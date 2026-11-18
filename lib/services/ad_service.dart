import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ads_config.dart';
import '../utils/app_log.dart';

/// Layanan iklan AdMob (rewarded, interstitial).
///
/// Prinsip:
/// - **Tidak pernah memblokir fitur inti.** Semua kegagalan iklan (no fill,
///   offline, SDK tidak tersedia) dikembalikan sebagai `false`, bukan exception.
/// - **Tidak pernah memberi reward tanpa iklan selesai.** Reward hanya
///   dikembalikan dari callback `onUserEarnedReward`.
/// - **Preload** supaya iklan siap saat dibutuhkan (menghindari spinner lama).
class AdService {
  AdService._();

  static bool _initialized = false;
  static Future<void>? _initFuture;

  static RewardedAd? _rewardedAd;
  static InterstitialAd? _interstitialAd;
  static bool _loadingRewarded = false;
  static bool _loadingInterstitial = false;

  static DateTime? _lastInterstitialAt;
  static int _actionsSinceInterstitial = 0;

  static bool get isInitialized => _initialized;

  /// Inisialisasi SDK. Aman dipanggil berkali-kali.
  static Future<void> initialize() {
    if (!AdsConfig.isSupported) return Future<void>.value();
    return _initFuture ??= _doInitialize();
  }

  static Future<void> _doInitialize() async {
    try {
      await MobileAds.instance.initialize();
      MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          maxAdContentRating: MaxAdContentRating.g,
          tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
          tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
        ),
      );
      _initialized = true;
      AppLog.d('📢 AdMob siap (${AdsConfig.testMode ? 'TEST ADS' : 'PRODUKSI'})');
      preloadRewarded();
      preloadInterstitial();
    } catch (e) {
      // Emulator tanpa Google Play Services / perangkat tanpa GMS.
      AppLog.d('⚠️ AdMob init gagal: $e');
      _initialized = false;
    }
  }

  // ---------------------------------------------------------------- REWARDED

  static void preloadRewarded() {
    if (!AdsConfig.isSupported || _loadingRewarded || _rewardedAd != null) return;
    final unitId = AdsConfig.rewardedUnitId;
    if (unitId.isEmpty) return;

    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
          AppLog.d('⚠️ Rewarded gagal dimuat: ${error.code} ${error.message}');
        },
      ),
    );
  }

  /// Menampilkan rewarded ad dan menunggu sampai user menyelesaikan reward.
  ///
  /// Mengembalikan `true` **hanya** bila Google mengonfirmasi reward.
  /// [userId] dipakai untuk Server-Side Verification (SSV) saat diaktifkan.
  static Future<bool> showRewarded({String? userId}) async {
    if (!AdsConfig.isSupported) return false;

    await initialize();
    if (!_initialized) return false;

    var ad = _rewardedAd;
    if (ad == null) {
      preloadRewarded();
      ad = await _waitForRewarded();
    }
    if (ad == null) return false;

    _rewardedAd = null;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shown) {
        shown.dispose();
        preloadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (shown, error) {
        shown.dispose();
        preloadRewarded();
        AppLog.d('⚠️ Rewarded gagal tampil: ${error.code}');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    if (userId != null && userId.isNotEmpty) {
      try {
        // SSV: dipakai saat Server-Side Verification diaktifkan di AdMob.
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: userId,
            customData: 'quota_reward',
          ),
        );
      } catch (e) {
        AppLog.d('⚠️ SSV options gagal diset: $e');
      }
    }

    try {
      ad.show(onUserEarnedReward: (_, reward) {
        if (!completer.isCompleted) completer.complete(true);
      });
    } catch (e) {
      AppLog.d('⚠️ Rewarded exception: $e');
      return false;
    }

    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
  }

  static Future<RewardedAd?> _waitForRewarded() async {
    final deadline = DateTime.now().add(AdsConfig.loadTimeout);
    while (_rewardedAd == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_rewardedAd == null && !_loadingRewarded) preloadRewarded();
    }
    return _rewardedAd;
  }

  // ------------------------------------------------------------ INTERSTITIAL

  static void preloadInterstitial() {
    if (!AdsConfig.isSupported ||
        _loadingInterstitial ||
        _interstitialAd != null) {
      return;
    }
    final unitId = AdsConfig.interstitialUnitId;
    if (unitId.isEmpty) return;

    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          AppLog.d('⚠️ Interstitial gagal dimuat: ${error.code} ${error.message}');
        },
      ),
    );
  }

  /// Catat satu aksi bernilai (mis. penghapusan foto berhasil).
  static void noteUserAction() {
    _actionsSinceInterstitial++;
    if (_interstitialAd == null) preloadInterstitial();
  }

  /// Tampilkan interstitial bila semua syarat terpenuhi.
  /// [isPro] = true tidak pernah ditampilkan iklan.
  static Future<bool> maybeShowInterstitial({bool isPro = false}) async {
    if (isPro || !AdsConfig.isSupported) return false;
    await initialize();
    if (!_initialized) return false;

    if (_actionsSinceInterstitial < AdsConfig.interstitialAfterActions) {
      return false;
    }

    final now = DateTime.now();
    if (_lastInterstitialAt != null &&
        now.difference(_lastInterstitialAt!) <
            AdsConfig.interstitialMinInterval) {
      return false;
    }

    var ad = _interstitialAd;
    if (ad == null) {
      preloadInterstitial();
      return false; // jangan tahan aksi user hanya demi iklan
    }

    _interstitialAd = null;
    _lastInterstitialAt = now;
    _actionsSinceInterstitial = 0;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shown) {
        shown.dispose();
        preloadInterstitial();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (shown, error) {
        shown.dispose();
        preloadInterstitial();
        AppLog.d('⚠️ Interstitial gagal tampil: ${error.code}');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      ad.show();
    } catch (e) {
      AppLog.d('⚠️ Interstitial exception: $e');
      return false;
    }

    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => true,
    );
  }

  /// Bersihkan cache (dipakai saat logout supaya iklan tidak bocor antar akun).
  static void disposeAds() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _actionsSinceInterstitial = 0;
    _lastInterstitialAt = null;
  }
}
