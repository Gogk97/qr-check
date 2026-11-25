import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/screens/report_screen.dart';
import 'package:qr_check/services/export_service.dart';
import 'package:qr_check/theme/app_theme.dart';

ScannedItem _item({
  required String id,
  double? amount,
  String merchant = 'Kopi Senja',
  String city = 'Jakarta',
  bool isQRIS = true,
  DateTime? addedAt,
}) {
  return ScannedItem(
    id: id,
    file: File('/tmp/qristal_export_$id.jpg'),
    fileName: '$id.jpg',
    fileSize: 1000,
    addedAt: addedAt ?? DateTime(2026, 11, 18, 10, 30),
    isProcessing: false,
    hasQR: true,
    isQRIS: isQRIS,
    qrisDetails: QRISDetails(
      merchantName: merchant,
      merchantCity: city,
      postalCode: '12140',
      mcc: '5812',
      amount: amount,
      nmid: 'ID1024345514862',
      acquirer: 'BCA',
      isDynamic: amount != null,
      isValidCRC: true,
      tags: const {},
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('ExportService.reportable', () {
    test('hanya QRIS dengan nominal > 0', () {
      final items = [
        _item(id: 'a', amount: 25000),
        _item(id: 'b', amount: null),
        _item(id: 'c', amount: 0),
        _item(id: 'd', amount: 15000, isQRIS: false),
      ];
      final result = ExportService.reportable(items);
      expect(result.length, 1);
      expect(result.first.id, 'a');
    });

    test('diurutkan dari yang terbaru', () {
      final items = [
        _item(id: 'lama', amount: 1000, addedAt: DateTime(2026, 11, 1)),
        _item(id: 'baru', amount: 2000, addedAt: DateTime(2026, 11, 19)),
      ];
      expect(ExportService.reportable(items).first.id, 'baru');
    });
  });

  group('ExportService.buildCsv', () {
    test('memuat BOM, header, dan data terformat', () {
      final csv = ExportService.buildCsv([
        _item(id: 'a', amount: 25000, merchant: 'Kopi, Senja'),
      ]);

      expect(csv.startsWith('\uFEFF'), isTrue, reason: 'BOM UTF-8 untuk Excel');
      expect(csv, contains('Tanggal,Jam,Merchant'));
      expect(csv, contains('"Kopi, Senja"'), reason: 'koma harus di-escape');
      expect(csv, contains('25000'));
      expect(csv, contains('2026-11-18'));
    });

    test('meng-escape tanda kutip ganda', () {
      final csv = ExportService.buildCsv([
        _item(id: 'a', amount: 1000, merchant: 'Toko "Maju"'),
      ]);
      expect(csv, contains('"Toko ""Maju"""'));
    });
  });

  group('ExportService.buildExcelXml', () {
    test('menghasilkan workbook XML yang valid', () {
      final xml = ExportService.buildExcelXml([
        _item(id: 'a', amount: 25000),
        _item(id: 'b', amount: 15000),
      ]);

      expect(xml, contains('<?mso-application progid="Excel.Sheet"?>'));
      expect(xml, contains('<Worksheet ss:Name="Laporan QRIS">'));
      expect(xml, contains('ss:Type="Number">25000'));
      expect(xml, contains('TOTAL'));
      expect(xml, contains('40000'), reason: 'total 25.000 + 15.000');
      expect(xml, contains('</Workbook>'));
    });

    test('meng-escape karakter XML pada nama merchant', () {
      final xml = ExportService.buildExcelXml([
        _item(id: 'a', amount: 1000, merchant: 'A & B <Store>'),
      ]);
      expect(xml, contains('A &amp; B &lt;Store&gt;'));
      expect(xml, isNot(contains('<Store>')));
    });
  });

  group('ReportScreen', () {
    testWidgets('menampilkan empty state bila belum ada nominal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ReportScreen(items: [_item(id: 'a', amount: null)]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Belum ada data nominal'), findsOneWidget);
      expect(find.text('Laporan QRIS'), findsOneWidget);
    });

    testWidgets('menampilkan ringkasan dan tombol ekspor saat ada data', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ReportScreen(items: [
            _item(id: 'a', amount: 25000),
            _item(id: 'b', amount: 15000, merchant: 'Bakery Aroma'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Transaksi'), findsOneWidget);
      expect(find.text('Rata-rata'), findsOneWidget);
      expect(find.textContaining('Ekspor 2 transaksi'), findsOneWidget);
      expect(find.text('Bakery Aroma'), findsOneWidget);
    });
  });
}
