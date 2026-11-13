import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/qris_payment_screen.dart';
import '../theme/app_theme.dart';
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
                    'Upgrade ke PRO (Rp 15.000)',
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

  /// Modal Pembelian / Simulasi Aktivasi Fitur PRO
  static Future<bool> showProUpgradeModal(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium, color: Colors.amber, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'Upgrade QRIS Detector PRO',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Nikmati kebebasan penuh tanpa batasan iklan!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              _buildFeatureRow(Icons.check_circle_rounded, 'Hapus Massal Foto Tanpa Batas'),
              _buildFeatureRow(Icons.block_rounded, '100% Bebas Semua Jenis Iklan Selamanya'),
              _buildFeatureRow(Icons.bolt_rounded, 'Pemindaian Galeri AI Ekstra Cepat'),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.qrisGreenDark,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  Navigator.of(context).pop(false);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
                  );
                },
                child: const Text(
                  'Beli PRO Sekarang (Rp 15.000)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Nanti Saja'),
              ),
            ],
          ),
        );
      },
    );

    return result ?? false;
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
