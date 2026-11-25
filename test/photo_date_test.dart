import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/services/export_service.dart';

ScannedItem _item({
  DateTime? addedAt,
  DateTime? photoDate,
  double? amount = 25000,
}) {
  return ScannedItem(
    id: 'x',
    file: File('/tmp/x.jpg'),
    fileName: 'x.jpg',
    fileSize: 1000,
    addedAt: addedAt ?? DateTime(2026, 11, 25, 9, 0),
    photoDate: photoDate,
    isProcessing: false,
    hasQR: true,
    isQRIS: true,
    qrisDetails: QRISDetails(
      merchantName: 'Kopi Senja',
      merchantCity: 'Jakarta',
      postalCode: '12140',
      mcc: '5812',
      amount: amount,
      nmid: 'ID1024345514862',
      acquirer: 'BCA',
      isDynamic: true,
      isValidCRC: true,
      tags: const {},
    ),
  );
}

void main() {
  group('ScannedItem.reportDate', () {
    test('memakai tanggal foto bila tersedia', () {
      final item = _item(
        addedAt: DateTime(2026, 11, 25, 9, 0), // waktu pindai
        photoDate: DateTime(2024, 3, 14, 16, 20), // tanggal foto asli
      );
      expect(item.reportDate, DateTime(2024, 3, 14, 16, 20));
    });

    test('fallback ke waktu pindai untuk data lama', () {
      final item = _item(addedAt: DateTime(2026, 11, 25, 9, 0));
      expect(item.reportDate, DateTime(2026, 11, 25, 9, 0));
    });

    test('photoDate bertahan setelah serialisasi JSON', () {
      final item = _item(photoDate: DateTime(2023, 8, 1, 7, 30));
      final restored = ScannedItem.fromJson(item.toJson());
      expect(restored.photoDate, DateTime(2023, 8, 1, 7, 30));
      expect(restored.reportDate, DateTime(2023, 8, 1, 7, 30));
    });

    test('data lama tanpa field photoDate tetap aman', () {
      final legacy = <String, dynamic>{
        'id': 'legacy',
        'filePath': '/tmp/legacy.jpg',
        'fileName': 'legacy.jpg',
        'fileSize': 10,
        'addedAt': '2026-01-05T08:00:00.000',
      };
      final item = ScannedItem.fromJson(legacy);
      expect(item.photoDate, isNull);
      expect(item.reportDate, DateTime(2026, 1, 5, 8, 0));
    });
  });

  group('Export memakai tanggal foto', () {
    test('CSV menulis tanggal foto, bukan tanggal pindai', () {
      final csv = ExportService.buildCsv([
        _item(
          addedAt: DateTime(2026, 11, 25, 9, 0),
          photoDate: DateTime(2024, 3, 14, 16, 20),
        ),
      ]);
      expect(csv, contains('2024-03-14'));
      expect(csv, isNot(contains('2026-11-25')));
    });

    test('Excel XML juga memakai tanggal foto', () {
      final xml = ExportService.buildExcelXml([
        _item(
          addedAt: DateTime(2026, 11, 25, 9, 0),
          photoDate: DateTime(2024, 3, 14, 16, 20),
        ),
      ]);
      expect(xml, contains('2024-03-14'));
    });
  });
}
