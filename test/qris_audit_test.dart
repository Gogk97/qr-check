import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/services/qris_audit_service.dart';
import 'package:qr_check/services/qris_parser.dart';

/// Bangun payload QRIS EMVCo yang valid (CRC benar).
String buildPayload({
  String nmid = 'ID1024345514862',
  String merchant = 'Kopi Senja',
  String city = 'Jakarta',
  String mcc = '5812',
  String currency = '360',
  String country = 'ID',
  String? amount,
  String initiation = '12',
  bool duplicateMcc = false,
  String? rawTag51,
}) {
  final buf = StringBuffer('000201');
  buf.write('01${initiation.length.toString().padLeft(2, '0')}$initiation');
  final t51 = rawTag51 ?? nmid;
  buf.write('51${t51.length.toString().padLeft(2, '0')}$t51');
  buf.write('52${mcc.length.toString().padLeft(2, '0')}$mcc');
  if (duplicateMcc) {
    buf.write('52${mcc.length.toString().padLeft(2, '0')}$mcc');
  }
  buf.write('53${currency.length.toString().padLeft(2, '0')}$currency');
  if (amount != null) {
    buf.write('54${amount.length.toString().padLeft(2, '0')}$amount');
  }
  buf.write('58${country.length.toString().padLeft(2, '0')}$country');
  buf.write('59${merchant.length.toString().padLeft(2, '0')}$merchant');
  buf.write('60${city.length.toString().padLeft(2, '0')}$city');
  buf.write('6304');
  return buf.toString() + QRISParser.calculateCRC16(buf.toString());
}

ScannedItem item(String payload, {String id = 'x', String merchant = 'Kopi Senja', String nmid = 'ID1024345514862', double? amount = 25000}) {
  return ScannedItem(
    id: id,
    file: File('/tmp/audit_$id.jpg'),
    fileName: '$id.jpg',
    fileSize: 100,
    addedAt: DateTime(2026, 11, 18),
    isProcessing: false,
    hasQR: true,
    isQRIS: true,
    rawContent: payload,
    qrisDetails: QRISDetails(
      merchantName: merchant,
      merchantCity: 'Jakarta',
      postalCode: '12140',
      mcc: '5812',
      amount: amount,
      nmid: nmid,
      acquirer: 'BCA',
      isDynamic: true,
      isValidCRC: true,
      tags: const {},
    ),
  );
}

void main() {
  group('QrisAuditService — payload valid', () {
    test('skor 100 dan aman', () {
      final r = QrisAuditService.auditPayload(buildPayload(amount: '25000'));
      expect(r.score, 100);
      expect(r.verdict, AuditVerdict.safe);
      expect(r.crcValid, isTrue);
      expect(r.structureValid, isTrue);
      expect(r.findings, isEmpty);
      expect(r.nmid, 'ID1024345514862');
      expect(r.amount, 25000);
      expect(r.isDynamic, isTrue);
    });

    test('QRIS statis tanpa nominal tetap aman', () {
      final r = QrisAuditService.auditPayload(buildPayload(initiation: '11'));
      expect(r.verdict, AuditVerdict.safe);
      expect(r.isDynamic, isFalse);
      expect(r.amount, isNull);
    });
  });

  group('QrisAuditService — tag 51 bersarang (QRIS asli)', () {
    // Format nyata: 00 = penyelenggara, 02 = NMID, 03 = kategori.
    const tag51 = '0014ID.CO.QRIS.WWW0215ID20243589285110303UBE';

    test('NMID diambil dari sub-tag 02, bukan seluruh tag 51', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(rawTag51: tag51, amount: '56200'),
      );

      expect(r.nmid, 'ID2024358928511');
      expect(r.findings.any((f) => f.code == 'NMID_INVALID'), isFalse,
          reason: 'NMID pada sub-tag 02 valid');
      expect(r.score, 100);
      expect(r.verdict, AuditVerdict.safe);
    });

    test('NMID bersarang yang tidak valid tetap ditandai', () {
      const badTag51 = '0014ID.CO.QRIS.WWW0205ID1230303UBE';
      final r = QrisAuditService.auditPayload(
        buildPayload(rawTag51: badTag51, amount: '1000'),
      );
      expect(r.nmid, 'ID123');
      expect(r.findings.any((f) => f.code == 'NMID_INVALID'), isTrue);
    });
  });

  group('QrisAuditService — CRC', () {
    test('CRC diubah → temuan kritis & mencurigakan', () {
      final valid = buildPayload(amount: '25000');
      final tampered = '${valid.substring(0, valid.length - 4)}0000';
      final r = QrisAuditService.auditPayload(tampered);

      expect(r.crcValid, isFalse);
      expect(r.findings.any((f) => f.code == 'CRC_INVALID'), isTrue);
      expect(r.verdict, AuditVerdict.suspicious);
      expect(r.score, lessThan(60));
    });

    test('CRC hilang terdeteksi', () {
      final payload = buildPayload(amount: '25000');
      final withoutCrc = payload.substring(0, payload.length - 4);
      final r = QrisAuditService.auditPayload(withoutCrc);
      expect(r.findings.any((f) => f.code == 'CRC_MISSING'), isTrue);
    });
  });

  group('QrisAuditService — NMID', () {
    test('NMID tidak berawalan ID ditandai', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(nmid: '9999999999999999', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'NMID_INVALID'), isTrue);
    });

    test('NMID terlalu pendek ditandai', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(nmid: 'ID123', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'NMID_INVALID'), isTrue);
    });

    test('NMID dipakai dua merchant berbeda → konflik', () {
      final a = item(buildPayload(amount: '1000'), id: 'a', merchant: 'Toko A');
      final b = item(buildPayload(amount: '2000'), id: 'b', merchant: 'Toko B');

      final results = QrisAuditService.auditAll([a, b]);
      expect(results['a']!.findings.any((f) => f.code == 'NMID_CONFLICT'),
          isTrue);
      expect(results['b']!.findings.any((f) => f.code == 'NMID_CONFLICT'),
          isTrue);
      expect(results['a']!.verdict, isNot(AuditVerdict.safe));
    });

    test('NMID sama & merchant sama tidak dianggap konflik', () {
      final a = item(buildPayload(amount: '1000'), id: 'a');
      final b = item(buildPayload(amount: '2000'), id: 'b');
      final results = QrisAuditService.auditAll([a, b]);
      expect(results['a']!.findings.any((f) => f.code == 'NMID_CONFLICT'),
          isFalse);
    });
  });

  group('QrisAuditService — mata uang, negara, MCC', () {
    test('mata uang selain IDR ditandai kritis', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(currency: '840', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'CURRENCY_NOT_IDR'), isTrue);
      expect(r.verdict, isNot(AuditVerdict.safe));
    });

    test('negara selain ID ditandai', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(country: 'SG', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'COUNTRY_NOT_ID'), isTrue);
    });

    test('MCC bukan 4 digit ditandai', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(mcc: '58', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'MCC_INVALID'), isTrue);
    });
  });

  group('QrisAuditService — struktur', () {
    test('payload terpotong terdeteksi', () {
      final payload = buildPayload(amount: '25000');
      final truncated = payload.substring(0, payload.length - 12);
      final r = QrisAuditService.auditPayload(truncated);
      expect(r.structureValid, isFalse);
      expect(r.findings.any((f) => f.code.startsWith('TLV_')), isTrue);
    });

    test('tag ganda ditandai sebagai peringatan', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(amount: '1000', duplicateMcc: true),
      );
      expect(r.findings.any((f) => f.code == 'TLV_DUPLICATE'), isTrue);
      expect(r.verdict, isNot(AuditVerdict.suspicious));
    });

    test('bukan payload QRIS dikenali', () {
      final r = QrisAuditService.auditPayload('WIFI:S:MyNet;T:WPA;P:rahasia;;');
      expect(r.findings.any((f) => f.code == 'NOT_QRIS'), isTrue);
      expect(r.verdict, AuditVerdict.suspicious);
    });
  });

  group('QrisAuditService — nominal & merchant', () {
    test('QRIS statis dengan nominal diberi peringatan', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(initiation: '11', amount: '5000'),
      );
      expect(r.findings.any((f) => f.code == 'STATIC_WITH_AMOUNT'), isTrue);
      expect(r.verdict, AuditVerdict.safe, reason: 'peringatan ringan saja');
    });

    test('nama merchant berkarakter aneh ditandai', () {
      final r = QrisAuditService.auditPayload(
        buildPayload(merchant: 'Toko<Script>', amount: '1000'),
      );
      expect(r.findings.any((f) => f.code == 'MERCHANT_ODD_CHARS'), isTrue);
    });

    test('item tanpa payload diaudit sebagai mencurigakan', () {
      final noPayload = ScannedItem(
        id: 'n',
        file: File('/tmp/n.jpg'),
        fileName: 'n.jpg',
        fileSize: 10,
        addedAt: DateTime(2026, 1, 1),
        isProcessing: false,
        hasQR: true,
        isQRIS: true,
      );
      final r = QrisAuditService.audit(noPayload);
      expect(r.findings.single.code, 'NO_PAYLOAD');
      expect(r.verdict, AuditVerdict.suspicious);
    });
  });

  group('QrisAuditService — agregat', () {
    test('needsReview hanya mengembalikan yang tidak aman', () {
      final good = item(buildPayload(amount: '1000'), id: 'good');
      final badPayload = buildPayload(amount: '2000');
      final bad = item(
        '${badPayload.substring(0, badPayload.length - 4)}0000',
        id: 'bad',
      );

      final review = QrisAuditService.needsReview([good, bad]);
      expect(review.length, 1);
      expect(review.first.key.id, 'bad');
      expect(QrisAuditService.countNeedsReview([good, bad]), 1);
    });
  });
}
