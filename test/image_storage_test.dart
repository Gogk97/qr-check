import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_check/services/image_storage_service.dart';

/// Gambar sintetis menyerupai **foto kamera**: resolusi besar + noise acak
/// deterministik, lalu di-encode JPEG q100 (seperti output sensor).
/// Noise membuat kompresi sulit, sehingga penghematan yang terukur
/// mencerminkan skenario nyata, bukan gambar polos yang mudah dikompres.
Uint8List _buildCameraLikeJpeg({int width = 3000, int height = 2000}) {
  final image = img.Image(width: width, height: height);
  var seed = 12345;
  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (next() >> 16) & 0xFF;
      final g = (next() >> 8) & 0xFF;
      final b = next() & 0xFF;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  group('ImageStorageService.compressBytes', () {
    test('mengecilkan foto besar dan membatasi dimensi maksimum', () async {
      final source = _buildCameraLikeJpeg();
      final compressed = await ImageStorageService.compressBytes(source);

      expect(compressed, isNotNull);
      final decoded = img.decodeImage(compressed!);
      expect(decoded, isNotNull);

      // Sisi terpanjang tidak boleh melebihi batas.
      expect(decoded!.width <= ImageStorageService.maxDimension, isTrue,
          reason: 'lebar ${decoded.width} melebihi ${ImageStorageService.maxDimension}');
      expect(decoded.height <= ImageStorageService.maxDimension, isTrue,
          reason: 'tinggi ${decoded.height} melebihi ${ImageStorageService.maxDimension}');

      // Harus benar-benar lebih kecil dari sumber.
      final savingPercent = 100 - (compressed.length * 100 / source.length);
      expect(compressed.length, lessThan(source.length),
          reason: 'hasil ${compressed.length}B tidak lebih kecil dari ${source.length}B');
      expect(savingPercent, greaterThan(50),
          reason: 'hemat hanya ${savingPercent.toStringAsFixed(1)}%, diharapkan >50%');
    });

    test('tidak memperbesar gambar yang sudah kecil', () async {
      final small = img.Image(width: 200, height: 150);
      img.fill(small, color: img.ColorRgb8(11, 135, 96));
      final source = Uint8List.fromList(img.encodePng(small));

      final compressed = await ImageStorageService.compressBytes(source);
      expect(compressed, isNotNull);

      final decoded = img.decodeImage(compressed!);
      expect(decoded!.width, 200);
      expect(decoded.height, 150);
    });

    test('mengembalikan null untuk data yang bukan gambar', () async {
      final garbage = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final result = await ImageStorageService.compressBytes(garbage);
      expect(result, isNull);
    });
  });

  group('RetentionResult', () {
    test('didRemove false saat tidak ada yang dibuang', () {
      const result = RetentionResult(items: [], removed: 0, bytesFreed: 0);
      expect(result.didRemove, isFalse);
    });
  });
}
