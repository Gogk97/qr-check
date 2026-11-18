import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_log.dart';

/// Penyimpanan sesi Supabase di **Keystore (Android) / Keychain (iOS) / WebCrypto**.
///
/// Sebelumnya `supabase_flutter` memakai SharedPreferences (plaintext) sehingga
/// access+refresh token bisa diekstrak lewat ADB backup / auto-backup.
///
/// Kelas ini juga memigrasikan sesi lama: kalau SharedPreferences masih memuat
/// token, token dipindah ke secure storage lalu dihapus dari prefs.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null || legacy.isEmpty) return;

      final existing = await _storage.read(key: persistSessionKey);
      if (existing == null || existing.isEmpty) {
        await _storage.write(key: persistSessionKey, value: legacy);
      }
      // Hapus salinan plaintext lama.
      await prefs.remove(persistSessionKey);
    } catch (e) {
      // Jangan gagalkan startup hanya karena migrasi storage.
      if (kDebugMode) AppLog.d('⚠️ SecureSessionStorage migration: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await _storage.read(key: persistSessionKey);
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);
}
