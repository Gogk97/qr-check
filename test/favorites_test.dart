import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/screens/favorites_screen.dart';
import 'package:qr_check/theme/app_theme.dart';

ScannedItem _buildItem({
  required String id,
  bool isFavorite = false,
  bool isQRIS = true,
  String merchant = 'Toko Uji',
}) {
  return ScannedItem(
    id: id,
    file: File('/tmp/qristal_test_$id.jpg'),
    fileName: '$id.jpg',
    fileSize: 1200,
    addedAt: DateTime(2026, 11, 19, 10, 0),
    isProcessing: false,
    hasQR: true,
    isQRIS: isQRIS,
    isFavorite: isFavorite,
    qrisDetails: isQRIS
        ? QRISDetails(
            merchantName: merchant,
            merchantCity: 'Jakarta',
            postalCode: '12345',
            mcc: '5812',
            nmid: 'ID1024345514862',
            acquirer: 'BCA',
            isDynamic: false,
            isValidCRC: true,
            tags: const {},
          )
        : null,
  );
}

void main() {
  group('ScannedItem.isFavorite', () {
    test('default false dan bertahan setelah serialisasi', () {
      final item = _buildItem(id: 'a');
      expect(item.isFavorite, isFalse);

      item.isFavorite = true;
      final restored = ScannedItem.fromJson(item.toJson());
      expect(restored.isFavorite, isTrue);
    });

    test('data lama tanpa field isFavorite tetap aman (backward compatible)', () {
      final legacyJson = <String, dynamic>{
        'id': 'legacy',
        'filePath': '/tmp/legacy.jpg',
        'fileName': 'legacy.jpg',
        'fileSize': 10,
        'addedAt': '2026-01-01T00:00:00.000',
      };
      final item = ScannedItem.fromJson(legacyJson);
      expect(item.isFavorite, isFalse);
    });
  });

  group('FavoritesScreen', () {
    testWidgets('menampilkan empty state saat belum ada favorit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FavoritesScreen(items: const [], onToggleFavorite: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Belum ada favorit'), findsOneWidget);
      expect(find.text('Jelajahi Beranda'), findsOneWidget);
      expect(find.textContaining('Favorit adalah fitur khusus PRO'), findsOneWidget);
    });

    testWidgets('menampilkan kartu favorit dan menyaring QRIS', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final items = [
        _buildItem(id: 'qris1', isFavorite: true, merchant: 'Kopi Senja'),
        _buildItem(id: 'qr1', isFavorite: true, isQRIS: false),
        _buildItem(id: 'bukan_favorit', isFavorite: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FavoritesScreen(items: items, onToggleFavorite: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();

      // Header + jumlah item
      expect(find.text('Koleksi QR pilihan Anda'), findsOneWidget);
      expect(find.text('2 item'), findsOneWidget);
      expect(find.text('1 QRIS · 1 QR code tersimpan'), findsOneWidget);

      // Filter QRIS menyisakan satu kartu
      await tester.tap(find.text('QRIS').first);
      await tester.pumpAndSettle();
      expect(find.text('Kopi Senja'), findsOneWidget);
    });
  });
}
