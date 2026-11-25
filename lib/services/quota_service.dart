import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'ad_service.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'monetization_service.dart';
import 'supabase_service.dart';
import '../utils/app_log.dart';

/// Layanan manajemen kuota penghapusan foto untuk pengguna QRIS Detector.
///
/// Terhubung dengan Supabase RPC (consume_quota & claim_ad_reward)
/// dengan append-only audit trail di quota_ledger dan perlindungan RLS.
class QuotaService {
  static const String _quotaKey = 'user_delete_quota_v1';
  static const String _initializedUsersKey = 'initialized_quota_users_v1';

  // --- Kuota offline (antrean sinkronisasi) ---
  static const String _pendingKey = 'quota_pending_ops_v1';
  static const String _offlineAllowanceKey = 'quota_offline_allowance_v1';
  static const String _offlineDateKey = 'quota_offline_date_v1';

  /// Batas pemakaian tanpa jaringan per hari. Mencegah bypass dengan
  /// mematikan internet, tetapi tetap memberi jalan saat sinyal buruk.
  static const int offlineDailyAllowance = 20;

  static bool _usedOffline = false;

  /// True bila operasi terakhir memakai kuota offline (belum tersinkron).
  static bool get usedOffline => _usedOffline;

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
              AppLog.d('⚠️ Anti-Abuse notice: ${res['message']}');
            }
            return serverQuota;
          }
        }

        // Server menolak klaim (DEVICE_MISMATCH / DEVICE_LIMIT_REACHED /
        // RATE_LIMITED). Jangan mengarang kuota lokal: pakai nilai server.
        if (res is Map && res['remaining_quota'] != null) {
          final serverQuota = (res['remaining_quota'] as num).toInt();
          await prefs.setInt(_quotaKey, serverQuota);
          await prefs.setInt(userQuotaKey, serverQuota);
          if (res['is_pro'] == true) {
            await MonetizationService.setProUser(true, userId: userId);
          }
          AppLog.d('⚠️ Klaim kuota ditolak server: ${res['error']}');
          return serverQuota;
        }
      }
    } catch (e) {
      AppLog.d('⚠️ Supabase claim_device_welcome_quota error: $e');
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

  /// Pesan error terakhir dari operasi kuota (untuk ditampilkan di UI).
  static String? _lastQuotaError;
  static String? get lastError => _lastQuotaError;

  /// Memeriksa apakah kuota mencukupi untuk menghapus sejumlah [needed] foto.
  /// Catatan: ini hanya untuk gating UI — keputusan final tetap di server
  /// (`consume_quota`).
  static Future<bool> hasEnoughQuota(int needed) async {
    final isPro = await MonetizationService.isProUser();
    if (isPro) return true;
    final current = await getRemainingQuota();
    return current >= needed;
  }

  /// Mengurangi kuota secara atomik **di server**.
  ///
  /// Tidak ada fallback lokal: kalau server tidak bisa dihubungi, operasi
  /// ditolak supaya kuota tidak bisa dipakai gratis saat offline.
  static Future<bool> consumeQuota(
    int count, {
    String? userId,
    String? refId,
  }) async {
    if (count <= 0) return true;
    _lastQuotaError = null;

    if (!SupabaseService.isAuthenticated) {
      return _consumeOffline(count, refId ?? 'del_${DateTime.now().microsecondsSinceEpoch}');
    }

    final prefs = await SharedPreferences.getInstance();
    final currentUserId = userId ?? prefs.getString('last_active_user_id_v1');
    final ref = refId ?? 'del_${DateTime.now().microsecondsSinceEpoch}';

    try {
      final res = await SupabaseService.client.rpc('consume_quota', params: {
        'p_amount': count,
        'p_ref_id': ref,
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
      }

      final code = res is Map ? res['code'] : null;
      _lastQuotaError = switch (code) {
        'INSUFFICIENT_QUOTA' => 'Kuota tidak cukup. Tonton iklan atau upgrade PRO.',
        'RATE_LIMITED' => 'Terlalu banyak permintaan. Coba lagi sebentar.',
        _ => 'Kuota gagal dipotong (${code ?? 'unknown'}).',
      };
      return false;
    } catch (e) {
      // Jaringan bermasalah → pakai jatah offline, sinkronkan nanti.
      AppLog.d('⚠️ consume_quota gagal (${e.runtimeType}), mencoba jalur offline');
      return _consumeOffline(count, ref);
    }
  }

  /// Potong kuota secara lokal saat offline, lalu antre untuk disinkronkan.
  ///
  /// Dibatasi [offlineDailyAllowance] item per hari supaya tidak bisa dipakai
  /// sebagai celah gratis tanpa batas.
  static Future<bool> _consumeOffline(int count, String refId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    if (prefs.getString(_offlineDateKey) != today) {
      await prefs.setString(_offlineDateKey, today);
      await prefs.setInt(_offlineAllowanceKey, offlineDailyAllowance);
    }

    final allowance = prefs.getInt(_offlineAllowanceKey) ?? offlineDailyAllowance;
    if (allowance < count) {
      _lastQuotaError =
          'Kuota offline habis ($allowance tersisa hari ini). Sambungkan '
          'internet untuk melanjutkan.';
      return false;
    }

    await prefs.setInt(_offlineAllowanceKey, allowance - count);

    final pending = prefs.getStringList(_pendingKey) ?? <String>[];
    pending.add(jsonEncode({
      'count': count,
      'refId': refId,
      'at': now.toIso8601String(),
    }));
    await prefs.setStringList(_pendingKey, pending);

    _usedOffline = true;
    _lastQuotaError = null;
    AppLog.d('📴 Kuota offline dipakai: $count '
        '(sisa jatah hari ini ${allowance - count})');
    return true;
  }

  /// Jumlah item yang menunggu sinkronisasi kuota.
  static Future<int> pendingOfflineItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? const [];
    var total = 0;
    for (final entry in raw) {
      try {
        final op = jsonDecode(entry);
        if (op is Map) total += (op['count'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    return total;
  }

  /// Kirim ulang pemotongan kuota yang terjadi saat offline.
  /// Dipanggil saat aplikasi dibuka dan setelah operasi online berhasil.
  static Future<int> syncPending() async {
    if (!SupabaseService.isAuthenticated) return 0;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? <String>[];
    if (raw.isEmpty) return 0;

    final keep = <String>[];
    var synced = 0;

    for (final entry in raw) {
      Map<String, dynamic> op;
      try {
        final decoded = jsonDecode(entry);
        if (decoded is! Map) continue;
        op = Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }

      final count = (op['count'] as num?)?.toInt() ?? 0;
      final refId = '${op['refId'] ?? ''}';
      if (count <= 0 || refId.isEmpty) continue;

      var retry = false;
      try {
        final res = await SupabaseService.client.rpc('consume_quota', params: {
          'p_amount': count,
          'p_ref_id': refId,
        });
        if (res is Map && res['success'] == true) {
          synced += count;
          final remaining = (res['remaining_quota'] as num?)?.toInt();
          if (remaining != null) {
            await prefs.setInt(_quotaKey, remaining);
            final uid = prefs.getString('last_active_user_id_v1');
            if (uid != null) await prefs.setInt('user_quota_v1_$uid', remaining);
          }
        } else {
          retry = true; // kuota habis / rate limit → coba lagi nanti
        }
      } catch (_) {
        retry = true; // masih offline
      }
      if (retry) keep.add(entry);
    }

    await prefs.setStringList(_pendingKey, keep);
    if (synced > 0) {
      AppLog.d('☁️ Sinkron kuota offline: $synced item, '
          '${keep.length} operasi tersisa');
    }
    return synced;
  }

  /// Kembalikan kuota yang sudah terpotong bila penghapusan dibatalkan.
  /// Idempoten di server: satu [refId] hanya bisa di-refund sekali.
  static Future<void> refundQuota(String refId, int amount) async {
    // Bila potongan masih di antrean offline, cukup buang dari antrean.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? <String>[];
    if (raw.isNotEmpty) {
      final kept = <String>[];
      var removed = false;
      for (final entry in raw) {
        try {
          final op = jsonDecode(entry);
          if (op is Map && '${op['refId']}' == refId) {
            removed = true;
            continue;
          }
        } catch (_) {}
        kept.add(entry);
      }
      if (removed) {
        await prefs.setStringList(_pendingKey, kept);
        AppLog.d('↩️ Potongan kuota offline dibatalkan ($refId)');
        return;
      }
    }

    if (amount <= 0 || !SupabaseService.isAuthenticated) return;
    try {
      await SupabaseService.client.rpc('refund_quota', params: {
        'p_ref_id': refId,
        'p_amount': amount,
      });
    } catch (e) {
      AppLog.d('⚠️ refund_quota gagal: $e');
    }
  }

  /// Menambah kuota lewat server (RPC `claim_ad_reward`).
  /// Tidak ada penambahan lokal: kalau server menolak/gagal, kuota tidak berubah.
  static Future<int> addQuota(int amount, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = userId ?? prefs.getString('last_active_user_id_v1');
    final current = await getRemainingQuota();
    _lastQuotaError = null;

    if (amount <= 0) return current;
    if (!SupabaseService.isAuthenticated) {
      _lastQuotaError = 'Butuh koneksi internet untuk menambah kuota.';
      return current;
    }

    try {
      final res = await SupabaseService.client.rpc('claim_ad_reward', params: {
        'p_ref_id': 'ad_${DateTime.now().microsecondsSinceEpoch}',
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

      final code = res is Map ? res['code'] : null;
      _lastQuotaError = switch (code) {
        'DAILY_LIMIT_REACHED' => 'Batas reward iklan harian tercapai.',
        'RATE_LIMITED' => 'Terlalu cepat. Coba lagi beberapa saat.',
        _ => 'Reward iklan gagal diklaim (${code ?? 'unknown'}).',
      };
    } catch (e) {
      AppLog.d('⚠️ claim_ad_reward gagal: $e');
      _lastQuotaError = 'Tidak dapat menghubungi server. Coba lagi saat online.';
    }

    return current;
  }

  /// Reset Kuota (untuk kebutuhan Developer / Testing)
  static Future<void> devResetQuota(int quota) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_quotaKey, quota);
  }

  /// Menampilkan Rewarded AdMob nyata untuk mendapatkan +1 Kuota Hapus.
  /// Reward hanya diberikan bila Google mengonfirmasi iklan selesai ditonton.
  static Future<bool> watchRewardedAdForQuota(BuildContext context) async {
    if (!context.mounted) return false;

    final userId = SupabaseService.isInitialized
        ? SupabaseService.client.auth.currentUser?.id
        : null;
    final earned = await AdService.showRewarded(userId: userId);

    if (!earned) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Iklan belum selesai atau belum tersedia. Kuota belum ditambahkan.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: AppTheme.cardColor(isDark),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.qrAmber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hourglass_empty_rounded, color: AppTheme.qrAmber, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kuota Hapus Tidak Cukup',
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dibutuhkan', style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark))),
                        Text(
                          '$needed Foto',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.dangerRed,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    Container(height: 28, width: 1, color: AppTheme.borderColor(isDark)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Sisa Kuota Anda', style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark))),
                        Text(
                          '$current Foto',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.qrAmber,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pilih opsi di bawah untuk menambah kuota atau hapus tanpa batas:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.mutedColor(isDark),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),

              // Opsi 1: Tonton Iklan (+1 Kuota)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
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
                    child: const Icon(Icons.ondemand_video_rounded, color: AppTheme.primary, size: 20),
                  ),
                  title: Text(
                    'Tonton Iklan (+1 Kuota)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.inkColor(isDark)),
                  ),
                  subtitle: Text(
                    'Tonton video sponsor singkat 3 detik untuk +1 kuota.',
                    style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                  ),
                  onTap: () => Navigator.of(ctx).pop('watch_ad'),
                ),
              ),

              const SizedBox(height: 8),

              // Opsi 2: Beli PRO (Unlimited)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.qrAmber.withOpacity(0.4)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.qrAmber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: AppTheme.qrAmber, size: 20),
                  ),
                  title: const Text(
                    'Upgrade ke PRO (Lifetime)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.qrAmber),
                  ),
                  subtitle: Text(
                    'Hapus tanpa batas selamanya & 100% bebas iklan!',
                    style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                  ),
                  onTap: () => Navigator.of(ctx).pop('buy_pro'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text('Batal', style: TextStyle(color: AppTheme.mutedColor(isDark), fontWeight: FontWeight.w600)),
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
      return MonetizationService.openProPurchase(context);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: AppTheme.cardColor(isDark),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPro ? AppTheme.qrAmber.withOpacity(0.15) : AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isPro ? Icons.star_rounded : Icons.confirmation_number_rounded,
                  color: isPro ? AppTheme.qrAmber : AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kuota Hapus Foto',
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
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPro ? AppTheme.qrAmber.withOpacity(0.4) : AppTheme.borderColor(isDark),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'STATUS SAAT INI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mutedColor(isDark),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isPro ? 'UNLIMITED' : '$remaining Foto',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: isPro ? AppTheme.qrAmber : AppTheme.inkColor(isDark),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPro
                          ? 'Fitur PRO Aktif: Hapus massal tanpa batas!'
                          : '1 kuota digunakan untuk setiap 1 foto yang dibersihkan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: AppTheme.mutedColor(isDark)),
                    ),
                  ],
                ),
              ),
              if (!isPro) ...[
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await watchRewardedAdForQuota(context);
                  },
                  icon: const Icon(Icons.ondemand_video_rounded, size: 18),
                  label: const Text('Nonton Iklan (+1 Kuota Hapus)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await MonetizationService.openProPurchase(context);
                  },
                  icon: const Icon(Icons.workspace_premium_rounded, color: AppTheme.qrAmber, size: 18),
                  label: const Text('Beli PRO (Tanpa Batas Kuota)', style: TextStyle(color: AppTheme.qrAmber, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.qrAmber.withOpacity(0.5)),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Tutup', style: TextStyle(color: AppTheme.mutedColor(isDark), fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }
}
