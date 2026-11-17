import 'package:flutter/foundation.dart';

/// Logger yang otomatis mati di build rilis.
///
/// `debugPrint` bawaan Flutter tetap menulis ke logcat pada build release,
/// sehingga detail error/path bisa bocor ke log perangkat. Gunakan `AppLog.d`
/// untuk semua logging non-kritis.
class AppLog {
  const AppLog._();

  static void d(Object? message) {
    if (kDebugMode) {
      debugPrint(message?.toString());
    }
  }

  static void e(Object? message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('❌ $message${error == null ? '' : ': $error'}');
      if (stack != null) debugPrint(stack.toString());
    }
  }
}
