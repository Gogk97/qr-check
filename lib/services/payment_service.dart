import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_record.dart';
import 'supabase_service.dart';

/// Layanan pembayaran QRIS dengan integrasi Supabase Storage & Database.
///
/// Foto bukti transfer diunggah langsung ke bucket privat 'payment-proofs',
/// dan record transaksi disimpan di tabel 'payments' untuk verifikasi admin.
class PaymentService {
  static const String _localPaymentsKey = 'local_payments_v1';
  static const String _storageBucket = 'payment-proofs';

  /// Cek apakah Supabase sudah siap digunakan
  static Future<bool> isConfigured() async {
    return SupabaseService.isInitialized;
  }

  // ─── MAIN: Kirim ke Supabase Storage & Table ─────────────────
  /// Mengirim data pembayaran ke Supabase.
  ///
  /// Mengunggah file bukti ke Storage bucket `payment-proofs/{userId}/...`
  /// dan mencatat record transaksi di tabel `payments`.
  static Future<bool> submitPayment({
    required PaymentRecord record,
    String? proofImagePath,
  }) async {
    try {
      final supaClient = SupabaseService.client;
      final currentUserId = supaClient.auth.currentUser?.id ?? record.userId;
      String? remoteStoragePath;

      // 1. Upload Bukti Transfer ke Supabase Storage jika ada
      if (proofImagePath != null && proofImagePath.isNotEmpty) {
        final file = File(proofImagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final ext = proofImagePath.split('.').last.toLowerCase();
          final mimeType = (ext == 'png') ? 'image/png' : 'image/jpeg';
          final filename = '${record.id}_transfer.$ext';
          remoteStoragePath = '$currentUserId/$filename';

          try {
            await supaClient.storage.from(_storageBucket).uploadBinary(
              remoteStoragePath,
              bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
            debugPrint('✅ Payment proof uploaded to Supabase Storage: $remoteStoragePath');
          } catch (uploadErr) {
            debugPrint('⚠️ Storage upload warning: $uploadErr');
          }
        }
      }

      // 2. Simpan Transaksi ke Tabel payments di Supabase
      try {
        final res = await supaClient.rpc('submit_payment', params: {
          'p_sender_bank': record.senderBank,
          'p_proof_path': remoteStoragePath,
          'p_notes': record.notes,
        });

        debugPrint('✅ Payment RPC response: $res');
      } catch (rpcErr) {
        debugPrint('⚠️ RPC submit_payment failed, fallback direct insert: $rpcErr');
        // Fallback direct insert jika RPC belum match
        await supaClient.from('payments').insert({
          'id': record.id,
          'user_id': currentUserId,
          'user_name': record.userName,
          'user_email': record.userEmail,
          'sender_bank': record.senderBank,
          'amount': record.amount,
          'proof_path': remoteStoragePath,
          'status': 'PENDING',
          'notes': record.notes,
        });
      }

      // 3. Simpan juga ke backup lokal
      final updatedRecord = record.copyWith(
        remoteProofUrl: remoteStoragePath,
        userId: currentUserId,
      );
      await savePaymentLocal(updatedRecord);

      return true;
    } catch (e) {
      debugPrint('❌ Supabase payment submission error: $e');
      // Tetap simpan lokal agar user tidak kehilangan riwayat jika offline
      await savePaymentLocal(record);
      return false;
    }
  }

  // ─── LOCAL & REMOTE STORAGE: Riwayat Pembayaran ───────────────
  /// Menyimpan record pembayaran ke SharedPreferences (offline backup).
  static Future<void> savePaymentLocal(PaymentRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_localPaymentsKey) ?? [];
    existing.add(jsonEncode(record.toJson()));
    await prefs.setStringList(_localPaymentsKey, existing);
  }

  /// Mengambil seluruh riwayat pembayaran pengguna.
  static Future<List<PaymentRecord>> getLocalPayments() async {
    // 1. Coba sync dari Supabase jika online
    try {
      final supaClient = SupabaseService.client;
      final userId = supaClient.auth.currentUser?.id;
      if (userId != null) {
        final rows = await supaClient
            .from('payments')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: true);

        if (rows.isNotEmpty) {
          final serverList = rows.map((r) => PaymentRecord.fromJson(r)).toList();
          return serverList;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Get payments from Supabase error, fallback local: $e');
    }

    // 2. Fallback SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localPaymentsKey) ?? [];
    return raw.map((e) {
      try {
        return PaymentRecord.fromJson(jsonDecode(e));
      } catch (_) {
        return null;
      }
    }).whereType<PaymentRecord>().toList();
  }

  /// Mengambil payment terakhir pengguna (untuk cek status).
  static Future<PaymentRecord?> getLastPayment() async {
    final list = await getLocalPayments();
    if (list.isEmpty) return null;
    return list.last;
  }

  /// Mengecek apakah ada pembayaran pending.
  static Future<bool> hasPendingPayment() async {
    // 1. Coba cek ke server secara real-time
    try {
      final supaClient = SupabaseService.client;
      final userId = supaClient.auth.currentUser?.id;
      if (userId != null) {
        final pending = await supaClient
            .from('payments')
            .select('id')
            .eq('user_id', userId)
            .eq('status', 'PENDING')
            .maybeSingle();

        if (pending != null) return true;
      }
    } catch (_) {}

    // 2. Fallback cek lokal
    final list = await getLocalPayments();
    return list.any((p) => p.status == 'PENDING');
  }
}
