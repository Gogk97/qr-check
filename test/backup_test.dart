import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/services/backup_service.dart';

Directory _tempDir(String name) {
  final dir = Directory.systemTemp.createTempSync('qristal_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Future<ScannedItem> _item(Directory dir, String id, {bool favorite = false}) async {
  final file = File('${dir.path}/$id.jpg');
  await file.writeAsBytes(List<int>.filled(64, 7));
  return ScannedItem(
    id: id,
    file: file,
    fileName: '$id.jpg',
    fileSize: 64,
    addedAt: DateTime(2026, 11, 18, 10, 30),
    photoDate: DateTime(2024, 3, 14, 16, 20),
    isProcessing: false,
    hasQR: true,
    isQRIS: true,
    isFavorite: favorite,
    rawContent: '00020101021226ID10243455148626304ABCD',
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
      tags: {},
    ),
  );
}

void main() {
  group('BackupService.createBackup', () {
    test('membuat file .qristal berisi item dan gambar', () async {
      final src = _tempDir('src');
      final out = _tempDir('out');
      final items = [
        await _item(src, 'a', favorite: true),
        await _item(src, 'b'),
      ];

      final file = await BackupService.createBackup(items, outputDir: out);

      expect(file.existsSync(), isTrue);
      expect(file.path.endsWith('.${BackupService.fileExtension}'), isTrue);
      expect(await file.length(), greaterThan(0));

      final summary = await BackupService.inspect(file);
      expect(summary.itemCount, 2);
      expect(summary.imageCount, 2);
      expect(summary.formatVersion, BackupService.formatVersion);
      expect(summary.exportedAt, isNotNull);
    });

    test('tetap jalan walau file gambar hilang', () async {
      final src = _tempDir('missing');
      final out = _tempDir('out2');
      final item = await _item(src, 'c');
      await item.file.delete();

      final file = await BackupService.createBackup([item], outputDir: out);
      final summary = await BackupService.inspect(file);

      expect(summary.itemCount, 1);
      expect(summary.imageCount, 0, reason: 'gambar tidak ikut, metadata tetap');
    });
  });

  group('BackupService.restoreItems', () {
    test('memulihkan item + gambar ke direktori baru', () async {
      final src = _tempDir('rsrc');
      final out = _tempDir('rout');
      final dest = _tempDir('rdest');

      final original = [await _item(src, 'x', favorite: true), await _item(src, 'y')];
      final backup = await BackupService.createBackup(original, outputDir: out);

      final restored = await BackupService.restoreItems(
        backup,
        existingIds: const {},
        existingFileNames: const {},
        storageOverride: dest,
      );

      expect(restored.result.added, 2);
      expect(restored.result.skipped, 0);
      expect(restored.result.missingImages, 0);
      expect(restored.items.length, 2);

      final first = restored.items.first;
      expect(first.file.existsSync(), isTrue);
      expect(first.file.path.startsWith(dest.path), isTrue);
      expect(first.qrisDetails?.merchantName, 'Kopi Senja');
      expect(first.photoDate, DateTime(2024, 3, 14, 16, 20));
      expect(restored.items.any((e) => e.isFavorite), isTrue,
          reason: 'status favorit ikut dipulihkan');
    });

    test('restore berulang tidak menduplikasi', () async {
      final src = _tempDir('dsrc');
      final out = _tempDir('dout');
      final dest = _tempDir('ddest');

      final original = [await _item(src, 'z')];
      final backup = await BackupService.createBackup(original, outputDir: out);

      final first = await BackupService.restoreItems(
        backup,
        existingIds: const {},
        existingFileNames: const {},
        storageOverride: dest,
      );
      expect(first.result.added, 1);

      final second = await BackupService.restoreItems(
        backup,
        existingIds: first.items.map((e) => e.id).toSet(),
        existingFileNames: first.items.map((e) => e.fileName).toSet(),
        storageOverride: dest,
      );

      expect(second.result.added, 0);
      expect(second.result.skipped, 1);
    });

    test('nama file bentrok diberi akhiran, bukan ditimpa', () async {
      final src = _tempDir('csrc');
      final out = _tempDir('cout');
      final dest = _tempDir('cdest');

      // File dengan nama sama sudah ada di tujuan.
      await File('${dest.path}/w.jpg').writeAsBytes(List<int>.filled(8, 1));

      final backup = await BackupService.createBackup(
        [await _item(src, 'w')],
        outputDir: out,
      );
      final restored = await BackupService.restoreItems(
        backup,
        existingIds: const {},
        existingFileNames: const {'w.jpg'},
        storageOverride: dest,
      );

      expect(restored.result.added, 1);
      expect(restored.items.single.fileName, 'w_2.jpg');
      expect(File('${dest.path}/w_2.jpg').existsSync(), isTrue);
      // File lama tidak berubah ukurannya.
      expect(await File('${dest.path}/w.jpg').length(), 8);
    });
  });

  group('BackupService — validasi file', () {
    test('file bukan zip ditolak dengan pesan jelas', () async {
      final dir = _tempDir('bad');
      final file = File('${dir.path}/rusak.qristal');
      await file.writeAsString('ini bukan backup');

      expect(
        () => BackupService.inspect(file),
        throwsA(isA<BackupException>()),
      );
    });

    test('arsip dengan app lain ditolak', () async {
      final dir = _tempDir('wrongapp');
      final archive = Archive();
      final manifest = utf8.encode(jsonEncode({'app': 'lain', 'version': 1}));
      final items = utf8.encode(jsonEncode(<dynamic>[]));
      archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      archive.addFile(ArchiveFile('items.json', items.length, items));

      final file = File('${dir.path}/lain.qristal');
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));

      expect(
        () => BackupService.inspect(file),
        throwsA(isA<BackupException>()),
      );
    });

    test('versi format lebih baru ditolak', () async {
      final dir = _tempDir('newver');
      final archive = Archive();
      final manifest = utf8.encode(jsonEncode({
        'app': BackupService.appId,
        'version': BackupService.formatVersion + 1,
      }));
      final items = utf8.encode(jsonEncode(<dynamic>[]));
      archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      archive.addFile(ArchiveFile('items.json', items.length, items));

      final file = File('${dir.path}/baru.qristal');
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));

      expect(
        () => BackupService.inspect(file),
        throwsA(isA<BackupException>()),
      );
    });

    test('arsip tanpa items.json ditolak', () async {
      final dir = _tempDir('noitems');
      final archive = Archive();
      final manifest = utf8.encode(jsonEncode({
        'app': BackupService.appId,
        'version': BackupService.formatVersion,
      }));
      archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));

      final file = File('${dir.path}/kosong.qristal');
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));

      expect(
        () => BackupService.inspect(file),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
