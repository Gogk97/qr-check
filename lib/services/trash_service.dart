import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/scanned_item.dart';
import '../utils/app_log.dart';
import 'image_storage_service.dart';

/// Satu item di tempat sampah.
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.item,
    required this.trashFileName,
    required this.deletedAt,
    required this.galleryDeleted,
  });

  final String id;
  final ScannedItem item;

  /// Nama file gambar di folder tempat sampah.
  final String trashFileName;
  final DateTime deletedAt;

  /// True bila foto asli di galeri sistem ikut terhapus (tidak bisa dipulihkan
  /// ke galeri, hanya salinan Qristal-nya).
  final bool galleryDeleted;

  Duration get age => DateTime.now().difference(deletedAt);

  bool get isExpired => age > TrashService.retention;

  String get merchantName {
    final name = item.qrisDetails?.merchantName ?? '';
    return name.isEmpty ? 'QRIS Tanpa Nama' : name;
  }

  double get amount => item.qrisDetails?.amount ?? 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'trashFileName': trashFileName,
        'deletedAt': deletedAt.toIso8601String(),
        'galleryDeleted': galleryDeleted,
        'item': item.toJson(),
      };

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
        id: '${json['id'] ?? ''}',
        trashFileName: '${json['trashFileName'] ?? ''}',
        deletedAt:
            DateTime.tryParse('${json['deletedAt'] ?? ''}') ?? DateTime.now(),
        galleryDeleted: json['galleryDeleted'] ?? false,
        item: ScannedItem.fromJson(
          Map<String, dynamic>.from(json['item'] ?? const {}),
        ),
      );
}

/// Tempat sampah sementara: file dipindah, bukan langsung dihapus.
///
/// Memberi jendela 24 jam untuk membatalkan penghapusan. Setelah itu file
/// dibersihkan otomatis saat aplikasi dibuka.
class TrashService {
  TrashService._();

  static const Duration retention = Duration(hours: 24);
  static const String _indexName = 'trash_index.json';

  static Directory? _cachedDir;

  /// Folder tempat sampah (di app support, tidak terlihat user).
  static Future<Directory> dir() async {
    if (_cachedDir != null && await _cachedDir!.exists()) return _cachedDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/qristal_trash');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// Untuk test: arahkan ke folder sementara.
  static void overrideDirForTest(Directory? dir) => _cachedDir = dir;

  static Future<File> _indexFile() async {
    final d = await dir();
    return File('${d.path}/$_indexName');
  }

  // ------------------------------------------------------------------- read

  static Future<List<TrashEntry>> list() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return <TrashEntry>[];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <TrashEntry>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TrashEntry>[];
      final entries = decoded
          .whereType<Map>()
          .map((e) => TrashEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
      return entries;
    } catch (e) {
      AppLog.d('⚠️ Gagal membaca tempat sampah: $e');
      return <TrashEntry>[];
    }
  }

  static Future<int> count() async => (await list()).length;

  // ------------------------------------------------------------------ write

  static Future<void> _writeIndex(List<TrashEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// Pindahkan gambar item ke tempat sampah. Item TIDAK lagi dihapus langsung.
  static Future<TrashEntry?> move(
    ScannedItem item, {
    bool galleryDeleted = false,
  }) async {
    try {
      final d = await dir();
      final source = item.file;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final ext = _extension(item.fileName);
      final trashName = '${stamp}_$ext';

      final target = File('${d.path}/$trashName');
      if (await source.exists()) {
        await source.copy(target.path);
        await source.delete();
      }

      final entry = TrashEntry(
        id: 'trash_$stamp',
        item: item,
        trashFileName: trashName,
        deletedAt: DateTime.now(),
        galleryDeleted: galleryDeleted,
      );

      final entries = List<TrashEntry>.from(await list());
      entries.insert(0, entry);
      await _writeIndex(entries);
      AppLog.d('🗑️ Ke tempat sampah: ${item.fileName}');
      return entry;
    } catch (e) {
      AppLog.d('⚠️ Gagal memindahkan ke tempat sampah: $e');
      return null;
    }
  }

  /// Pindahkan beberapa item sekaligus.
  static Future<List<TrashEntry>> moveAll(
    List<ScannedItem> items, {
    bool galleryDeleted = false,
  }) async {
    final moved = <TrashEntry>[];
    for (final item in items) {
      final entry = await move(item, galleryDeleted: galleryDeleted);
      if (entry != null) moved.add(entry);
    }
    return moved;
  }

  /// Pulihkan item dari tempat sampah ke folder gambar aplikasi.
  ///
  /// Mengembalikan item yang berhasil dipulihkan (dengan path file baru).
  static Future<List<ScannedItem>> restore(
    List<TrashEntry> entries, {
    Directory? storageOverride,
  }) async {
    if (entries.isEmpty) return const [];

    final storage = storageOverride ?? await ImageStorageService.storageDir();
    final trashDir = await dir();
    final all = await list();
    final restored = <ScannedItem>[];
    final restoredIds = <String>{};

    for (final entry in entries) {
      final source = File('${trashDir.path}/${entry.trashFileName}');
      if (!await source.exists()) continue;

      try {
        var target = File('${storage.path}/${entry.item.fileName}');
        var counter = 2;
        while (await target.exists()) {
          final dot = entry.item.fileName.lastIndexOf('.');
          final base = dot > 0
              ? entry.item.fileName.substring(0, dot)
              : entry.item.fileName;
          final ext = dot > 0 ? entry.item.fileName.substring(dot) : '';
          target = File('${storage.path}/${base}_$counter$ext');
          counter++;
        }

        await source.copy(target.path);
        await source.delete();

        final item = entry.item;
        item.file = target;
        item.fileName = target.uri.pathSegments.last;
        restored.add(item);
        restoredIds.add(entry.id);
      } catch (e) {
        AppLog.d('⚠️ Gagal memulihkan ${entry.item.fileName}: $e');
      }
    }

    final remaining =
        all.where((e) => !restoredIds.contains(e.id)).toList();
    await _writeIndex(remaining);
    if (restored.isNotEmpty) {
      AppLog.d('♻️ Dipulihkan dari tempat sampah: ${restored.length} item');
    }
    return restored;
  }

  /// Hapus permanen satu entry (file + metadata).
  static Future<void> deletePermanently(TrashEntry entry) async {
    final trashDir = await dir();
    try {
      final file = File('${trashDir.path}/${entry.trashFileName}');
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLog.d('⚠️ Gagal menghapus file sampah: $e');
    }
    final all = await list();
    await _writeIndex(all.where((e) => e.id != entry.id).toList());
  }

  /// Kosongkan seluruh tempat sampah.
  static Future<void> empty() async {
    final all = await list();
    final trashDir = await dir();
    for (final entry in all) {
      try {
        final file = File('${trashDir.path}/${entry.trashFileName}');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _writeIndex(const []);
    AppLog.d('🗑️ Tempat sampah dikosongkan (${all.length} item)');
  }

  /// Bersihkan item yang sudah melewati masa retensi (24 jam).
  static Future<int> purgeExpired() async {
    final all = await list();
    final expired = all.where((e) => e.isExpired).toList();
    if (expired.isEmpty) return 0;

    final trashDir = await dir();
    for (final entry in expired) {
      try {
        final file = File('${trashDir.path}/${entry.trashFileName}');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _writeIndex(all.where((e) => !e.isExpired).toList());
    AppLog.d('🧹 Tempat sampah: ${expired.length} item kedaluwarsa dibersihkan');
    return expired.length;
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return 'jpg';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
