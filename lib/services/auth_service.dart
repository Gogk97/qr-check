import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_config.dart';
import '../models/user_model.dart';
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
      // 1. Supabase Anonymous Sign-In
      final authRes = await SupabaseService.client.auth.signInAnonymously();
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

  /// Menyimpan data pengguna ke SharedPreferences
  static Future<void> _persistUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setBool(_isLoggedInKey, true);
  }
}
