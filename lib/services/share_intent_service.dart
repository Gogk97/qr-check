import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Menerima gambar yang dibagikan dari aplikasi lain (WhatsApp, Telegram,
/// Galeri, Files) melalui Android share sheet.
///
/// Native (`ShareIntentBridge.kt`) menyalin gambar ke cache aplikasi lalu
/// mengirim path-nya. Dua jalur:
/// - **Cold start** — `drainPending()` saat aplikasi dibuka dari share sheet.
/// - **Warm start** — [stream] saat aplikasi sudah berjalan.
class ShareIntentService {
  ShareIntentService._();

  static const MethodChannel _channel = MethodChannel('com.qrcheck.app/share');
  static final StreamController<List<File>> _controller =
      StreamController<List<File>>.broadcast();

  static bool _initialized = false;

  /// Stream gambar yang masuk saat aplikasi sudah berjalan.
  static Stream<List<File>> get stream => _controller.stream;

  static bool get isSupported => Platform.isAndroid;

  /// Pasang handler channel. Aman dipanggil berkali-kali.
  static void init() {
    if (_initialized || !isSupported) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedFiles') return null;
      final paths = (call.arguments as List?)?.whereType<String>().toList() ??
          const <String>[];
      final files = _existing(paths);
      if (files.isNotEmpty) _controller.add(files);
      return null;
    });
  }

  /// Ambil gambar yang dikirim saat aplikasi belum berjalan (cold start).
  static Future<List<File>> drainPending() async {
    if (!isSupported) return const [];
    try {
      final paths =
          await _channel.invokeMethod<List<Object?>>('getPendingFiles') ??
              const [];
      return _existing(paths.whereType<String>());
    } catch (_) {
      return const [];
    }
  }

  static List<File> _existing(Iterable<String> paths) => paths
      .map((p) => File(p))
      .where((f) => f.existsSync() && f.lengthSync() > 0)
      .toList();
}
