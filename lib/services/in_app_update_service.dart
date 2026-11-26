import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Pembaruan aplikasi lewat Google Play tanpa keluar dari aplikasi.
///
/// Dua alur yang dipakai:
///  - **flexible** (default): diunduh di latar belakang, dipasang saat aplikasi
///    di-restart. Pengguna tetap bisa memakai aplikasi selama unduhan.
///  - **immediate**: hanya untuk pembaruan mendesak (priority Play >= 4).
class InAppUpdateService {
  InAppUpdateService._();

  static const MethodChannel _channel =
      MethodChannel('com.qrcheck.app/in_app_update');
  static const String _skipKey = 'in_app_update_skipped_at_v1';
  static const Duration _skipCooldown = Duration(hours: 24);

  static bool _listening = false;
  static bool _busy = false;
  static bool _downloadedHandled = false;

  /// Hanya untuk pengujian: paksa status dukungan platform.
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get isSupported => debugForceSupported ?? Platform.isAndroid;

  /// Dipanggil saat Beranda siap. Aman dipanggil berulang.
  static Future<void> checkAndPrompt(BuildContext context) async {
    if (!isSupported || _busy) return;
    _busy = true;
    try {
      _ensureListener();

      final prefs = await SharedPreferences.getInstance();
      final skippedAt = prefs.getInt(_skipKey) ?? 0;
      if (skippedAt > 0) {
        final elapsed = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(skippedAt));
        if (elapsed < _skipCooldown) return;
      }

      final info = await _checkUpdate();
      if (info == null || !context.mounted) return;

      // Aplikasi hasil sideload tidak bisa memakai alur Play.
      if (info['fromPlayStore'] != true) return;

      final installStatus = info['installStatus'] as int? ?? 0;
      if (installStatus == _installStatusDownloaded) {
        await _promptInstall(context);
        return;
      }

      final available = info['available'] == true;
      final inProgress = info['inProgress'] == true;
      if (!available && !inProgress) return;

      final priority = info['priority'] as int? ?? 0;
      final immediateAllowed = info['immediateAllowed'] == true;
      final flexibleAllowed = info['flexibleAllowed'] == true;

      if (inProgress || (immediateAllowed && priority >= 4)) {
        await _startUpdate('startImmediate');
        return;
      }

      if (!flexibleAllowed) return;
      final started = await _startUpdate('startFlexible');
      if (started == true && context.mounted) {
        _showDownloadingHint(context);
      }
    } catch (_) {
      // Pembaruan bersifat opsional — kegagalan apa pun tidak boleh
      // mengganggu alur utama aplikasi.
    } finally {
      _busy = false;
    }
  }

  /// Pemeriksaan manual dari menu akun (opsional).
  static Future<String> checkManually() async {
    if (!isSupported) return 'Pembaruan otomatis hanya tersedia di Android.';
    try {
      _ensureListener();
      final info = await _checkUpdate();
      if (info == null) return 'Tidak dapat memeriksa pembaruan saat ini.';
      if (info['fromPlayStore'] != true) {
        return 'Pembaruan hanya berlaku untuk aplikasi dari Play Store.';
      }
      if (info['available'] != true && info['inProgress'] != true) {
        return 'Aplikasi sudah versi terbaru.';
      }
      final priority = info['priority'] as int? ?? 0;
      if (info['immediateAllowed'] == true && priority >= 4) {
        await _startUpdate('startImmediate');
        return 'Pembaruan penting sedang dipasang…';
      }
      final started = await _startUpdate('startFlexible');
      return started == true
          ? 'Pembaruan sedang diunduh di latar belakang.'
          : 'Pembaruan belum dapat dimulai.';
    } catch (_) {
      return 'Tidak dapat memeriksa pembaruan saat ini.';
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _checkUpdate() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkUpdate');
    if (raw == null) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static Future<bool?> _startUpdate(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method);
    } on PlatformException {
      return false;
    }
  }

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDownloaded' && !_downloadedHandled) {
        _downloadedHandled = true;
        final ctx = _rootContext;
        if (ctx != null && ctx.mounted) await _promptInstall(ctx);
      }
      return null;
    });
  }

  static BuildContext? _rootContext;

  /// Konteks dipakai untuk menampilkan dialog setelah unduhan selesai.
  static void attachContext(BuildContext context) => _rootContext = context;

  static void _showDownloadingHint(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Memperbarui Qristal di latar belakang…',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _promptInstall(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    final install = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: AppTheme.cardColor(dark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppTheme.primary, size: 26),
          ),
          title: const Text(
            'Pembaruan siap dipasang',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Versi terbaru Qristal sudah terunduh. Pasang sekarang untuk '
            'mendapatkan perbaikan dan fitur baru.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.mutedColor(dark),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Nanti',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mutedColor(dark),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              ),
              child: const Text(
                'Pasang sekarang',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (install == true) {
      _downloadedHandled = false;
      await _channel.invokeMethod<bool>('completeUpdate');
    } else {
      await prefs.setInt(_skipKey, DateTime.now().millisecondsSinceEpoch);
      _downloadedHandled = false;
    }
  }

  // Nilai InstallStatus dari Play Core.
  static const int _installStatusDownloaded = 11; // InstallStatus.DOWNLOADED
}
