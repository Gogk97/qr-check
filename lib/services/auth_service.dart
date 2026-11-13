import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_config.dart';
import '../models/user_model.dart';
import 'device_service.dart';
import 'monetization_service.dart';
import 'quota_service.dart';
import 'supabase_service.dart';

class AuthService {
  static const String _userKey = 'current_user_v1';
  static const String _isLoggedInKey = 'is_logged_in_v1';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: SupabaseConfig.googleWebClientId,
    scopes: ['email', 'profile'],
  );

  /// Mengecek apakah pengguna sedang login (baik Supabase Session aktif atau data lokal)
  static Future<bool> isLoggedIn() async {
    final session = SupabaseService.client.auth.currentSession;
    if (session != null) return true;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /// Mengambil data pengguna yang tersimpan
  static Future<UserModel?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      if (raw == null || raw.isEmpty) return null;
      return UserModel.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return null;
    }
  }

  /// Login sebagai pengguna tamu (Supabase Anonymous Sign-In)
  static Future<UserModel> loginAsGuest() async {
    try {
      final deviceDetails = await DeviceService.getDeviceDetails();

      // 1. Supabase Anonymous Sign-In dengan metadata device langsung
      final authRes = await SupabaseService.client.auth.signInAnonymously(
        data: {
          'full_name': 'Pengguna Tamu',
          'is_guest': true,
          'device_id': deviceDetails['device_id'],
          'device_brand': deviceDetails['device_brand'],
          'device_model': deviceDetails['device_model'],
          'os_version': deviceDetails['os_version'],
          'device_platform': deviceDetails['device_platform'],
          'device_summary': deviceDetails['device_summary'],
        },
      );
      final supaUser = authRes.user;
      final userId = supaUser?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      final user = UserModel(
        id: userId,
        name: 'Pengguna Tamu',
        email: supaUser?.email ?? '',
        avatarUrl: null,
        isGuest: true,
        loginAt: DateTime.now(),
      );

      await _persistUser(user);
      await QuotaService.initQuotaForLogin(isGoogle: false, userId: user.id);
      await MonetizationService.isProUser(userId: user.id);
      await syncDeviceInfoToServer();
      return user;
    } catch (e) {
      debugPrint('⚠️ Supabase Anonymous login error, fallback local: $e');
      final fallbackUser = UserModel.guest();
      await _persistUser(fallbackUser);
      await QuotaService.initQuotaForLogin(isGoogle: false, userId: fallbackUser.id);
      return fallbackUser;
    }
  }

  /// Login dengan Google Sign-In SDK + Supabase OAuth Handshake
  static Future<UserModel?> loginWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        return null;
      }

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      String userId = account.id;

      // Exchange with Supabase Auth if tokens are present
      if (idToken != null && idToken.isNotEmpty) {
        try {
          final res = await SupabaseService.client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );
          if (res.user != null) {
            userId = res.user!.id;
          }
        } catch (supaErr) {
          debugPrint('⚠️ Supabase ID token exchange warning: $supaErr');
        }
      }

      final user = UserModel.googleUser(
        id: userId,
        name: account.displayName ?? 'Pengguna Google',
        email: account.email,
        avatarUrl: account.photoUrl,
      );

      await _persistUser(user);
      await QuotaService.initQuotaForLogin(isGoogle: true, userId: user.id);
      await MonetizationService.isProUser(userId: user.id);
      await syncDeviceInfoToServer();
      return user;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// Fallback Dev Login Google jika Google Play Services / SHA-1 belum dipasang di environment dev
  static Future<UserModel> loginWithGoogleDevFallback() async {
    // Coba anonymous sign in sebagai dev session di Supabase
    String userId = 'dev_google_user';
    try {
      final authRes = await SupabaseService.client.auth.signInAnonymously();
      if (authRes.user != null) {
        userId = authRes.user!.id;
      }
    } catch (_) {}

    final user = UserModel.googleUser(
      id: userId,
      name: 'Google User (Dev)',
      email: 'dev.tester@gmail.com',
      avatarUrl: null,
    );
    await _persistUser(user);
    await QuotaService.initQuotaForLogin(isGoogle: true, userId: user.id);
    await MonetizationService.isProUser(userId: user.id);
    return user;
  }

  /// Logout dan bersihkan data sesi
  static Future<void> logout() async {
    try {
      await SupabaseService.client.auth.signOut();
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      debugPrint('Error during Sign-Out: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.setBool(_isLoggedInKey, false);
  }

  /// Sinkronisasi informasi spesifikasi detail perangkat ke database Supabase profiles
  static Future<void> syncDeviceInfoToServer() async {
    try {
      if (!SupabaseService.isAuthenticated) return;
      final details = await DeviceService.getDeviceDetails();

      // 1. Simpan ke raw_user_meta_data di auth.users (tampil di dashboard auth)
      try {
        await SupabaseService.client.auth.updateUser(
          UserAttributes(data: details),
        );
      } catch (e) {
        debugPrint('⚠️ Auth metadata update notice: $e');
      }

      // 2. Simpan ke tabel profiles via RPC SECURITY DEFINER
      await SupabaseService.client.rpc('update_device_info', params: {
        'p_device_id': details['device_id'],
        'p_device_brand': details['device_brand'],
        'p_device_model': details['device_model'],
        'p_os_version': details['os_version'],
        'p_device_platform': details['device_platform'],
        'p_device_summary': details['device_summary'],
      });
      debugPrint('📱 Device info synced to Supabase: ${details['device_summary']}');
    } catch (e) {
      debugPrint('⚠️ Failed to sync device info: $e');
    }
  }

  /// Menyimpan data pengguna ke SharedPreferences
  static Future<void> _persistUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setBool(_isLoggedInKey, true);
  }
}
