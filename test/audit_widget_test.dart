import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/screens/audit_screen.dart';
import 'package:qr_check/services/qris_audit_service.dart';
import 'package:qr_check/services/qris_parser.dart';
import 'package:qr_check/theme/app_theme.dart';
import 'package:qr_check/widgets/qris_audit_card.dart';

String _payload({String merchant = 'Kopi Senja', String? amount = '25000'}) {
  String tlv(String tag, String value) =>
      '$tag${value.length.toString().padLeft(2, '0')}$value';

  final buf = StringBuffer('000201')
    ..write(tlv('01', '12'))
    ..write(tlv('51', 'ID1024345514862'))
    ..write(tlv('52', '5812'))
    ..write(tlv('53', '360'));
  if (amount != null) buf.write(tlv('54', amount));
  buf
    ..write(tlv('58', 'ID'))
    ..write(tlv('59', merchant))
    ..write(tlv('60', 'Jakarta'))
    ..write('6304');
  return buf.toString() + QRISParser.calculateCRC16(buf.toString());
}

ScannedItem _item(String id, String raw, {String merchant = 'Kopi Senja'}) {
  return ScannedItem(
    id: id,
    file: File('/tmp/aw_$id.jpg'),
    fileName: '$id.jpg',
    fileSize: 10,
    addedAt: DateTime(2026, 11, 18),
    isProcessing: false,
    hasQR: true,
    isQRIS: true,
    rawContent: raw,
    qrisDetails: QRISDetails(
      merchantName: merchant,
      merchantCity: 'Jakarta',
      postalCode: '12140',
      mcc: '5812',
      amount: 25000,
      nmid: 'ID1024345514862',
      acquirer: 'BCA',
      isDynamic: true,
      isValidCRC: true,
      tags: const {},
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('QrisAuditCard', () {
    testWidgets('menampilkan skor dan kesimpulan aman', (tester) async {
      final result = QrisAuditService.auditPayload(_payload());

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: QrisAuditCard(result: result)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('QRIS terlihat aman'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.textContaining('Semua pemeriksaan lolos'), findsOneWidget);
    });

    testWidgets('menampilkan temuan saat payload diubah', (tester) async {
      final valid = _payload();
      final tampered = '${valid.substring(0, valid.length - 4)}0000';
      final result = QrisAuditService.auditPayload(tampered);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: QrisAuditCard(result: result)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mencurigakan'), findsOneWidget);
      expect(find.text('Checksum tidak cocok'), findsOneWidget);
    });
  });

  group('AuditScreen', () {
    testWidgets('menghitung aman dan mencurigakan', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final good = _item('good', _payload());
      final badRaw = _payload(merchant: 'Toko Lain');
      final bad = _item(
        'bad',
        '${badRaw.substring(0, badRaw.length - 4)}0000',
        merchant: 'Toko Lain',
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: AuditScreen(items: [good, bad]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Audit QRIS'), findsOneWidget);
      expect(find.text('Aman'), findsOneWidget);
      expect(find.text('Mencurigakan'), findsOneWidget);
      // Dua QRIS dihitung pada daftar.
      expect(find.text('2 QRIS'), findsOneWidget);
      expect(find.text('Toko Lain'), findsOneWidget);
    });

    testWidgets('empty state saat belum ada QRIS', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AuditScreen(items: []),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Belum ada QRIS untuk diaudit'), findsOneWidget);
    });
  });
}
