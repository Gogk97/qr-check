import 'dart:io';

enum ScanCategory {
  qris,
  regularQr,
  noQr,
  error,
}

class QRISDetails {
  final String merchantName;
  final String merchantCity;
  final String postalCode;
  final String mcc;
  final double? amount;
  final String nmid;
  final String acquirer;
  final bool isDynamic;
  final bool isValidCRC;
  final Map<String, String> tags;

  QRISDetails({
    required this.merchantName,
    required this.merchantCity,
    required this.postalCode,
    required this.mcc,
    this.amount,
    required this.nmid,
    required this.acquirer,
    required this.isDynamic,
    required this.isValidCRC,
    required this.tags,
  });

  String get displayAcquirer {
    final str = (acquirer.isNotEmpty ? acquirer : (tags['26'] ?? tags['51'] ?? tags['52'] ?? '')).toUpperCase();
    final merchant = merchantName.toUpperCase();
    final combined = '$str $merchant';

    if (combined.contains('BCA')) return 'BCA';
    if (combined.contains('GOPAY') || combined.contains('GO-PAY') || combined.contains('GOJEK')) return 'GoPay';
    if (combined.contains('OVO')) return 'OVO';
    if (combined.contains('DANA')) return 'DANA';
    if (combined.contains('SHOPEE') || combined.contains('SHOPEEPAY')) return 'ShopeePay';
    if (combined.contains('MANDIRI')) return 'Bank Mandiri';
    if (combined.contains('BRI') || combined.contains('BANK RAKYAT')) return 'BRI';
    if (combined.contains('BNI') || combined.contains('NEGARA INDONESIA')) return 'BNI';
    if (combined.contains('LINKAJA') || combined.contains('TELKOM')) return 'LinkAja';
    if (combined.contains('BSI') || combined.contains('SYARIAH INDONESIA')) return 'BSI';
    if (combined.contains('NOBU')) return 'Bank Nobu';
    if (combined.contains('CIMB')) return 'CIMB Niaga';
    if (combined.contains('PERMATA')) return 'Bank Permata';
    if (combined.contains('DANAMON')) return 'Danamon';
    if (combined.contains('MAYBANK')) return 'Maybank';
    if (combined.contains('OCBC')) return 'OCBC NISP';
    if (combined.contains('JAGO')) return 'Bank Jago';
    if (combined.contains('SEABANK')) return 'SeaBank';
    if (combined.contains('NEO')) return 'Bank Neo Commerce';

    if (acquirer.trim().isNotEmpty && !acquirer.contains('.')) {
      return acquirer.trim();
    }
    return 'Lainnya / QRIS Umum';
  }
  Map<String, dynamic> toJson() => {
        'merchantName': merchantName,
        'merchantCity': merchantCity,
        'postalCode': postalCode,
        'mcc': mcc,
        'amount': amount,
        'nmid': nmid,
        'acquirer': acquirer,
        'isDynamic': isDynamic,
        'isValidCRC': isValidCRC,
        'tags': tags,
      };

  factory QRISDetails.fromJson(Map<String, dynamic> json) => QRISDetails(
        merchantName: json['merchantName'] ?? '',
        merchantCity: json['merchantCity'] ?? '',
        postalCode: json['postalCode'] ?? '',
        mcc: json['mcc'] ?? '',
        amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : null,
        nmid: json['nmid'] ?? '',
        acquirer: json['acquirer'] ?? '',
        isDynamic: json['isDynamic'] ?? false,
        isValidCRC: json['isValidCRC'] ?? false,
        tags: Map<String, String>.from(json['tags'] ?? {}),
      );
}

class ScannedItem {
  final String id;
  final File file;
  final String fileName;
  final String originalFileName;
  final String? assetId;
  final int fileSize;
  final DateTime addedAt;
  bool isProcessing;
  bool hasQR;
  bool isQRIS;
  String? rawContent;
  String qrType; // 'qris', 'url', 'wifi', 'email', 'tel', 'text', 'none'
  QRISDetails? qrisDetails;
  String? errorMessage;
  bool isSelected;

  ScannedItem({
    required this.id,
    required this.file,
    required this.fileName,
    String? originalFileName,
    this.assetId,
    required this.fileSize,
    required this.addedAt,
    this.isProcessing = true,
    this.hasQR = false,
    this.isQRIS = false,
    this.rawContent,
    this.qrType = 'none',
    this.qrisDetails,
    this.errorMessage,
    this.isSelected = false,
  }) : originalFileName = originalFileName ?? fileName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': file.path,
        'fileName': fileName,
        'originalFileName': originalFileName,
        'assetId': assetId,
        'fileSize': fileSize,
        'addedAt': addedAt.toIso8601String(),
        'isProcessing': isProcessing,
        'hasQR': hasQR,
        'isQRIS': isQRIS,
        'rawContent': rawContent,
        'qrType': qrType,
        'qrisDetails': qrisDetails?.toJson(),
        'errorMessage': errorMessage,
      };

  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
        id: json['id'] ?? '',
        file: File(json['filePath'] ?? ''),
        fileName: json['fileName'] ?? '',
        originalFileName: json['originalFileName'] ?? json['fileName'] ?? '',
        assetId: json['assetId'],
        fileSize: json['fileSize'] ?? 0,
        addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : DateTime.now(),
        isProcessing: json['isProcessing'] ?? false,
        hasQR: json['hasQR'] ?? false,
        isQRIS: json['isQRIS'] ?? false,
        rawContent: json['rawContent'],
        qrType: json['qrType'] ?? 'none',
        qrisDetails: json['qrisDetails'] != null ? QRISDetails.fromJson(json['qrisDetails']) : null,
        errorMessage: json['errorMessage'],
      );

  ScanCategory get category {
    if (errorMessage != null) return ScanCategory.error;
    if (isQRIS) return ScanCategory.qris;
    if (hasQR) return ScanCategory.regularQr;
    return ScanCategory.noQr;
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
