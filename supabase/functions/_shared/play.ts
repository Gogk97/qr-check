// ============================================================================
// Shared helper: Google service account -> Play Developer API
// Dipakai oleh `verify-play-purchase` dan `play-rtdn`.
// ============================================================================

export const PACKAGE_NAME = Deno.env.get("PLAY_PACKAGE_NAME") ?? "com.qrcheck.app.qr_check";
export const PRODUCT_ID = Deno.env.get("PLAY_PRODUCT_ID") ?? "pro_lifetime";

const SA_JSON_RAW = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "";
const ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ─── Encoding helpers ──────────────────────────────────────────────────────
export function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlJson(value: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(value)));
}

// ─── Service account ───────────────────────────────────────────────────────
interface ServiceAccount {
  client_email: string;
  private_key: string;
}

function readServiceAccount(): ServiceAccount {
  if (!SA_JSON_RAW) throw new Error("missing_GOOGLE_SERVICE_ACCOUNT_JSON");
  let raw = SA_JSON_RAW.trim();
  if (!raw.startsWith("{")) {
    // Dukungan nilai base64 (aman untuk secret multi-baris).
    raw = new TextDecoder().decode(Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)));
  }
  const parsed = JSON.parse(raw);
  if (!parsed.client_email || !parsed.private_key) {
    throw new Error("invalid_service_account_json");
  }
  return { client_email: parsed.client_email, private_key: parsed.private_key };
}

let cachedToken: { accessToken: string; expiresAt: number } | null = null;

export async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) {
    return cachedToken.accessToken;
  }

  const sa = readServiceAccount();
  const header = b64urlJson({ alg: "RS256", typ: "JWT" });
  const claims = b64urlJson({
    iss: sa.client_email,
    scope: ANDROID_PUBLISHER_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const signingInput = `${header}.${claims}`;

  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${b64url(new Uint8Array(signature))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`google_token_exchange_failed:${res.status}:${await res.text()}`);
  }
  const payload = await res.json();
  cachedToken = {
    accessToken: payload.access_token,
    expiresAt: now + Number(payload.expires_in ?? 3600),
  };
  return cachedToken.accessToken;
}

// ─── Play Developer API ────────────────────────────────────────────────────
export interface ProductPurchaseV2 {
  productLineItem?: Array<{ productId?: string }>;
  purchaseStateContext?: { purchaseState?: string };
  testPurchaseContext?: { fopType?: string };
  orderId?: string;
  obfuscatedExternalAccountId?: string;
  regionCode?: string;
  purchaseCompletionTime?: string;
  acknowledgementState?: string;
}

export async function fetchProductPurchase(purchaseToken: string): Promise<ProductPurchaseV2> {
  const accessToken = await getAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(PACKAGE_NAME)}/purchases/productsv2/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`play_api_get_failed:${res.status}:${text}`);
  }
  return JSON.parse(text);
}

export async function acknowledgeProduct(productId: string, purchaseToken: string): Promise<boolean> {
  const accessToken = await getAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(PACKAGE_NAME)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (res.ok) return true;
  const body = await res.text();
  // Sudah pernah di-acknowledge -> bukan error.
  if (res.status === 400 && /already/i.test(body)) {
    return true;
  }
  console.error("acknowledge_failed", res.status, body.slice(0, 300));
  return false;
}

export function ownsProduct(purchase: ProductPurchaseV2, productId = PRODUCT_ID): boolean {
  return (purchase.productLineItem ?? []).some((item) => item?.productId === productId);
}
