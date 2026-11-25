import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/services/trash_service.dart';

Directory _tempDir(String name) {
  final dir = Directory.systemTemp.createTempSync('qristal_trash_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Future<ScannedItem> _item(Directory dir, String id) async {
  final file = File('${dir.path}/$id.jpg');
  await file.writeAsBytes(List<int>.filled(32, 9));
  return ScannedItem(
    id: id,
    file: file,
    fileName: '$id.jpg',
    fileSize: 32,
    addedAt: DateTime(2026, 11, 18, 10),
    isProcessing: false,
    hasQR: true,
    isQRIS: true,
    qrisDetails: QRISDetails(
      merchantName: 'Kopi Senja',
      merchantCity: 'Jakarta',
      postalCode: '12140',
      mcc: '5812',
      amount: 25000,
      nmid: 'ID1024345514862',
      acquirer: 'BCA',
      isDynamic: true,
      isValidCRC: true,
      tags: const {},
    ),
  );
}

void main() {
  late Directory trashDir;
  late Directory storageDir;

  setUp(() {
    trashDir = _tempDir('bin');
    storageDir = _tempDir('store');
    TrashService.overrideDirForTest(trashDir);
  });

  tearDown(() => TrashService.overrideDirForTest(null));

  group('TrashService.move', () {
    test('memindahkan file ke tempat sampah, bukan menghapus', () async {
      final item = await _item(storageDir, 'a');
      final originalPath = item.file.path;

      final entry = await TrashService.move(item);

      expect(entry, isNotNull);
      expect(File(originalPath).existsSync(), isFalse, reason: 'file asli pindah');
      expect(File('${trashDir.path}/${entry!.trashFileName}').existsSync(), isTrue);

      final list = await TrashService.list();
      expect(list.length, 1);
      expect(list.first.item.id, 'a');
      expect(list.first.merchantName, 'Kopi Senja');
      expect(await TrashService.count(), 1);
    });

    test('menandai bila foto galeri ikut terhapus', () async {
      final item = await _item(storageDir, 'b');
      final entry = await TrashService.move(item, galleryDeleted: true);
      expect(entry!.galleryDeleted, isTrue);
    });

    test('moveAll memindahkan semua item', () async {
      final items = [
        await _item(storageDir, 'c'),
        await _item(storageDir, 'd'),
      ];
      final entries = await TrashService.moveAll(items);
      expect(entries.length, 2);
      expect(await TrashService.count(), 2);
    });
  });

  group('TrashService.restore', () {
    test('mengembalikan file dan memperbarui path item', () async {
      final item = await _item(storageDir, 'e');
      final entry = await TrashService.move(item);

      final restored =
          await TrashService.restore([entry!], storageOverride: storageDir);

      expect(restored.length, 1);
      final back = restored.single;
      expect(back.id, 'e');
      expect(back.file.existsSync(), isTrue);
      expect(back.file.path.startsWith(storageDir.path), isTrue);
      expect(await TrashService.count(), 0, reason: 'entri dihapus dari indeks');
    });

    test('nama file bentrok diberi akhiran', () async {
      final item = await _item(storageDir, 'f');
      final entry = await TrashService.move(item);

      // File dengan nama sama sudah ada lagi di storage.
      await File('${storageDir.path}/f.jpg').writeAsBytes(List<int>.filled(4, 1));

      final restored =
          await TrashService.restore([entry!], storageOverride: storageDir);
      expect(restored.single.fileName, 'f_2.jpg');
    });

    test('entry tanpa file dilewati dengan aman', () async {
      final item = await _item(storageDir, 'g');
      final entry = await TrashService.move(item);
      await File('${trashDir.path}/${entry!.trashFileName}').delete();

      final restored =
          await TrashService.restore([entry], storageOverride: storageDir);
      expect(restored, isEmpty);
    });
  });

  group('TrashService.purgeExpired', () {
    test('hanya membuang entri lebih dari 24 jam', () async {
      final fresh = await _item(storageDir, 'fresh');
      final old = await _item(storageDir, 'old');
      await TrashService.move(fresh);
      await TrashService.move(old);

      // Mundurkan deletedAt entri "old" menjadi 2 hari lalu.
      final indexFile = File('${trashDir.path}/trash_index.json');
      final raw = jsonDecode(await indexFile.readAsString()) as List;
      for (final entry in raw) {
        final map = entry as Map<String, dynamic>;
        final item = map['item'] as Map<String, dynamic>;
        if (item['id'] == 'old') {
          map['deletedAt'] = DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String();
        }
      }
      await indexFile.writeAsString(jsonEncode(raw));

      final removed = await TrashService.purgeExpired();

      expect(removed, 1);
      final remaining = await TrashService.list();
      expect(remaining.length, 1);
      expect(remaining.single.item.id, 'fresh');
    });
  });

  group('TrashService.deletePermanently & empty', () {
    test('hapus permanen satu item', () async {
      final item = await _item(storageDir, 'h');
      final entry = await TrashService.move(item);

      await TrashService.deletePermanently(entry!);

      expect(await TrashService.count(), 0);
      expect(File('${trashDir.path}/${entry.trashFileName}').existsSync(), isFalse);
    });

    test('kosongkan seluruh tempat sampah', () async {
      await TrashService.moveAll([
        await _item(storageDir, 'i'),
        await _item(storageDir, 'j'),
      ]);
      await TrashService.empty();

      expect(await TrashService.count(), 0);
      final leftovers = trashDir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('trash_index.json'))
          .toList();
      expect(leftovers, isEmpty, reason: 'tidak ada gambar tertinggal');
    });
  });
}
