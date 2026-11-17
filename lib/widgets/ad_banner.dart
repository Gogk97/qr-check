import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ads_config.dart';
import '../services/monetization_service.dart';
import '../utils/app_log.dart';

/// Banner AdMob adaptif (anchored adaptive).
///
/// - Tidak tampil untuk pengguna PRO (PRO = bebas iklan).
/// - Tidak memakan ruang bila iklan gagal dimuat / platform tidak didukung.
/// - Tidak pernah menutupi konten: tinggi mengikuti ukuran iklan sebenarnya.
class AdBanner extends StatefulWidget {
  /// Matikan paksa (mis. di layar pengaturan atau saat memproses batch).
  final bool enabled;
  final EdgeInsetsGeometry margin;

  const AdBanner({
    super.key,
    this.enabled = true,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isPro = true; // default aman: jangan minta iklan sebelum diketahui
  bool _loading = false;
  bool _checkedPro = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedPro) {
      _checkedPro = true;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    if (!AdsConfig.isSupported || !widget.enabled) return;

    final isPro = await MonetizationService.isProUser();
    if (!mounted) return;
    setState(() => _isPro = isPro);
    if (isPro) return;

    await _loadBanner();
  }

  Future<void> _loadBanner() async {
    if (_bannerAd != null || _loading) return;
    final unitId = AdsConfig.bannerUnitId;
    if (unitId.isEmpty) return;

    _loading = true;
    final width = MediaQuery.sizeOf(context).width.truncate();

    AdSize size = AdSize.banner;
    try {
      final adaptive =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (adaptive != null) size = adaptive;
    } catch (e) {
      AppLog.d('⚠️ Ukuran banner adaptif gagal, pakai 320x50: $e');
    }
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: unitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) {
          if (!mounted) {
            loaded.dispose();
            return;
          }
          setState(() {
            _bannerAd = loaded as BannerAd;
            _loading = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _loading = false;
          AppLog.d('⚠️ Banner gagal dimuat: ${error.code} ${error.message}');
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!widget.enabled || _isPro || ad == null) return const SizedBox.shrink();

    return Padding(
      padding: widget.margin,
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
