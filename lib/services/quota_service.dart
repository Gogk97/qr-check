import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/qris_payment_screen.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'monetization_service.dart';
import 'supabase_service.dart';

/// Layanan manajemen kuota penghapusan foto untuk pengguna QRIS Detector.
///
/// Terhubung dengan Supabase RPC (consume_quota & claim_ad_reward)
/// dengan append-only audit trail di quota_ledger dan perlindungan RLS.
class QuotaService {
  static const String _quotaKey = 'user_delete_quota_v1';
  static const String _initializedUsersKey = 'initialized_quota_users_v1';

  /// Inisialisasi kuota saat login akun (sinkronisasi dari server Supabase dengan perlindungan anti-exploit)
  static Future<int> initQuotaForLogin({
    required bool isGoogle,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_active_user_id_v1', userId);
    final userQuotaKey = 'user_quota_v1_$userId';

    // 1. Klaim kuota selamat datang terikat device (Anti Multi-Account / Reinstall Abuse)
    try {
      if (SupabaseService.isAuthenticated) {
        final deviceDetails = await DeviceService.getDeviceDetails();
        final deviceId = deviceDetails['device_id'] ?? userId;

        final res = await SupabaseService.client.rpc('claim_device_welcome_quota', params: {
          'p_device_id': deviceId,
          'p_device_brand': deviceDetails['device_brand'],
          'p_device_model': deviceDetails['device_model'],
          'p_os_version': deviceDetails['os_version'],
        });

        if (res is Map && res['success'] == true) {
          final serverQuota = (res['remaining_quota'] as num?)?.toInt();
          final serverIsPro = res['is_pro'] as bool? ?? false;
          if (serverIsPro) {
            await MonetizationService.setProUser(true, userId: userId);
          }
          if (serverQuota != null) {
            await prefs.setInt(_quotaKey, serverQuota);
            await prefs.setInt(userQuotaKey, serverQuota);
            if (res['bonus_granted'] == false && res['message'] != null) {
              debugPrint('⚠️ Anti-Abuse notice: ${res['message']}');
            }
            return serverQuota;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Supabase claim_device_welcome_quota error: $e');
    }

    final initializedList = prefs.getStringList(_initializedUsersKey) ?? [];
    if (!initializedList.contains(userId)) {
      final initialQuota = isGoogle ? 10 : 5;
      await prefs.setInt(userQuotaKey, initialQuota);
      await prefs.setInt(_quotaKey, initialQuota);
      initializedList.add(userId);
      await prefs.setStringList(_initializedUsersKey, initializedList);
      return initialQuota;
    }

    // Kembalikan sisa kuota yang sebelumnya tercatat untuk user/device ini
    final existing = prefs.getInt(userQuotaKey) ?? prefs.getInt(_quotaKey) ?? (isGoogle ? 10 : 5);
    await prefs.setInt(_quotaKey, existing);
    return existing;
  }

  /// Mengambil sisa kuota hapus saat ini
  static Future<int> getRemainingQuota() async {
    final prefs = await SharedPreferences.getInstance();

    // Coba sync real-time dengan Supabase
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        final row = await SupabaseService.client
            .from('profiles')
            .select('remaining_quota, is_pro')
            .eq('id', userId)
            .maybeSingle();

        if (row != null) {
          final q = row['remaining_quota'] as int?;
          if (q != null) {
            await prefs.setInt(_quotaKey, q);
            return q;
          }
        }
      }
    } catch (_) {}

    final val = prefs.getInt(_quotaKey);
    if (val != null) return val;

    final user = await AuthService.getCurrentUser();
    final defaultQuota = (user != null && !user.isGuest) ? 10 : 5;
    await prefs.setInt(_quotaKey, defaultQuota);
    return defaultQuota;
  }

  /// Memeriksa apakah kuota mencukupi untuk menghapus sejumlah [needed] foto
  static Future<bool> hasEnoughQuota(int needed) async {
    final isPro = await MonetizationService.isProUser();
    if (isPro) return true; // PRO User = Unlimited
    final current = await getRemainingQuota();
    return current >= needed;
  }

  /// Mengurangi kuota sebesar [count] secara atomik via Supabase RPC
  static Future<bool> consumeQuota(int count, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = userId ?? prefs.getString('last_active_user_id_v1');
    final isPro = await MonetizationService.isProUser(userId: currentUserId);
    if (isPro) return true; // PRO User tidak mengurangi kuota

    // 1. Mutasi atomik di server Supabase
    try {
      if (SupabaseService.isAuthenticated) {
        final res = await SupabaseService.client.rpc('consume_quota', params: {
          'p_amount': count,
          'p_ref_id': 'del_${DateTime.now().millisecondsSinceEpoch}',
        });

        if (res is Map && res['success'] == true) {
          final remaining = (res['remaining_quota'] as num?)?.toInt();
          if (remaining != null) {
            await prefs.setInt(_quotaKey, remaining);
            if (currentUserId != null) {
              await prefs.setInt('user_quota_v1_$currentUserId', remaining);
            }
          }
          return true;
        } else if (res is Map && res['code'] == 'INSUFFICIENT_QUOTA') {
          return false;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Supabase consume_quota error, fallback local: $e');
    }

    // 2. Fallback offline
    final current = await getRemainingQuota();
    if (current < count) return false;

    final newQuota = current - count;
    await prefs.setInt(_quotaKey, newQuota);

    if (currentUserId != null && currentUserId.isNotEmpty) {
      await prefs.setInt('user_quota_v1_$currentUserId', newQuota);
    }

    return true;
  }

  /// Menambah kuota sebesar [amount] (misal: +1 dari menonton video sponsor) via Supabase RPC
  static Future<int> addQuota(int amount, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = userId ?? prefs.getString('last_active_user_id_v1');

    // 1. Eksekusi di server Supabase
    try {
      if (SupabaseService.isAuthenticated) {
        final res = await SupabaseService.client.rpc('claim_ad_reward', params: {
          'p_ref_id': 'ad_${DateTime.now().millisecondsSinceEpoch}',
        });

        if (res is Map && res['success'] == true) {
          final remaining = (res['remaining_quota'] as num?)?.toInt();
          if (remaining != null) {
            await prefs.setInt(_quotaKey, remaining);
            if (currentUserId != null) {
              await prefs.setInt('user_quota_v1_$currentUserId', remaining);
            }
            return remaining;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Supabase claim_ad_reward error, fallback local: $e');
    }

    // 2. Fallback offline
    final current = await getRemainingQuota();
    final newQuota = current + amount;
    await prefs.setInt(_quotaKey, newQuota);

    if (currentUserId != null && currentUserId.isNotEmpty) {
      await prefs.setInt('user_quota_v1_$currentUserId', newQuota);
    }

    return newQuota;
  }

  /// Reset Kuota (untuk kebutuhan Developer / Testing)
  static Future<void> devResetQuota(int quota) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_quotaKey, quota);
  }

  /// Menampilkan simulasi Iklan Rewarded Video untuk mendapatkan +1 Kuota
  static Future<bool> watchRewardedAdForQuota(BuildContext context) async {
    if (!context.mounted) return false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return const _RewardedAdDialog(
          title: 'Iklan Video Rewarded',
          description: 'Tonton sponsor selama beberapa detik untuk mendapatkan +1 Kuota Hapus...',
          durationSeconds: 3,
        );
      },
    );

    final newQuota = await addQuota(1);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('🎉 Berhasil! +1 Kuota ditambahkan. Sisa kuota: $newQuota foto.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.qrisGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return true;
  }

  /// Dialog ketika kuota hapus habis atau tidak cukup
  static Future<bool> showQuotaExhaustedDialog(
    BuildContext context, {
    required int needed,
    required int current,
  }) async {
    if (!context.mounted) return false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Kuota Hapus Tidak Cukup',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dibutuhkan', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          '$needed Foto',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.red),
                        ),
                      ],
                    ),
                    Container(height: 28, width: 1, color: Colors.grey.withOpacity(0.3)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Sisa Kuota Anda', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          '$current Foto',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.orange),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih opsi di bawah untuk menambah kuota atau hapus tanpa batas:',
                style: TextStyle(fontSize: 12, height: 1.3),
              ),
              const SizedBox(height: 14),

              // Opsi 1: Tonton Iklan (+1 Kuota)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primary,
                    radius: 20,
                    child: Icon(Icons.ondemand_video_rounded, color: Colors.white, size: 22),
                  ),
                  title: const Text(
                    'Tonton Iklan (+1 Kuota)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Tonton video sponsor singkat 3 detik untuk +1 kuota.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.of(ctx).pop('watch_ad'),
                ),
              ),

              const SizedBox(height: 10),

              // Opsi 2: Beli PRO (Unlimited)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFD97706).withOpacity(0.12),
                      const Color(0xFFF59E0B).withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFD97706),
                    radius: 20,
                    child: Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 22),
                  ),
                  title: const Text(
                    'Upgrade ke PRO (Rp 15.000)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFD97706)),
                  ),
                  subtitle: const Text(
                    'Hapus tanpa batas selamanya & 100% bebas iklan!',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.of(ctx).pop('buy_pro'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Batal'),
            ),
          ],
        );
      },
    );

    if (result == 'watch_ad') {
      if (!context.mounted) return false;
      return await watchRewardedAdForQuota(context);
    } else if (result == 'buy_pro') {
      if (!context.mounted) return false;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
      );
      return false;
    }

    return false;
  }

  /// Dialog manajemen & info kuota (saat user klik chip kuota di AppBar)
  static Future<void> showQuotaManagementDialog(BuildContext context) async {
    final isPro = await MonetizationService.isProUser();
    final remaining = await getRemainingQuota();
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPro ? Colors.amber.withOpacity(0.15) : AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPro ? Icons.star_rounded : Icons.confirmation_number_rounded,
                  color: isPro ? Colors.amber : AppTheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Kuota Hapus Foto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isPro ? Colors.amber.withOpacity(0.4) : AppTheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'STATUS SAAT INI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isPro ? 'UNLIMITED' : '$remaining Foto',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: isPro ? Colors.amber : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPro
                          ? '✨ Fitur PRO Aktif: Hapus massal tanpa batas!'
                          : '1 kuota digunakan untuk setiap 1 foto yang dibersihkan.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (!isPro) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await watchRewardedAdForQuota(context);
                  },
                  icon: const Icon(Icons.ondemand_video_rounded, size: 20),
                  label: const Text('Nonton Iklan (+1 Kuota Hapus)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706), size: 20),
                  label: const Text('Beli PRO (Tanpa Batas Kuota)', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD97706)),
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }
}

class _RewardedAdDialog extends StatefulWidget {
  final String title;
  final String description;
  final int durationSeconds;

  const _RewardedAdDialog({
    required this.title,
    required this.description,
    required this.durationSeconds,
  });

  @override
  State<_RewardedAdDialog> createState() => _RewardedAdDialogState();
}

class _RewardedAdDialogState extends State<_RewardedAdDialog> {
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
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Hadiah diberikan dalam $_secondsLeft detik...',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
