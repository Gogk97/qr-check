import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scanned_item.dart';
import '../utils/app_log.dart';

/// Manajemen penyimpanan gambar hasil pindai.
///
/// Tanggung jawab:
/// 1. **Kompresi saat simpan** — foto QR/QRIS disalin ke storage aplikasi dalam
///    versi teroptimasi (maks. 1280 px, JPEG q88). QR sudah diparse menjadi teks,
///    jadi foto penuh tidak diperlukan lagi; versi ringan ini hanya untuk preview
///    dan tombol "Bagikan Foto".
/// 2. **Retensi otomatis** — item lebih tua dari 30 hari atau melebihi 300 item
///    dibuang (file-nya ikut dihapus) agar penyimpanan tidak menumpuk.
/// 3. **Housekeeping** — membersihkan file yatim yang tidak lagi dirujuk item.
///
/// Semua proses berat (decode/resize/encode) berjalan di isolate terpisah lewat
/// [compute] supaya UI tidak tersendat saat memindai ratusan foto.
class ImageStorageService {
  ImageStorageService._();

  static const String dirName = 'qris_permanently_saved_images';

  /// Sisi terpanjang maksimum gambar tersimpan.
  static const int maxDimension = 1280;

  /// Kualitas JPEG. 88 dipilih agar QR tetap tajam bila dipindai ulang.
  static const int jpegQuality = 88;

  /// File di bawah ambang ini dibiarkan apa adanya (hemat CPU, hasil sama).
  static const int skipCompressBelowBytes = 150 * 1024;

  /// Item lebih tua dari ini akan dibersihkan otomatis.
  static const Duration retention = Duration(days: 30);

  /// Batas jumlah item yang disimpan.
  static const int maxItems = 300;

  static Directory? _cachedDir;

  /// Folder penyimpanan gambar (Documents/qris_permanently_saved_images).
  static Future<Directory> storageDir() async {
    final cached = _cachedDir;
    if (cached != null && await cached.exists()) return cached;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// Simpan salinan teroptimasi dari [source].
  ///
  /// Mengembalikan file di storage aplikasi. Bila optimasi gagal (format tak
  /// dikenal, memori kurang), fallback ke penyalinan biasa agar tidak ada data
  /// yang hilang.
  static Future<File> saveOptimized(File source) async {
    final dir = await storageDir();
    if (source.path.startsWith(dir.path)) return source;

    final ext = _safeExtension(source.path);
    final base = _safeBaseName(source.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final originalSize = await _lengthOrZero(source);

    // File kecil: salin apa adanya.
    if (originalSize > 0 && originalSize <= skipCompressBelowBytes) {
      return _copyTo(source, File('${dir.path}/${stamp}_$base.$ext'));
    }

    try {
      final bytes = await source.readAsBytes();
      final compressed = await compressBytes(bytes);

      if (compressed == null || compressed.isEmpty) {
        return _copyTo(source, File('${dir.path}/${stamp}_$base.$ext'));
      }

      // Jika hasil kompresi justru lebih besar (mis. PNG kecil), pakai aslinya.
      if (originalSize > 0 && compressed.length >= originalSize) {
        return _copyTo(source, File('${dir.path}/${stamp}_$base.$ext'));
      }

      final target = File('${dir.path}/${stamp}_$base.jpg');
      await target.writeAsBytes(compressed, flush: true);
      AppLog.d(
        '🗜️ Optimasi: ${_kb(originalSize)} → ${_kb(compressed.length)} '
        '(${_savingPercent(originalSize, compressed.length)}% hemat)',
      );
      return target;
    } catch (e) {
      AppLog.d('⚠️ Optimasi gambar gagal, fallback salin: $e');
      return _copyTo(source, File('${dir.path}/${stamp}_$base.$ext'));
    }
  }

  /// Kompres byte gambar di isolate (dipakai internal & unit test).
  ///
  /// Mengembalikan `null` bila format tidak dikenali.
  static Future<Uint8List?> compressBytes(
    Uint8List bytes, {
    int maxSide = maxDimension,
    int quality = jpegQuality,
  }) {
    return compute(
      _compressInIsolate,
      _CompressJob(bytes: bytes, maxDimension: maxSide, quality: quality),
    );
  }

  /// Ganti nama file item menjadi nama yang mudah dibaca dari isi QRIS,
  /// mis. `2026-11-19_Kopi_Senja_Rp25000_BCA.jpg`.
  ///
  /// Mengembalikan [File] baru; bila gagal, file lama dikembalikan.
  static Future<File> autoRename(ScannedItem item) async {
    try {
      final source = item.file;
      if (!await source.exists()) return source;

      final dir = await storageDir();
      if (!source.path.startsWith(dir.path)) return source;

      final d = item.qrisDetails;
      final date = DateFormat('yyyy-MM-dd').format(item.addedAt);
      final merchant = _slug(d?.merchantName ?? 'QRIS');
      final amount = (d?.amount ?? 0) > 0
          ? 'Rp${(d!.amount!).toStringAsFixed(0)}'
          : null;
      final acquirer = _slug(d?.displayAcquirer ?? '');

      final parts = <String>[
        date,
        merchant,
        if (amount != null) amount,
        if (acquirer.isNotEmpty) acquirer,
      ];
      var base = parts.join('_');
      if (base.length > 90) base = base.substring(0, 90);

      final ext = _safeExtension(source.path);
      var target = File('${dir.path}/$base.$ext');
      var counter = 2;
      while (await target.exists() && target.path != source.path) {
        target = File('${dir.path}/${base}_$counter.$ext');
        counter++;
      }

      if (target.path == source.path) return source;

      final renamed = await source.rename(target.path);
      AppLog.d('🏷️ Rename: ${source.uri.pathSegments.last} → ${target.uri.pathSegments.last}');
      return renamed;
    } catch (e) {
      AppLog.d('⚠️ Gagal rename file: $e');
      return item.file;
    }
  }

  static String _slug(String input) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'QRIS';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  /// Total ukuran folder gambar (byte).
  static Future<int> usageBytes() async {
    try {
      final dir = await storageDir();
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          total += await _lengthOrZero(entity);
        }
      }
      return total;
    } catch (e) {
      AppLog.d('⚠️ Gagal menghitung pemakaian penyimpanan: $e');
      return 0;
    }
  }

  /// Hapus file milik item yang dibuang. Aman bila file sudah tidak ada.
  static Future<int> deleteFiles(Iterable<File> files) async {
    var deleted = 0;
    for (final f in files) {
      try {
        if (await f.exists()) {
          await f.delete();
          deleted++;
        }
      } catch (e) {
        AppLog.d('⚠️ Gagal menghapus file ${f.path}: $e');
      }
    }
    return deleted;
  }

  /// Hapus file di folder storage yang tidak lagi dirujuk item mana pun.
  static Future<int> purgeOrphanFiles(Set<String> keepPaths) async {
    try {
      final dir = await storageDir();
      var deleted = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && !keepPaths.contains(entity.path)) {
          try {
            await entity.delete();
            deleted++;
          } catch (_) {}
        }
      }
      if (deleted > 0) {
        AppLog.d('🧹 $deleted file yatim dibersihkan dari storage');
      }
      return deleted;
    } catch (e) {
      AppLog.d('⚠️ Gagal membersihkan file yatim: $e');
      return 0;
    }
  }

  /// Terapkan kebijakan retensi pada daftar item.
  ///
  /// Aturan: buang item lebih tua dari [retention], lalu batasi maksimal
  /// [maxItems] item terbaru. File dari item yang dibuang ikut dihapus.
  ///
  /// Mengembalikan [RetentionResult] berisi item yang dipertahankan beserta
  /// statistik pembersihan.
  static Future<RetentionResult> applyRetention(List<ScannedItem> items) async {
    if (items.isEmpty) return const RetentionResult(items: [], removed: 0, bytesFreed: 0);

    final now = DateTime.now();
    final cutoff = now.subtract(retention);

    // Urutkan terbaru lebih dulu agar batas maxItems mempertahankan yang baru.
    final sorted = List<ScannedItem>.from(items)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    final kept = <ScannedItem>[];
    final removed = <ScannedItem>[];

    for (final item in sorted) {
      final tooOld = item.addedAt.isBefore(cutoff);
      final overQuota = kept.length >= maxItems;
      if (tooOld || overQuota) {
        removed.add(item);
      } else {
        kept.add(item);
      }
    }

    if (removed.isEmpty) {
      return RetentionResult(items: sorted, removed: 0, bytesFreed: 0);
    }

    var bytesFreed = 0;
    for (final item in removed) {
      bytesFreed += await _lengthOrZero(item.file);
    }
    await deleteFiles(removed.map((e) => e.file));

    AppLog.d(
      '🧹 Retensi: ${removed.length} item dibuang, '
      '${_kb(bytesFreed)} dibebaskan (sisa ${kept.length} item)',
    );

    return RetentionResult(items: kept, removed: removed.length, bytesFreed: bytesFreed);
  }

  // ------------------------------------------------------------------ helpers

  static Future<File> _copyTo(File source, File target) async {
    try {
      return await source.copy(target.path);
    } catch (e) {
      AppLog.d('⚠️ Gagal menyalin file: $e');
      return source;
    }
  }

  static Future<int> _lengthOrZero(File file) async {
    try {
      if (await file.exists()) return await file.length();
    } catch (_) {}
    return 0;
  }

  static String _safeBaseName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final cleaned = base.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'img' : (cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned);
  }

  static String _safeExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'jpg';
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} KB';

  static String _savingPercent(int before, int after) {
    if (before <= 0) return '0';
    return (100 - (after * 100 / before)).toStringAsFixed(0);
  }
}

/// Hasil penerapan kebijakan retensi.
class RetentionResult {
  final List<ScannedItem> items;
  final int removed;
  final int bytesFreed;

  const RetentionResult({
    required this.items,
    required this.removed,
    required this.bytesFreed,
  });

  bool get didRemove => removed > 0;
}

/// Payload untuk kompresi di isolate.
class _CompressJob {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;

  const _CompressJob({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });
}

/// Fungsi top-level (wajib untuk `compute`): decode → orientasi → resize → JPEG.
Uint8List? _compressInIsolate(_CompressJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;

  // Hormati orientasi EXIF agar foto kamera tidak miring.
  final oriented = img.bakeOrientation(decoded);

  img.Image output = oriented;
  if (oriented.width > job.maxDimension || oriented.height > job.maxDimension) {
    output = oriented.width >= oriented.height
        ? img.copyResize(
            oriented,
            width: job.maxDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            oriented,
            height: job.maxDimension,
            interpolation: img.Interpolation.average,
          );
  }

  return Uint8List.fromList(img.encodeJpg(output, quality: job.quality));
}
