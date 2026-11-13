import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

/// [Deprecated] Service legacy Google Apps Script / Google Sheets.
///
/// Seluruh sinkronisasi data user dan kuota sekarang dikelola otomatis
/// secara real-time oleh Supabase Database & Auth (Row Level Security).
@Deprecated('Use SupabaseService instead')
class CloudSyncService {
  static const String sheetTransaksiId = 'deprecated';
  static const String sheetUserGoogleId = 'deprecated';
  static const String sheetUserGuestId = 'deprecated';

  static Future<bool> syncUser({
    required UserModel user,
    int? remainingQuota,
    bool? isPro,
  }) async {
    debugPrint('ℹ️ CloudSyncService is deprecated. User data is synced via Supabase Auth & DB.');
    return true;
  }

  static Future<bool> updateRemainingQuota({
    required String userId,
    required bool isGoogle,
    required int newQuota,
  }) async {
    debugPrint('ℹ️ CloudSyncService is deprecated. Quota is managed via Supabase RPC.');
    return true;
  }
}
