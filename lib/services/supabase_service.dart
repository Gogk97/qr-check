import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_config.dart';
import 'secure_session_storage.dart';
import '../utils/app_log.dart';

/// Central Supabase Client & Lifecycle Manager
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Token sesi disimpan di Keystore/Keychain (bukan SharedPreferences plaintext).
      final projectRef = Uri.parse(SupabaseConfig.projectUrl).host.split('.').first;
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        // ignore: deprecated_member_use
        anonKey: SupabaseConfig.anonKey,
        debug: kDebugMode,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(
            persistSessionKey: 'sb-$projectRef-auth-token',
          ),
        ),
      );
      _initialized = true;
      AppLog.d('✅ Supabase initialized successfully: ${SupabaseConfig.projectUrl}');
    } catch (e) {
      AppLog.d('⚠️ Supabase initialize error: $e');
    }
  }

  /// Current user ID (null if not authenticated or not initialized)
  static String? get currentUserId => _initialized ? client.auth.currentUser?.id : null;

  /// Check if user is currently signed in via Supabase Auth
  static bool get isAuthenticated => _initialized && client.auth.currentUser != null;
}
