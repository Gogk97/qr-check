import '../models/scanned_item.dart';
import 'export_service.dart';

/// Sekelompok foto yang menampilkan QRIS yang sama.
class DuplicateGroup {
  const DuplicateGroup(this.items);

  /// Semua foto dengan payload identik, urut terbaru → terlama.
  final List<ScannedItem> items;

  ScannedItem get keep => items.first;
  List<ScannedItem> get extras => items.skip(1).toList();
  int get count => items.length;

  String get merchantName {
    final name = keep.qrisDetails?.merchantName ?? '';
    return name.isEmpty ? 'QRIS Tanpa Nama' : name;
  }

  double get amount => keep.qrisDetails?.amount ?? 0;
  String get acquirer => keep.qrisDetails?.displayAcquirer ?? '-';
}

/// Deteksi QRIS yang difoto lebih dari sekali (isi payload identik).
class DuplicateService {
  DuplicateService._();

  /// Grup duplikat, diurutkan dari yang paling banyak fotonya.
  static List<DuplicateGroup> groups(List<ScannedItem> items) {
    final map = <String, List<ScannedItem>>{};
    final order = <String>[];

    final sorted = items.toList()
      ..sort((a, b) => b.reportDate.compareTo(a.reportDate));

    for (final item in sorted) {
      // Hanya QR/QRIS yang punya isi payload — foto biasa tidak diduplikasi.
      if ((item.rawContent ?? '').trim().isEmpty && !item.isQRIS) continue;
      final key = ExportService.fingerprint(item);
      final bucket = map[key];
      if (bucket == null) {
        map[key] = [item];
        order.add(key);
      } else {
        bucket.add(item);
      }
    }

    final result = order
        .map((k) => DuplicateGroup(map[k]!))
        .where((g) => g.count > 1)
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.keep.reportDate.compareTo(a.keep.reportDate);
      });
    return result;
  }

  /// Semua foto yang akan dihapus bila pengguna memilih "simpan terbaru".
  static List<ScannedItem> extraPhotos(List<DuplicateGroup> groups) =>
      groups.expand((g) => g.extras).toList();

  static int totalExtras(List<DuplicateGroup> groups) =>
      groups.fold<int>(0, (sum, g) => sum + g.extras.length);
}
