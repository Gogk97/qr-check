import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scanned_item.dart';
import '../utils/app_log.dart';
import 'image_storage_service.dart';

/// Ringkasan isi file backup (tanpa memulihkan apa pun).
class BackupSummary {
  const BackupSummary({
    required this.itemCount,
    required this.imageCount,
    required this.exportedAt,
    required this.formatVersion,
    required this.appVersion,
  });

  final int itemCount;
  final int imageCount;
  final DateTime? exportedAt;
  final int formatVersion;
  final String appVersion;
}

/// Hasil pemulihan.
class RestoreResult {
  const RestoreResult({
    required this.added,
    required this.skipped,
    required this.missingImages,
  });

  final int added;
  final int skipped;
  final int missingImages;

  bool get hasAnything => added > 0;
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Backup & restore seluruh data QRIS ke satu file `.qristal`.
///
/// Format: arsip ZIP berisi
/// - `manifest.json` — versi format, waktu ekspor, jumlah item
/// - `items.json` — seluruh metadata item (termasuk favorit & tanggal foto)
/// - `images/<nama file>` — gambar QRIS yang disimpan aplikasi
///
/// Semua proses lokal — tidak ada data yang dikirim ke server.
class BackupService {
  BackupService._();

  static const String appId = 'qristal';
  static const int formatVersion = 1;
  static const String fileExtension = 'qristal';
  static const String mimeType = 'application/zip';

  static final DateFormat _stamp = DateFormat('yyyyMMdd_HHmm');

  // ------------------------------------------------------------------ export

  /// Buat file backup di direktori sementara. Pemanggil yang membagikannya.
  static Future<File> createBackup(
    List<ScannedItem> items, {
    String appVersion = '',
    Directory? outputDir,
  }) async {
    final archive = Archive();
    final entries = <Map<String, dynamic>>[];
    var imageCount = 0;

    for (final item in items) {
      entries.add(item.toJson());
      try {
        if (await item.file.exists()) {
          final bytes = await item.file.readAsBytes();
          archive.addFile(
            ArchiveFile('images/${item.fileName}', bytes.length, bytes),
          );
          imageCount++;
        }
      } catch (e) {
        AppLog.d('⚠️ Backup: gambar ${item.fileName} dilewati ($e)');
      }
    }

    final manifest = <String, dynamic>{
      'app': appId,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'itemCount': entries.length,
      'imageCount': imageCount,
      'appVersion': appVersion,
    };

    _addJson(archive, 'manifest.json', manifest);
    _addJson(archive, 'items.json', entries);

    final bytes = ZipEncoder().encodeBytes(archive);
    final dir = outputDir ?? await getTemporaryDirectory();
    final name =
        'qristal_backup_${_stamp.format(DateTime.now())}.$fileExtension';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    AppLog.d('💾 Backup dibuat: $name '
        '(${entries.length} item, ${bytes.length} byte)');
    return file;
  }

  static void _addJson(Archive archive, String name, Object value) {
    final data = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  // ----------------------------------------------------------------- inspect

  /// Baca manifest tanpa mengubah data apa pun.
  static Future<BackupSummary> inspect(File file) async {
    final archive = await _open(file);
    final manifest = _readManifest(archive);
    final items = _readItems(archive);

    return BackupSummary(
      itemCount: items.length,
      imageCount: (manifest['imageCount'] as num?)?.toInt() ?? 0,
      exportedAt: DateTime.tryParse('${manifest['exportedAt'] ?? ''}'),
      formatVersion: (manifest['version'] as num?)?.toInt() ?? 0,
      appVersion: '${manifest['appVersion'] ?? ''}',
    );
  }

  // ----------------------------------------------------------------- restore

  /// Pulihkan item dari file backup (tanpa mengembalikan daftar item).
  ///
  /// Item dengan `id` yang sudah ada dilewati, jadi restore berulang aman.
  static Future<RestoreResult> restore(
    File file, {
    required Set<String> existingIds,
    required Set<String> existingFileNames,
  }) async {
    final result = await restoreItems(
      file,
      existingIds: existingIds,
      existingFileNames: existingFileNames,
    );
    return result.result;
  }

  /// Pulihkan item dan kembalikan daftar item baru untuk digabung ke UI.
  static Future<({RestoreResult result, List<ScannedItem> items})> restoreItems(
    File file, {
    required Set<String> existingIds,
    required Set<String> existingFileNames,
    Directory? storageOverride,
  }) async {
    final archive = await _open(file);
    _readManifest(archive); // validasi app & versi
    final rawItems = _readItems(archive);

    final dir = storageOverride ?? await ImageStorageService.storageDir();
    final ids = {...existingIds};
    final names = {...existingFileNames};
    final restored = <ScannedItem>[];
    var skipped = 0;
    var missing = 0;

    for (final entry in rawItems) {
      if (entry is! Map) {
        skipped++;
        continue;
      }
      final json = Map<String, dynamic>.from(entry);
      final id = '${json['id'] ?? ''}';
      if (id.isEmpty || ids.contains(id)) {
        skipped++;
        continue;
      }

      final fileName = '${json['fileName'] ?? ''}';
      final image =
          fileName.isEmpty ? null : archive.findFile('images/$fileName');
      if (image == null) {
        missing++;
        continue;
      }

      try {
        final bytes = image.readBytes();
        if (bytes == null || bytes.isEmpty) {
          missing++;
          continue;
        }

        // Jangan menimpa file yang sudah ada dengan nama sama.
        var target = File('${dir.path}/$fileName');
        var counter = 2;
        while (names.contains(target.uri.pathSegments.last)) {
          final dot = fileName.lastIndexOf('.');
          final base = dot > 0 ? fileName.substring(0, dot) : fileName;
          final ext = dot > 0 ? fileName.substring(dot) : '';
          target = File('${dir.path}/${base}_$counter$ext');
          counter++;
        }

        await target.writeAsBytes(bytes, flush: true);
        names.add(target.uri.pathSegments.last);

        json['filePath'] = target.path;
        json['fileName'] = target.uri.pathSegments.last;
        final item = ScannedItem.fromJson(json);
        ids.add(id);
        restored.add(item);
      } catch (e) {
        AppLog.d('⚠️ Restore gagal untuk $fileName: $e');
        missing++;
      }
    }

    AppLog.d('♻️ Restore: ${restored.length} dipulihkan, '
        '$skipped dilewati, $missing gambar hilang');

    return (
      result: RestoreResult(
        added: restored.length,
        skipped: skipped,
        missingImages: missing,
      ),
      items: restored,
    );
  }

  // ---------------------------------------------------------------- internal

  static Future<Archive> _open(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw BackupException('File backup tidak bisa dibaca: $e');
    }
  }

  static Map<String, dynamic> _readManifest(Archive archive) {
    final entry = archive.findFile('manifest.json');
    if (entry == null) {
      throw BackupException('File backup tidak lengkap: manifest.json hilang.');
    }
    final bytes = entry.readBytes();
    if (bytes == null) {
      throw BackupException('File backup rusak: manifest.json kosong.');
    }
    Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw BackupException('Manifest backup tidak dikenali.');
      }
      manifest = Map<String, dynamic>.from(decoded);
    } catch (e) {
      throw BackupException('Manifest backup tidak bisa dibaca: $e');
    }

    if (manifest['app'] != appId) {
      throw BackupException('File ini bukan backup Qristal.');
    }
    final version = (manifest['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw BackupException(
        'Backup dibuat oleh versi aplikasi lebih baru (format $version). '
        'Perbarui Qristal terlebih dahulu.',
      );
    }
    return manifest;
  }

  static List<dynamic> _readItems(Archive archive) {
    final entry = archive.findFile('items.json');
    if (entry == null) {
      throw BackupException('File backup tidak lengkap: items.json hilang.');
    }
    final bytes = entry.readBytes();
    if (bytes == null) {
      throw BackupException('File backup rusak: items.json kosong.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) {
        throw BackupException('Daftar item pada backup tidak dikenali.');
      }
      return decoded;
    } catch (e) {
      throw BackupException('Daftar item tidak bisa dibaca: $e');
    }
  }
}
