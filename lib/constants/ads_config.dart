import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Konfigurasi AdMob Qristal.
///
/// Mode default adalah **TEST ADS** supaya aman saat development/QA:
/// unit iklan test resmi Google tidak menghasilkan pendapatan dan tidak
/// berisiko "invalid traffic" (akun AdMob bisa di-suspend kalau klik iklan
/// sendiri pada unit produksi).
///
/// Untuk rilis produksi, build dengan:
///
/// ```bash
/// flutter build appbundle --release \
///   --dart-define=ADMOB_TEST_MODE=false \
///   --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXX/YYYY \
///   --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXX/ZZZZ \
///   --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/WWWW \
///   -PadmobAppId=ca-app-pub-XXXX~VVVV
/// ```
///
/// `-PadmobAppId` dibaca oleh `android/app/build.gradle` dan disuntik ke
/// AndroidManifest sebagai `com.google.android.gms.ads.APPLICATION_ID`.
class AdsConfig {
  AdsConfig._();

  /// `true` = unit iklan test Google. Set `false` hanya untuk build produksi.
  static const bool testMode =
      bool.fromEnvironment('ADMOB_TEST_MODE', defaultValue: true);

  static const String _rewardedOverride =
      String.fromEnvironment('ADMOB_REWARDED_ID');
  static const String _interstitialOverride =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const String _bannerOverride =
      String.fromEnvironment('ADMOB_BANNER_ID');

  // Unit iklan test resmi Google (Android).
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';

  static String get rewardedUnitId => testMode ? _testRewarded : _rewardedOverride;
  static String get interstitialUnitId =>
      testMode ? _testInterstitial : _interstitialOverride;
  static String get bannerUnitId => testMode ? _testBanner : _bannerOverride;

  /// Iklan hanya didukung di Android/iOS. Desktop & unit test tidak memuat SDK.
  static bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True bila build produksi sudah membawa ketiga unit id asli.
  static bool get hasProductionIds =>
      !testMode &&
      _rewardedOverride.isNotEmpty &&
      _interstitialOverride.isNotEmpty &&
      _bannerOverride.isNotEmpty;

  // --- Kebijakan frekuensi (UX + kebijakan Play: jangan agresif) -----------
  /// Jeda minimum antar interstitial.
  static const Duration interstitialMinInterval = Duration(seconds: 120);

  /// Interstitial baru muncul setelah sekian aksi hapus berhasil.
  static const int interstitialAfterActions = 3;

  /// Batas waktu memuat iklan sebelum menyerah (ms).
  static const Duration loadTimeout = Duration(seconds: 12);
}
