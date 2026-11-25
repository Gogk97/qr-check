import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/models/scanned_item.dart';
import 'package:qr_check/screens/onboarding_screen.dart';
import 'package:qr_check/services/duplicate_service.dart';
import 'package:qr_check/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScannedItem _item({
  required String id,
  String? raw,
  double? amount = 25000,
  String merchant = 'Kopi Senja',
  bool isQRIS = true,
  bool hasQR = true,
  DateTime? addedAt,
}) {
  return ScannedItem(
    id: id,
    file: File('/tmp/dup_$id.jpg'),
    fileName: '$id.jpg',
    fileSize: 1000,
    addedAt: addedAt ?? DateTime(2026, 11, 18, 10, 0),
    isProcessing: false,
    hasQR: hasQR,
    isQRIS: isQRIS,
    rawContent: raw,
    qrisDetails: isQRIS
        ? QRISDetails(
            merchantName: merchant,
            merchantCity: 'Jakarta',
            postalCode: '12140',
            mcc: '5812',
            amount: amount,
            nmid: 'ID1024345514862',
            acquirer: 'BCA',
            isDynamic: amount != null,
            isValidCRC: true,
            tags: const {},
          )
        : null,
  );
}

void main() {
  group('DuplicateService.groups', () {
    test('mengelompokkan QRIS dengan payload identik', () {
      final items = [
        _item(id: 'a1', raw: 'QR-SAMA'),
        _item(id: 'a2', raw: 'QR-SAMA'),
        _item(id: 'b1', raw: 'QR-BEDA', amount: 10000),
      ];
      final groups = DuplicateService.groups(items);

      expect(groups.length, 1);
      expect(groups.first.count, 2);
      expect(groups.first.merchantName, 'Kopi Senja');
    });

    test('tidak menandai QRIS unik sebagai duplikat', () {
      final items = [
        _item(id: 'a', raw: 'QR-A'),
        _item(id: 'b', raw: 'QR-B'),
      ];
      expect(DuplicateService.groups(items), isEmpty);
    });

    test('yang dipertahankan adalah foto paling baru', () {
      final items = [
        _item(id: 'lama', raw: 'QR-X', addedAt: DateTime(2026, 1, 1)),
        _item(id: 'baru', raw: 'QR-X', addedAt: DateTime(2026, 6, 1)),
      ];
      final group = DuplicateService.groups(items).single;
      expect(group.keep.id, 'baru');
      expect(group.extras.single.id, 'lama');
    });

    test('tiga foto QRIS sama menghasilkan dua foto berlebih', () {
      final items = [
        _item(id: 'a', raw: 'QR-3'),
        _item(id: 'b', raw: 'QR-3'),
        _item(id: 'c', raw: 'QR-3'),
      ];
      final groups = DuplicateService.groups(items);
      expect(DuplicateService.totalExtras(groups), 2);
      expect(DuplicateService.extraPhotos(groups).length, 2);
    });

    test('diurutkan dari grup terbesar', () {
      final items = [
        _item(id: 'a1', raw: 'QR-A'),
        _item(id: 'a2', raw: 'QR-A'),
        _item(id: 'b1', raw: 'QR-B'),
        _item(id: 'b2', raw: 'QR-B'),
        _item(id: 'b3', raw: 'QR-B'),
      ];
      final groups = DuplicateService.groups(items);
      expect(groups.first.count, 3);
      expect(groups.last.count, 2);
    });

    test('foto tanpa payload dan bukan QRIS diabaikan', () {
      final items = [
        _item(id: 'foto1', raw: null, isQRIS: false),
        _item(id: 'foto2', raw: null, isQRIS: false),
      ];
      expect(DuplicateService.groups(items), isEmpty);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('menampilkan slide pertama dan bisa lanjut', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pindai galeri sekali jalan'), findsOneWidget);
      expect(find.text('Lanjut'), findsOneWidget);

      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Dari WhatsApp langsung ke sini'), findsOneWidget);

      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Laporan rapi untuk PRO'), findsOneWidget);
      expect(find.text('Mulai Sekarang'), findsOneWidget);
    });

    testWidgets('Lewati menyimpan penanda selesai', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const OnboardingScreen()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lewati'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.prefsKey), isTrue);
    });

    testWidgets('showIfNeeded tidak muncul bila sudah pernah dilihat',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {OnboardingScreen.prefsKey: true});

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => OnboardingScreen.showIfNeeded(context),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();

      expect(find.text('Pindai galeri sekali jalan'), findsNothing);
    });
  });
}
