import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/services/qris_parser.dart';

void main() {
  test('Parses valid static QRIS', () {
    const rawQRIS = "00020101021151440014ID.CO.QRIS.WWW0215ID10200210005570303UMI5204541153033605802ID5916TOKO BERKAH JAYA6007JAKARTA61051234062070703A0163044D20";
    final result = QRISParser.analyze(rawQRIS);
    expect(result.isQR, true);
    expect(result.isQRIS, true);
    expect(result.qrisDetails?.merchantName, 'TOKO BERKAH JAYA');
    expect(result.qrisDetails?.merchantCity, 'JAKARTA');
    expect(result.qrisDetails?.nmid, 'ID1020021000557');
    expect(result.qrisDetails?.isDynamic, false);
    expect(result.qrisDetails?.isValidCRC, true);
  });

  test('Parses dynamic QRIS with amount', () {
    // Dynamic QRIS has tag 01 = 12 and tag 54 = amount
    // KAFE SANTUY is 11 chars
    const payloadBeforeCRC = "000201"
        "010212"
        "51440014ID.CO.QRIS.WWW0215ID10200210005570303UMI"
        "52045411"
        "5303360"
        "540550000"
        "5802ID"
        "5911KAFE SANTUY"
        "6007BANDUNG"
        "610540115"
        "62070703A01"
        "6304";
    final crc = QRISParser.calculateCRC16(payloadBeforeCRC);
    final fullQRIS = "$payloadBeforeCRC$crc";

    final result = QRISParser.analyze(fullQRIS);
    expect(result.isQR, true);
    expect(result.isQRIS, true);
    expect(result.qrisDetails?.merchantName, 'KAFE SANTUY');
    expect(result.qrisDetails?.merchantCity, 'BANDUNG');
    expect(result.qrisDetails?.amount, 50000.0);
    expect(result.qrisDetails?.isDynamic, true);
    expect(result.qrisDetails?.isValidCRC, true);
  });

  test('Parses regular QR URL', () {
    const rawURL = "https://flutter.dev";
    final result = QRISParser.analyze(rawURL);
    expect(result.isQR, true);
    expect(result.isQRIS, false);
    expect(result.qrType, 'url');
  });

  test('Parses WiFi QR', () {
    const rawWifi = "WIFI:S:MyNetwork;T:WPA;P:SecretPassword;;";
    final result = QRISParser.analyze(rawWifi);
    expect(result.isQR, true);
    expect(result.isQRIS, false);
    expect(result.qrType, 'wifi');
  });
}
