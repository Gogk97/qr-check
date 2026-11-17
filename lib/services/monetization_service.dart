import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/qris_payment_screen.dart';
import '../theme/app_theme.dart';
import 'play_billing_service.dart';
import 'supabase_service.dart';

class MonetizationService {
  static const String _proKey = 'user_is_pro_status_v1';

  static Future<bool> isProUser({String? userId}) async {
    // 1. Cek real-time ke Supabase jika online
    try {
      final supaUid = userId ?? SupabaseService.client.auth.currentUser?.id;
      if (supaUid != null && SupabaseService.isAuthenticated) {
        final row = await SupabaseService.client
            .from('profiles')
            .select('is_pro')
            .eq('id', supaUid)
            .maybeSingle();

        if (row != null && row['is_pro'] == true) {
          await setProUser(true, userId: supaUid);
          return true;
        }
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      final userSpecific = prefs.getBool('user_is_pro_status_v1_$userId');
      if (userSpecific != null) return userSpecific;
    }
    final currentUserJson = prefs.getString('current_user_v1');
    if (currentUserJson != null && currentUserJson.isNotEmpty) {
      try {
        final Map<String, dynamic> userMap = jsonDecode(currentUserJson);
        final currentId = userMap['id'] as String?;
        if (currentId != null && currentId.isNotEmpty) {
          final userSpecific = prefs.getBool('user_is_pro_status_v1_$currentId');
          if (userSpecific != null) return userSpecific;
          if (userMap['isGuest'] == true) {
            return false;
          }
        }
      } catch (_) {}
    }
    return prefs.getBool(_proKey) ?? false;
  }

  static Future<void> setProUser(bool status, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proKey, status);
    if (userId != null && userId.isNotEmpty) {
      await prefs.setBool('user_is_pro_status_v1_$userId', status);
    } else {
      final currentUserJson = prefs.getString('current_user_v1');
      if (currentUserJson != null && currentUserJson.isNotEmpty) {
        try {
          final Map<String, dynamic> userMap = jsonDecode(currentUserJson);
          final currentId = userMap['id'] as String?;
          if (currentId != null && currentId.isNotEmpty) {
            await prefs.setBool('user_is_pro_status_v1_$currentId', status);
          }
        } catch (_) {}
      }
    }
  }

  /// Tampilkan Dialog Iklan Interstitial Singkat (Dev / Production Ready)
  static Future<void> showInterstitialAd(BuildContext context) async {
    final isPro = await isProUser();
    if (isPro) return; // PRO user bebas iklan!

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _SimulatedAdDialog(
          title: 'Iklan Sponsor Singkat',
          description: 'Foto sedang dihapus... Menutup iklan dalam beberapa detik.',
          durationSeconds: 2,
        );
      },
    );
  }

  /// Tampilkan Dialog Pilihan Hapus Massal (> 3 Item)
  /// Mengembalikan true jika penghapusan diizinkan (lewat Iklan Video atau PRO)
  static Future<bool> showMassDeleteDialog(
    BuildContext context, {
    required int itemCount,
  }) async {
    final isPro = await isProUser();
    if (isPro) return true; // PRO User langsung bisa hapus tanpa batasan!

    if (!context.mounted) return false;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: AppTheme.cardColor(isDark),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.qrAmber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.workspace_premium, color: AppTheme.qrAmber, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hapus Massal Foto',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Anda memilih $itemCount foto sekaligus untuk dihapus.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppTheme.inkColor(isDark)),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih opsi di bawah ini untuk melanjutkan:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.mutedColor(isDark),
                ),
              ),
              const SizedBox(height: 14),
              // Option A: Watch Video Ad
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: AppTheme.primary, size: 20),
                  ),
                  title: Text(
                    'Nonton Iklan Video (Gratis)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.inkColor(isDark)),
                  ),
                  subtitle: Text(
                    'Gratis 1x Hapus Massal setelah nonton iklan 3 detik',
                    style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                  ),
                  onTap: () => Navigator.of(context).pop('watch_ad'),
                ),
              ),
              const SizedBox(height: 8),
              // Option B: Upgrade PRO
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.qrAmber.withOpacity(0.45)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.qrAmber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.star_rounded, color: AppTheme.qrAmber, size: 20),
                  ),
                  title: const Text(
                    'Upgrade ke PRO (Lifetime)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.qrAmber),
                  ),
                  subtitle: Text(
                    'Hapus tanpa batas & bebas semua iklan selamanya!',
                    style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                  ),
                  onTap: () => Navigator.of(context).pop('buy_pro'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: Text('Batal', style: TextStyle(color: AppTheme.mutedColor(isDark), fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (result == 'watch_ad') {
      if (!context.mounted) return false;
      // Simulasikan Rewarded Video Ad
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return const _SimulatedAdDialog(
            title: 'Iklan Video Rewarded',
            description: 'Sedang memutar video sponsor... Mengkonfirmasi Hapus Massal.',
            durationSeconds: 3,
          );
        },
      );
      return true;
    } else if (result == 'buy_pro') {
      if (!context.mounted) return false;
      // Simulasikan/Proses Pembelian PRO
      final bought = await showProUpgradeModal(context);
      return bought;
    }

    return false;
  }

  /// Titik masuk tunggal pembelian PRO.
  /// Android (Play Store) -> Google Play Billing (wajib menurut kebijakan Play).
  /// Platform lain (iOS/Web/Desktop) -> QRIS manual seperti sebelumnya.
  static Future<bool> openProPurchase(BuildContext context) async {
    if (PlayBillingService.isSupportedPlatform) {
      return showProUpgradeModal(context);
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
    );
    return false;
  }

  /// Modal Pembelian PRO: Google Play Billing (Android) atau QRIS (platform lain).
  static Future<bool> showProUpgradeModal(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ProUpgradeSheet(),
    );
    return result ?? false;
  }

  /// Eksekusi pembelian PRO lewat Google Play (Android only).
  /// Hak PRO baru diberikan setelah server memverifikasi purchase token.
  static Future<ProUpgradeOutcome> purchaseProViaPlay({String? userId}) async {
    final result = await PlayBillingService.purchase(obfuscatedAccountId: userId);

    switch (result.status) {
      case PlayPurchaseStatus.purchased:
        final purchase = result.purchase;
        if (purchase == null) {
          return const ProUpgradeOutcome(false, 'Data pembelian dari Play Store tidak lengkap.');
        }
        final verified = await PlayBillingService.verifyOnServer(purchase);
        if (!verified) {
          return const ProUpgradeOutcome(
            false,
            'Pembayaran diterima Google Play, tetapi verifikasi server belum berhasil. '
            'Coba tombol "Pulihkan Pembelian" beberapa saat lagi.',
          );
        }
        await setProUser(true, userId: userId);
        return const ProUpgradeOutcome(true, 'PRO aktif selamanya. Selamat menikmati!');

      case PlayPurchaseStatus.alreadyOwned:
        final restored = await restoreProPurchase(userId: userId);
        return restored
            ? const ProUpgradeOutcome(true, 'Pembelian PRO Anda berhasil dipulihkan.')
            : const ProUpgradeOutcome(
                false,
                'Produk ini sudah dimiliki akun Google Play lain di perangkat ini.',
              );

      case PlayPurchaseStatus.pending:
        return ProUpgradeOutcome(
          false,
          result.message ??
              'Pembayaran sedang diproses Google Play. PRO aktif otomatis setelah pembayaran selesai.',
        );

      case PlayPurchaseStatus.canceled:
        return const ProUpgradeOutcome(false, 'Pembelian dibatalkan.');

      case PlayPurchaseStatus.unavailable:
      case PlayPurchaseStatus.failed:
        return ProUpgradeOutcome(false, result.message ?? 'Pembelian gagal diproses.');
    }
  }

  /// Pulihkan pembelian PRO (reinstall, ganti perangkat, atau akun Play berbeda).
  static Future<bool> restoreProPurchase({String? userId}) async {
    final granted = await PlayBillingService.syncOwnedPurchases();
    if (granted) {
      await setProUser(true, userId: userId);
    }
    return granted;
  }

  static Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.qrisGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hasil proses pembelian PRO (untuk feedback UI).
class ProUpgradeOutcome {
  final bool success;
  final String message;

  const ProUpgradeOutcome(this.success, this.message);
}

/// Bottom sheet upgrade PRO.
///
/// Android + Play Store tersedia -> Google Play Billing (one-time product).
/// Platform lain (iOS/Web/Desktop) -> QRIS manual seperti sebelumnya.
class ProUpgradeSheet extends StatefulWidget {
  const ProUpgradeSheet({super.key});

  @override
  State<ProUpgradeSheet> createState() => _ProUpgradeSheetState();
}

class _ProUpgradeSheetState extends State<ProUpgradeSheet> {
  bool _loadingPrice = true;
  bool _busy = false;
  bool _playReady = false;
  bool _usePlay = PlayBillingService.isSupportedPlatform;
  PlayProduct? _product;
  String? _notice;
  bool _noticeIsError = false;

  bool get _isAndroid => _usePlay;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!_usePlay) {
      if (mounted) setState(() => _loadingPrice = false);
      return;
    }

    // 0) Pastikan Play Store benar-benar tersedia (Huawei/emulator tanpa GMS).
    final available = await PlayBillingService.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _usePlay = false;
        _loadingPrice = false;
        _playReady = false;
      });
      return;
    }

    // 1) Coba pulihkan pembelian yang sudah dimiliki akun Play (reinstall / device baru).
    final restored = await MonetizationService.restoreProPurchase();
    if (!mounted) return;
    if (restored) {
      Navigator.of(context).pop(true);
      return;
    }

    // 2) Selesaikan transaksi yang tertunda verifikasinya (offline / server sempat down).
    await PlayBillingService.retryPendingVerifications();

    // 3) Ambil harga asli dari Play Store (sudah terformat sesuai mata uang user).
    final product = await PlayBillingService.loadProduct();
    if (!mounted) return;
    setState(() {
      _product = product;
      _playReady = product != null;
      _loadingPrice = false;
      if (product == null) {
        _notice =
            'Katalog Play Store belum dapat dimuat. Pastikan aplikasi terpasang dari Play Store '
            'dan akun Google sudah terdaftar sebagai license tester.';
        _noticeIsError = true;
      }
    });
  }

  Future<void> _retryLoadPrice() async {
    setState(() {
      _loadingPrice = true;
      _notice = null;
    });
    await _bootstrap();
  }

  Future<void> _buyViaPlay() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final userId = SupabaseService.isInitialized
        ? SupabaseService.client.auth.currentUser?.id
        : null;
    final outcome = await MonetizationService.purchaseProViaPlay(userId: userId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = outcome.message;
      _noticeIsError = !outcome.success;
    });
    if (outcome.success) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final ok = await MonetizationService.restoreProPurchase();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = ok
          ? 'PRO berhasil dipulihkan ke akun ini.'
          : 'Tidak ada pembelian PRO yang bisa dipulihkan di akun Google Play ini.';
      _noticeIsError = !ok;
    });
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  void _buyViaQris() {
    Navigator.of(context).pop(false);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = AppTheme.inkColor(isDark);
    final muted = AppTheme.mutedColor(isDark);
    final priceLabel = _product?.formattedPrice ?? kProFallbackPrice;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.borderColor(isDark))),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppTheme.borderColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.qrAmber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: AppTheme.qrAmber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upgrade Qristal PRO',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sekali bayar, aktif selamanya.',
                      style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                icon: Icon(Icons.close_rounded, color: muted, size: 20),
                tooltip: 'Tutup',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.subtleBg(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonetizationService._buildFeatureRow(
                  Icons.check_circle_rounded,
                  'Hapus massal foto tanpa batas',
                ),
                MonetizationService._buildFeatureRow(
                  Icons.block_rounded,
                  '100% bebas iklan selamanya',
                ),
                MonetizationService._buildFeatureRow(
                  Icons.bolt_rounded,
                  'Pemindaian galeri prioritas',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_notice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_noticeIsError ? AppTheme.dangerRed : AppTheme.qrisGreen).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_noticeIsError ? AppTheme.dangerRed : AppTheme.qrisGreen).withOpacity(0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _noticeIsError ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: _noticeIsError ? AppTheme.dangerRed : AppTheme.qrisGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _notice!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.qrisGreenDark,
              disabledBackgroundColor: AppTheme.qrisGreenDark.withOpacity(0.5),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy
                ? null
                : (_isAndroid
                    ? (_playReady ? _buyViaPlay : _retryLoadPrice)
                    : _buyViaQris),
            child: _busy || (_isAndroid && _loadingPrice)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAndroid) ...[
                        const Icon(Icons.shop_rounded, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          _isAndroid
                              ? (_playReady
                                  ? 'Beli PRO — $priceLabel'
                                  : 'Muat Ulang Harga')
                              : 'Beli PRO Sekarang ($kProFallbackPrice)',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_isAndroid) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 12, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Pembayaran aman diproses Google Play',
                  style: TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text(
                'Pulihkan Pembelian',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text('Nanti Saja', style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SimulatedAdDialog extends StatefulWidget {
  final String title;
  final String description;
  final int durationSeconds;

  const _SimulatedAdDialog({
    required this.title,
    required this.description,
    required this.durationSeconds,
  });

  @override
  State<_SimulatedAdDialog> createState() => _SimulatedAdDialogState();
}

class _SimulatedAdDialogState extends State<_SimulatedAdDialog> {
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.durationSeconds;
    _startCountdown();
  }

  void _startCountdown() async {
    while (_secondsLeft > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _secondsLeft--;
        });
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.ondemand_video_rounded, color: AppTheme.primary, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  'Menutup otomatis dalam $_secondsLeft dtk...',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
