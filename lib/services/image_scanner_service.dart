import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' hide BarcodeFormat;

import '../models/scanned_item.dart';
import 'qris_parser.dart';

class ImageScannerService {
  static final ImageScannerService _instance = ImageScannerService._internal();
  factory ImageScannerService() => _instance;
  ImageScannerService._internal();

  BarcodeScanner? _mlKitScanner;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  BarcodeScanner _getMLKitScanner() {
    _mlKitScanner ??= BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    return _mlKitScanner!;
  }

  /// Pindai satu file gambar dan kembalikan hasil analisisnya
  Future<ScannedItem> scanImage(File file, {required String id, bool forceDeepScan = false}) async {
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final fileSize = await file.length();

    final item = ScannedItem(
      id: id,
      file: file,
      fileName: fileName,
      fileSize: fileSize,
      addedAt: DateTime.now(),
      isProcessing: true,
    );

    try {
      String? detectedCode;
      bool mlKitRanSuccessfully = false;

      // 1. Deteksi utama dengan Google ML Kit (hardware-accelerated native) di mobile (Android / iOS)
      if (_isMobile) {
        try {
          final inputImage = InputImage.fromFilePath(file.path);
          final scanner = _getMLKitScanner();
          final barcodes = await scanner.processImage(inputImage);
          mlKitRanSuccessfully = true;
          if (barcodes.isNotEmpty) {
            detectedCode = barcodes.first.rawValue;
          }
        } catch (e) {
          debugPrint('ML Kit scanning error, fallback to ZXing: $e');
        }
      }

      // 2. Pure-Dart ZXing fallback:
      // Hanya dijalankan jika:
      // - Berjalan di desktop/web tanpa ML Kit native, ATAU
      // - ML Kit melempar exception/error, ATAU
      // - Dipaksa deep scan secara eksplisit.
      // Menghindari pemborosan CPU & isolate pada ribuan foto biasa yang bukan QR di mobile.
      if ((detectedCode == null || detectedCode.isEmpty) && (!mlKitRanSuccessfully || forceDeepScan)) {
        detectedCode = await compute(_scanWithZXing, file.path);
      }

      item.isProcessing = false;

      if (detectedCode != null && detectedCode.isNotEmpty) {
        final analysis = QRISParser.analyze(detectedCode);
        item.hasQR = analysis.isQR;
        item.isQRIS = analysis.isQRIS;
        item.qrType = analysis.qrType;
        item.rawContent = analysis.rawContent;
        item.qrisDetails = analysis.qrisDetails;
      } else {
        item.hasQR = false;
        item.isQRIS = false;
        item.qrType = 'none';
      }
    } catch (e) {
      item.isProcessing = false;
      item.errorMessage = e.toString();
    }

    return item;
  }

  /// Scanner pure Dart ZXing untuk multi-platform dan background isolate
  static Future<String?> _scanWithZXing(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) return null;

      // Optimasi ukuran jika gambar terlalu besar (>800px)
      // Resolusi 800px sangat tajam untuk QR decoder dan menghemat memori serta waktu komputasi binarizer
      const int maxDimension = 800;
      if (image.width > maxDimension || image.height > maxDimension) {
        image = img.copyResize(
          image,
          width: image.width > image.height ? maxDimension : (image.width * maxDimension ~/ image.height),
          height: image.height >= image.width ? maxDimension : (image.height * maxDimension ~/ image.width),
          interpolation: img.Interpolation.linear,
        );
      }

      final width = image.width;
      final height = image.height;
      final Int32List rgbPixels = Int32List(width * height);

      int idx = 0;
      for (final p in image) {
        final a = p.a.toInt();
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        rgbPixels[idx++] = (a << 24) | (r << 16) | (g << 8) | b;
      }

      final luminanceSource = RGBLuminanceSource(width, height, rgbPixels);
      final binaryBitmap = BinaryBitmap(HybridBinarizer(luminanceSource));
      final reader = QRCodeReader();

      final result = reader.decode(binaryBitmap);
      return result.text;
    } catch (_) {
      // Tidak ada QR atau gagal decode
      return null;
    }
  }

  void dispose() {
    _mlKitScanner?.close();
  }
}
