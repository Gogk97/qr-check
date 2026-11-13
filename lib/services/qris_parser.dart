import '../models/scanned_item.dart';

class QRISAnalysisResult {
  final bool isQR;
  final bool isQRIS;
  final String qrType; // 'qris', 'url', 'wifi', 'email', 'tel', 'text', 'none'
  final QRISDetails? qrisDetails;
  final String rawContent;

  QRISAnalysisResult({
    required this.isQR,
    required this.isQRIS,
    required this.qrType,
    this.qrisDetails,
    required this.rawContent,
  });
}

class QRISParser {
  /// Hitung CRC16-CCITT (polynomial 0x1021, init 0xFFFF) sesuai standar EMVCo MPM
  static String calculateCRC16(String str) {
    int crc = 0xFFFF;
    for (int i = 0; i < str.length; i++) {
      int c = str.codeUnitAt(i);
      crc ^= (c << 8);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// Parse TLV (Tag-Length-Value) string secara berurutan
  static Map<String, String> parseTLV(String payload) {
    final Map<String, String> tags = {};
    int index = 0;

    while (index < payload.length - 3) {
      final tag = payload.substring(index, index + 2);
      final lenStr = payload.substring(index + 2, index + 4);
      final len = int.tryParse(lenStr);

      if (len == null || (index + 4 + len) > payload.length) break;

      final value = payload.substring(index + 4, index + 4 + len);
      tags[tag] = value;

      index += 4 + len;
    }

    return tags;
  }

  /// Analisis teks QR untuk menentukan apakah ini QRIS resmi atau QR biasa
  static QRISAnalysisResult analyze(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return QRISAnalysisResult(
        isQR: false,
        isQRIS: false,
        qrType: 'none',
        rawContent: rawText,
      );
    }

    // Format EMVCo dasar dimulai dengan "000201"
    final isEMVCoStart = trimmed.startsWith('000201');
    final tags = parseTLV(trimmed);

    // Ciri khas QRIS Indonesia:
    // 1. Tag 00 = "01" (Payload Format Indicator)
    // 2. Tag 58 = "ID" (Country Code)
    // 3. Tag 53 = "360" (Currency Rupiah) atau adanya reversed domain ID.CO.QRIS / Tag 51 / Tag 26
    final country = tags['58'];
    final currency = tags['53'];
    final formatInd = tags['00'];

    final hasQRISIdentifier = trimmed.contains('ID.CO.QRIS') ||
        trimmed.contains('ID10') ||
        (country == 'ID' && (currency == '360' || tags.containsKey('51') || tags.containsKey('26')));

    final isQRIS = isEMVCoStart && formatInd == '01' && (country == 'ID' || hasQRISIdentifier);

    if (isQRIS) {
      // Validasi Checksum CRC16 (Tag 63)
      final crcTagValue = tags['63'];
      bool isValidCRC = false;
      if (crcTagValue != null && trimmed.length >= 8) {
        final payloadBeforeCRC = trimmed.substring(0, trimmed.length - 4);
        final expectedCRC = calculateCRC16(payloadBeforeCRC);
        isValidCRC = (expectedCRC == crcTagValue.toUpperCase());
      }

      // Ambil detail data merchant
      final pointOfInitiation = tags['01']; // 11: Static, 12: Dynamic
      final merchantName = tags['59'] ?? 'Merchant Tanpa Nama';
      final merchantCity = tags['60'] ?? '-';
      final postalCode = tags['61'] ?? '-';
      final mcc = tags['52'] ?? '-';
      final amount = tags['54'] != null ? double.tryParse(tags['54']!) : null;

      // Parse sub-tag untuk NMID / Merchant Info
      String nmid = '';
      String acquirer = '';

      if (tags.containsKey('51')) {
        final sub = parseTLV(tags['51']!);
        nmid = sub['02'] ?? tags['51']!;
      }
      if (nmid.isEmpty && tags.containsKey('26')) {
        final sub = parseTLV(tags['26']!);
        nmid = sub['01'] ?? sub['02'] ?? '';
        acquirer = sub['00'] ?? '';
      }

      if (acquirer.isEmpty && tags.containsKey('51')) {
        final sub = parseTLV(tags['51']!);
        acquirer = sub['00'] ?? '';
      }

      final details = QRISDetails(
        merchantName: merchantName,
        merchantCity: merchantCity,
        postalCode: postalCode,
        mcc: mcc,
        amount: amount,
        nmid: nmid,
        acquirer: acquirer,
        isDynamic: pointOfInitiation == '12',
        isValidCRC: isValidCRC,
        tags: tags,
      );

      return QRISAnalysisResult(
        isQR: true,
        isQRIS: true,
        qrType: 'qris',
        qrisDetails: details,
        rawContent: trimmed,
      );
    }

    // Deteksi tipe QR code umum non-QRIS
    String qrType = 'text';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      qrType = 'url';
    } else if (lower.startsWith('wifi:')) {
      qrType = 'wifi';
    } else if (lower.startsWith('mailto:')) {
      qrType = 'email';
    } else if (lower.startsWith('tel:')) {
      qrType = 'tel';
    }

    return QRISAnalysisResult(
      isQR: true,
      isQRIS: false,
      qrType: qrType,
      rawContent: trimmed,
    );
  }
}
