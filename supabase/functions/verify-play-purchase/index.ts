// ============================================================================
// Supabase Edge Function: verify-play-purchase
// ----------------------------------------------------------------------------
// Tugas:
//   1. Autentikasi user (JWT Supabase dari header Authorization).
//   2. Verifikasi purchase token ke Google Play Developer API (productsv2).
//   3. Pastikan produk = one-time PRO dan status PURCHASED.
//   4. Acknowledge pembelian (wajib <= 3 hari, kalau tidak otomatis di-refund).
//   5. Beri hak PRO lewat RPC `grant_pro_from_play` (service_role only).
//
// Secrets yang dibutuhkan (supabase secrets set ...):
//   GOOGLE_SERVICE_ACCOUNT_JSON  -> isi JSON service account (atau base64-nya)
//   PLAY_PACKAGE_NAME            -> com.qrcheck.app.qr_check
//   PLAY_PRODUCT_ID              -> pro_lifetime
//
// Helper Google/Play API dipakai bersama dengan function `play-rtdn`
// (lihat supabase/functions/_shared/play.ts).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  acknowledgeProduct,
  corsHeaders,
  fetchProductPurchase,
  json,
  ownsProduct,
  PACKAGE_NAME,
  PRODUCT_ID,
} from "../_shared/play.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method === "GET") {
    return json({ ok: true, function: "verify-play-purchase", package: PACKAGE_NAME });
  }
  if (req.method !== "POST") {
    return json({ success: false, error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ success: false, error: "missing_authorization" }, 401);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const jwt = authHeader.slice(7).trim();
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData?.user) {
      return json({ success: false, error: "invalid_session" }, 401);
    }
    const userId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const purchaseToken: string | undefined = body?.purchaseToken;
    const productId: string = body?.productId ?? PRODUCT_ID;

    if (!purchaseToken || purchaseToken.length < 10) {
      return json({ success: false, error: "missing_purchase_token" }, 400);
    }
    if (productId !== PRODUCT_ID) {
      return json({ success: false, error: "unknown_product" }, 400);
    }

    // 1) Verifikasi ke Google Play (jangan percaya data dari client).
    const purchase = await fetchProductPurchase(purchaseToken);
    const state = purchase.purchaseStateContext?.purchaseState;

    if (!ownsProduct(purchase, productId)) {
      return json({ success: false, error: "product_mismatch" }, 409);
    }
    if (state !== "PURCHASED") {
      // PENDING / CANCELLED -> jangan beri hak PRO.
      return json({ success: false, error: "purchase_not_completed", state }, 409);
    }

    // 2) Anti replay: token yang dibuat untuk akun lain tidak boleh diklaim.
    const obfuscated = purchase.obfuscatedExternalAccountId;
    if (obfuscated && obfuscated !== userId) {
      return json({ success: false, error: "account_mismatch" }, 409);
    }

    // 3) Acknowledge (wajib, kalau tidak pembelian di-refund otomatis).
    if (purchase.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
      await acknowledgeProduct(productId, purchaseToken);
    }

    // 4) Grant PRO (service_role only).
    const { data: grant, error: grantError } = await admin.rpc("grant_pro_from_play", {
      p_user_id: userId,
      p_purchase_token: purchaseToken,
      p_product_id: productId,
      p_order_id: purchase.orderId ?? null,
      p_is_test: Boolean(purchase.testPurchaseContext),
      p_region_code: purchase.regionCode ?? null,
      p_raw: purchase,
    });

    if (grantError) {
      console.error("grant_rpc_failed", grantError.message);
      const claimed = grantError.message.includes("purchase_token_already_claimed");
      return json(
        { success: false, error: claimed ? "purchase_token_already_claimed" : "grant_failed" },
        409,
      );
    }

    return json({
      success: true,
      isPro: true,
      productId,
      orderId: purchase.orderId ?? null,
      grant,
    });
  } catch (error) {
    console.error("verify_play_purchase_error", String(error));
    return json({ success: false, error: String(error) }, 500);
  }
});
