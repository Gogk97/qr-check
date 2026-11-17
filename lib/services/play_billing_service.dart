import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import '../utils/app_log.dart';

/// Produk PRO lifetime (one-time / non-consumable) yang dibuat di Play Console.
/// Product ID ini WAJIB sama persis dengan yang ada di Play Console.
const String kProLifetimeProductId = 'pro_lifetime';

/// Harga fallback jika Play Billing belum siap (mis. offline / bukan Android).
const String kProFallbackPrice = 'Rp 15.000';

enum PlayPurchaseStatus {
  purchased,
  pending,
  canceled,
  alreadyOwned,
  unavailable,
  failed,
}

class PlayProduct {
  final String productId;
  final String title;
  final String name;
  final String description;
  final String? formattedPrice;
  final int? priceAmountMicros;
  final String? currencyCode;

  const PlayProduct({
    required this.productId,
    required this.title,
    required this.name,
    required this.description,
    this.formattedPrice,
    this.priceAmountMicros,
    this.currencyCode,
  });

  static PlayProduct? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<dynamic, dynamic>();
    final id = map['productId'] as String?;
    if (id == null) return null;
    return PlayProduct(
      productId: id,
      title: (map['title'] as String?) ?? 'PRO Lifetime',
      name: (map['name'] as String?) ?? 'PRO Lifetime',
      description: (map['description'] as String?) ?? '',
      formattedPrice: map['formattedPrice'] as String?,
      priceAmountMicros: (map['priceAmountMicros'] as num?)?.toInt(),
      currencyCode: map['currencyCode'] as String?,
    );
  }
}

class PlayPurchase {
  final String purchaseToken;
  final String? orderId;
  final List<String> productIds;
  final String state;
  final bool acknowledged;
  final int quantity;
  final int purchaseTimeMillis;

  const PlayPurchase({
    required this.purchaseToken,
    required this.orderId,
    required this.productIds,
    required this.state,
    required this.acknowledged,
    required this.quantity,
    required this.purchaseTimeMillis,
  });

  bool get isPurchased => state == 'PURCHASED';
  bool get isPending => state == 'PENDING';

  static PlayPurchase? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<dynamic, dynamic>();
    final token = map['purchaseToken'] as String?;
    if (token == null || token.isEmpty) return null;
    return PlayPurchase(
      purchaseToken: token,
      orderId: map['orderId'] as String?,
      productIds: (map['productIds'] as List?)?.whereType<String>().toList() ?? const [],
      state: (map['purchaseState'] as String?) ?? 'UNSPECIFIED',
      acknowledged: map['acknowledged'] == true,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      purchaseTimeMillis: (map['purchaseTime'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlayPurchaseEvent {
  final int code;
  final String message;
  final List<PlayPurchase> purchases;

  const PlayPurchaseEvent({
    required this.code,
    required this.message,
    required this.purchases,
  });
}

class PlayPurchaseResult {
  final PlayPurchaseStatus status;
  final PlayPurchase? purchase;
  final String? message;

  const PlayPurchaseResult(this.status, {this.purchase, this.message});
}

/// Wrapper Dart untuk native bridge Google Play Billing (MethodChannel).
///
/// Alur aman (server-authoritative):
///   Play Billing -> purchaseToken -> Edge Function `verify-play-purchase`
///   -> Play Developer API (validasi + acknowledge) -> RPC grant PRO di Supabase.
class PlayBillingService {
  PlayBillingService._();

  static const MethodChannel _channel = MethodChannel('com.qrcheck.app/billing');
  static const String _pendingTokensKey = 'pending_play_purchase_tokens_v1';

  static final StreamController<PlayPurchaseEvent> _events =
      StreamController<PlayPurchaseEvent>.broadcast();
  static bool _bound = false;
  static bool _connected = false;

  static Stream<PlayPurchaseEvent> get events => _events.stream;

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _bindChannel() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onPurchasesUpdated') return null;
      final args = (call.arguments as Map?)?.cast<dynamic, dynamic>() ?? const {};
      final purchases = (args['purchases'] as List?)
              ?.map(PlayPurchase.fromMap)
              .whereType<PlayPurchase>()
              .toList() ??
          const <PlayPurchase>[];
      _events.add(
        PlayPurchaseEvent(
          code: (args['code'] as num?)?.toInt() ?? -1,
          message: (args['message'] as String?) ?? '',
          purchases: purchases,
        ),
      );
      return null;
    });
  }

  /// Cek apakah Play Store tersedia di perangkat.
  static Future<bool> isAvailable() async {
    if (!isSupportedPlatform) return false;
    _bindChannel();
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException catch (e) {
      AppLog.d('⚠️ PlayBilling isAvailable error: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Membuka koneksi ke Play Billing.
  static Future<bool> initialize() async {
    if (!isSupportedPlatform) return false;
    _bindChannel();
    if (_connected) return true;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('init');
      _connected = res?['connected'] == true;
      if (!_connected) {
        AppLog.d('⚠️ PlayBilling init failed: ${res?['code']} ${res?['message']}');
      }
      return _connected;
    } on PlatformException catch (e) {
      AppLog.d('⚠️ PlayBilling init exception: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ambil detail produk (harga terformat sesuai mata uang akun Play user).
  static Future<PlayProduct?> loadProduct({String productId = kProLifetimeProductId}) async {
    if (!isSupportedPlatform) return null;
    if (!await initialize()) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'queryProduct',
        {'productId': productId},
      );
      final product = PlayProduct.fromMap(res?['product']);
      if (product == null) {
        AppLog.d('⚠️ PlayBilling product not found (${res?['code']}): ${res?['message']}');
      }
      return product;
    } on PlatformException catch (e) {
      AppLog.d('⚠️ PlayBilling queryProduct error: ${e.message}');
      return null;
    }
  }

  /// Daftar pembelian yang masih dimiliki akun Play di perangkat ini.
  static Future<List<PlayPurchase>> ownedPurchases() async {
    if (!isSupportedPlatform) return const [];
    if (!await initialize()) return const [];
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('queryPurchases');
      return (res?['purchases'] as List?)
              ?.map(PlayPurchase.fromMap)
              .whereType<PlayPurchase>()
              .toList() ??
          const [];
    } on PlatformException catch (e) {
      AppLog.d('⚠️ PlayBilling queryPurchases error: ${e.message}');
      return const [];
    }
  }

  /// Jalankan billing flow dan tunggu hasilnya.
  static Future<PlayPurchaseResult> purchase({
    String productId = kProLifetimeProductId,
    String? obfuscatedAccountId,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!isSupportedPlatform) {
      return const PlayPurchaseResult(
        PlayPurchaseStatus.unavailable,
        message: 'Google Play Billing hanya tersedia di Android.',
      );
    }
    if (!await initialize()) {
      return const PlayPurchaseResult(
        PlayPurchaseStatus.unavailable,
        message: 'Google Play tidak tersedia di perangkat ini.',
      );
    }

    final completer = Completer<PlayPurchaseResult>();
    StreamSubscription<PlayPurchaseEvent>? sub;

    void finish(PlayPurchaseResult result) {
      if (!completer.isCompleted) completer.complete(result);
      sub?.cancel();
    }

    sub = _events.stream.listen((event) {
      final purchase = event.purchases
          .where((p) => p.productIds.isEmpty || p.productIds.contains(productId))
          .firstOrNull;
      if (purchase != null && purchase.isPurchased) {
        finish(PlayPurchaseResult(PlayPurchaseStatus.purchased, purchase: purchase));
      } else if (purchase != null && purchase.isPending) {
        finish(PlayPurchaseResult(PlayPurchaseStatus.pending, purchase: purchase));
      } else if (event.code == 1) {
        finish(const PlayPurchaseResult(PlayPurchaseStatus.canceled, message: 'Dibatalkan user.'));
      } else if (event.code == 7) {
        finish(const PlayPurchaseResult(PlayPurchaseStatus.alreadyOwned));
      } else if (event.code != 0 && event.purchases.isEmpty) {
        finish(PlayPurchaseResult(
          PlayPurchaseStatus.failed,
          message: event.message.isEmpty ? 'Pembelian gagal (code ${event.code}).' : event.message,
        ));
      }
    });

    try {
      final launch = await _channel.invokeMapMethod<String, dynamic>('launchPurchase', {
        'productId': productId,
        'obfuscatedAccountId': obfuscatedAccountId,
      });
      if (launch?['launched'] != true) {
        finish(PlayPurchaseResult(
          PlayPurchaseStatus.failed,
          message: '${launch?['message'] ?? 'Billing flow gagal dibuka.'} (code ${launch?['code']})',
        ));
      }
    } on PlatformException catch (e) {
      finish(PlayPurchaseResult(PlayPurchaseStatus.failed, message: e.message));
    } on MissingPluginException {
      finish(const PlayPurchaseResult(
        PlayPurchaseStatus.unavailable,
        message: 'Native billing bridge tidak terpasang.',
      ));
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub?.cancel();
        return const PlayPurchaseResult(
          PlayPurchaseStatus.pending,
          message: 'Menunggu konfirmasi pembayaran dari Google Play.',
        );
      },
    );
  }

  /// Verifikasi purchase token ke server (Edge Function) lalu server memberi hak PRO.
  static Future<bool> verifyOnServer(PlayPurchase purchase) async {
    if (!SupabaseService.isAuthenticated) {
      AppLog.d('⚠️ verifyOnServer: user belum login, token disimpan untuk retry.');
      await _rememberPendingToken(purchase.purchaseToken);
      return false;
    }
    try {
      final res = await SupabaseService.client.functions.invoke(
        'verify-play-purchase',
        body: {
          'purchaseToken': purchase.purchaseToken,
          'productId': purchase.productIds.isNotEmpty ? purchase.productIds.first : kProLifetimeProductId,
          'orderId': purchase.orderId,
        },
      );
      final data = res.data;
      final ok = data is Map && data['success'] == true;
      if (ok) {
        await _forgetPendingToken(purchase.purchaseToken);
      } else {
        await _rememberPendingToken(purchase.purchaseToken);
      }
      return ok;
    } catch (e) {
      AppLog.d('⚠️ verifyOnServer error: $e');
      await _rememberPendingToken(purchase.purchaseToken);
      return false;
    }
  }

  /// Sinkronisasi pembelian yang sudah dimiliki (restore purchase / reinstall / ganti device).
  static Future<bool> syncOwnedPurchases({String productId = kProLifetimeProductId}) async {
    if (!isSupportedPlatform) return false;
    final owned = await ownedPurchases();
    final relevant = owned.where(
      (p) => p.isPurchased && (p.productIds.isEmpty || p.productIds.contains(productId)),
    );
    var granted = false;
    for (final purchase in relevant) {
      if (await verifyOnServer(purchase)) granted = true;
    }
    return granted;
  }

  /// Coba ulang token yang belum berhasil diverifikasi (offline / edge function down).
  static Future<bool> retryPendingVerifications() async {
    if (!isSupportedPlatform) return false;
    final prefs = await SharedPreferences.getInstance();
    final tokens = prefs.getStringList(_pendingTokensKey) ?? const <String>[];
    if (tokens.isEmpty) return false;
    var granted = false;
    for (final token in tokens) {
      final purchase = PlayPurchase(
        purchaseToken: token,
        orderId: null,
        productIds: const [kProLifetimeProductId],
        state: 'PURCHASED',
        acknowledged: false,
        quantity: 1,
        purchaseTimeMillis: 0,
      );
      if (await verifyOnServer(purchase)) {
        granted = true;
      }
    }
    return granted;
  }

  static Future<void> _rememberPendingToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = prefs.getStringList(_pendingTokensKey) ?? <String>[];
    if (!tokens.contains(token)) {
      tokens.add(token);
      await prefs.setStringList(_pendingTokensKey, tokens);
    }
  }

  static Future<void> _forgetPendingToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = prefs.getStringList(_pendingTokensKey) ?? <String>[];
    if (tokens.remove(token)) {
      await prefs.setStringList(_pendingTokensKey, tokens);
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
