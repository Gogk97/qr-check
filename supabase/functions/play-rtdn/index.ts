// ============================================================================
// Supabase Edge Function: play-rtdn
// ----------------------------------------------------------------------------
// Penerima Real-time Developer Notifications (RTDN) Google Play via Pub/Sub
// push subscription.
//
// Kenapa penting:
//   * ONE_TIME_PRODUCT_PURCHASED -> acknowledge pembelian walau user tidak
//     pernah membuka app lagi (tanpa ack <= 3 hari, Google auto-refund).
//   * ONE_TIME_PRODUCT_CANCELED / VOIDED_PURCHASE -> cabut PRO (refund,
//     chargeback, pembayaran gagal).
//
// Deploy WAJIB tanpa verifikasi JWT Supabase (Google yang menandatangani):
//   npx supabase functions deploy play-rtdn --no-verify-jwt
//
// Secrets:
//   RTDN_AUDIENCE               -> URL function (audience OIDC token)
//   RTDN_SERVICE_ACCOUNT_EMAIL  -> (opsional) email SA pemanggil Pub/Sub
//   GOOGLE_SERVICE_ACCOUNT_JSON -> service account Play Developer API
// ============================================================================

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  acknowledgeProduct,
  fetchProductPurchase,
  json,
  ownsProduct,
  PACKAGE_NAME,
  PRODUCT_ID,
} from "../_shared/play.ts";
import { verifyGoogleOidc } from "../_shared/oidc.ts";
import {
  classifyNotification,
  decideAction,
  decodeDeveloperNotification,
  type DeveloperNotification,
} from "../_shared/rtdn.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const RTDN_AUDIENCE = Deno.env.get("RTDN_AUDIENCE") ?? "";
const RTDN_SA_EMAIL = Deno.env.get("RTDN_SERVICE_ACCOUNT_EMAIL") ?? "";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ─── OIDC verification (Pub/Sub push auth) ─────────────────────────────────
async function verifyPubSubToken(authHeader: string | null): Promise<void> {
  if (!RTDN_AUDIENCE) {
    // Fail closed: tanpa audience, siapa pun bisa memalsukan notifikasi refund.
    throw new Error("RTDN_AUDIENCE_not_configured");
  }
  if (!authHeader?.toLowerCase().startsWith("bearer ")) {
    throw new Error("missing_oidc_token");
  }
  await verifyGoogleOidc(authHeader.slice(7).trim(), {
    audience: RTDN_AUDIENCE,
    expectedEmail: RTDN_SA_EMAIL || undefined,
  });
}

// ─── Notification handling ─────────────────────────────────────────────────
type SupabaseAdmin = SupabaseClient<any, "public", any>;

async function handlePurchased(
  admin: SupabaseAdmin,
  purchaseToken: string,
  sku: string,
): Promise<string> {
  // 1) Verifikasi otoritatif ke Google (jangan percaya payload Pub/Sub).
  const purchase = await fetchProductPurchase(purchaseToken);
  const state = purchase.purchaseStateContext?.purchaseState;
  if (!ownsProduct(purchase, sku) || state !== "PURCHASED") {
    return `skipped_state_${state ?? "unknown"}`;
  }

  // 2) Acknowledge supaya tidak di-refund otomatis.
  let acknowledged = purchase.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  if (!acknowledged) {
    acknowledged = await acknowledgeProduct(sku, purchaseToken);
  }

  // 3) Kalau token sudah diklaim user (verify-play-purchase), tidak ada lagi
  //    yang perlu dilakukan — RPC grant sudah idempoten.
  const { data: existing } = await admin
    .from("play_purchases")
    .select("user_id")
    .eq("purchase_token", purchaseToken)
    .maybeSingle();

  if (existing?.user_id) {
    return "already_claimed";
  }

  // 4) Auto-fulfill bila akun pembeli bisa dipetakan (obfuscatedAccountId = uid).
  const buyerId = purchase.obfuscatedExternalAccountId ?? "";
  if (UUID_RE.test(buyerId)) {
    const { data: profile } = await admin
      .from("profiles")
      .select("id")
      .eq("id", buyerId)
      .maybeSingle();
    if (profile?.id) {
      const { error } = await admin.rpc("grant_pro_from_play", {
        p_user_id: buyerId,
        p_purchase_token: purchaseToken,
        p_product_id: sku,
        p_order_id: purchase.orderId ?? null,
        p_is_test: Boolean(purchase.testPurchaseContext),
        p_region_code: purchase.regionCode ?? null,
        p_raw: purchase,
      });
      if (!error) return "granted";
      console.error("rtdn_grant_failed", error.message);
    }
  }

  // 5) Belum bisa dipetakan -> simpan agar bisa diklaim lewat restore.
  await admin.rpc("upsert_play_purchase_inbox", {
    p_purchase_token: purchaseToken,
    p_product_id: sku,
    p_order_id: purchase.orderId ?? null,
    p_state: "PURCHASED",
    p_acknowledged: acknowledged,
    p_region_code: purchase.regionCode ?? null,
    p_raw: purchase,
  });
  return "stored_in_inbox";
}

async function handleCanceled(
  admin: SupabaseAdmin,
  purchaseToken: string,
  reason: string,
): Promise<string> {
  await admin.rpc("upsert_play_purchase_inbox", {
    p_purchase_token: purchaseToken,
    p_product_id: PRODUCT_ID,
    p_order_id: null,
    p_state: "CANCELLED",
    p_acknowledged: false,
    p_region_code: null,
    p_raw: { reason },
  });

  const { data, error } = await admin.rpc("revoke_pro_from_play", {
    p_purchase_token: purchaseToken,
    p_reason: reason,
  });
  if (error) {
    console.error("rtdn_revoke_failed", error.message);
    throw new Error("revoke_failed");
  }
  return (data as any)?.success ? "revoked" : "not_found";
}

// ─── Handler ───────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "GET") {
    return json({ ok: true, function: "play-rtdn", package: PACKAGE_NAME });
  }
  if (req.method !== "POST") {
    return json({ success: false, error: "method_not_allowed" }, 405);
  }

  // 1) Autentikasi OIDC dari Pub/Sub.
  try {
    await verifyPubSubToken(req.headers.get("Authorization"));
  } catch (error) {
    console.error("rtdn_auth_failed", String(error));
    return json({ success: false, error: String(error) }, 401);
  }

  try {
    const envelope = await req.json().catch(() => null);
    const rawData: string | undefined = envelope?.message?.data;
    const messageId: string = envelope?.message?.messageId ?? envelope?.message?.message_id ?? "";

    if (!rawData) {
      return json({ success: false, error: "empty_message" }, 200);
    }

    let notification: DeveloperNotification;
    try {
      notification = decodeDeveloperNotification(rawData);
    } catch (decodeError) {
      // Payload rusak tidak akan pernah valid -> ack (200) agar tidak retry selamanya.
      console.error("rtdn_invalid_payload", String(decodeError));
      return json({ success: false, error: "invalid_payload" }, 200);
    }

    // 2) Abaikan notifikasi aplikasi lain (topic bisa dipakai bersama).
    if (notification.packageName && notification.packageName !== PACKAGE_NAME) {
      return json({ success: true, ignored: "package_mismatch" });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const eventType = classifyNotification(notification);

    // 3) Idempotensi: Pub/Sub bisa mengirim ulang pesan yang sama.
    //    PENTING: event hanya dicatat SETELAH berhasil diproses, supaya pesan
    //    yang gagal (Play API down) tetap dikirim ulang oleh Pub/Sub.
    const eventPurchaseToken =
      notification.oneTimeProductNotification?.purchaseToken ??
      notification.voidedPurchaseNotification?.purchaseToken ??
      null;

    if (messageId) {
      const { data: seen } = await admin
        .from("play_rtdn_events")
        .select("message_id")
        .eq("message_id", messageId)
        .maybeSingle();
      if (seen?.message_id) {
        return json({ success: true, duplicate: true, messageId });
      }
    }

    // 4) Routing (keputusan murni, lihat _shared/rtdn.ts).
    let result = "noop";
    const action = decideAction(notification, PRODUCT_ID);

    switch (action.kind) {
      case "test":
        result = "test_ok";
        break;
      case "purchase":
        result = await handlePurchased(admin, action.purchaseToken, action.sku);
        break;
      case "cancel":
      case "void":
        result = await handleCanceled(admin, action.purchaseToken, action.reason);
        break;
      case "pending_refund_review":
        // Chargeback menunggu review: catat saja, keputusan tetap manual
        // (ReviewRefund API butuh bukti pemakaian dari tim bisnis).
        console.warn("pending_refund_review", action.orderId);
        result = "logged_pending_review";
        break;
      case "ignore":
        result = `ignored_${action.reason}`;
        break;
    }

    // 5) Catat event setelah pemrosesan sukses (audit + dedupe pesan berikutnya).
    if (messageId) {
      const { error: recordError } = await admin.rpc("record_play_rtdn_event", {
        p_message_id: messageId,
        p_event_type: eventType,
        p_purchase_token: eventPurchaseToken,
        p_package_name: notification.packageName ?? null,
        p_payload: notification,
      });
      if (recordError) {
        console.error("rtdn_record_failed", recordError.message);
      }
    }

    return json({ success: true, eventType, result, messageId });
  } catch (error) {
    // Error transien (Play API down, jaringan) -> 500 supaya Pub/Sub retry.
    console.error("rtdn_handler_failed", String(error));
    return json({ success: false, error: String(error) }, 500);
  }
});
