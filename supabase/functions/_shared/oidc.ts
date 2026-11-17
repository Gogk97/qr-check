// ============================================================================
// Verifikasi OIDC token dari Google Pub/Sub push subscription.
//
// Pub/Sub menandatangani JWT (RS256) dan mengirimnya di header Authorization.
// Validasi: signature (JWKS Google), issuer, audience, expiry, email SA.
// ============================================================================

const DEFAULT_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs";

interface CertCacheEntry {
  keys: Record<string, CryptoKey>;
  expiresAt: number;
}

const certCache = new Map<string, CertCacheEntry>();

/** Hanya untuk test. */
export function __resetOidcCache(): void {
  certCache.clear();
}

export interface OidcVerifyOptions {
  /** Audience yang diharapkan (URL function / push endpoint). */
  audience: string;
  /** Email service account pemanggil (opsional, tapi disarankan). */
  expectedEmail?: string;
  /** Override endpoint JWKS (dipakai saat test). */
  certsUrl?: string;
  /** Toleransi clock skew (detik). */
  clockSkewSeconds?: number;
}

function decodeSegment(segment: string): Record<string, any> {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

function b64urlToBytes(segment: string): Uint8Array {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function getKey(kid: string, certsUrl: string): Promise<CryptoKey> {
  const now = Date.now();
  const cached = certCache.get(certsUrl);
  if (!cached || cached.expiresAt < now) {
    const res = await fetch(certsUrl);
    if (!res.ok) throw new Error(`jwks_fetch_failed:${res.status}`);
    const jwks = await res.json();
    const keys: Record<string, CryptoKey> = {};
    for (const jwk of jwks.keys ?? []) {
      if (!jwk?.kid || jwk.kty !== "RSA") continue;
      keys[jwk.kid] = await crypto.subtle.importKey(
        "jwk",
        { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"],
      );
    }
    certCache.set(certsUrl, { keys, expiresAt: now + 3600_000 });
  }
  const key = certCache.get(certsUrl)!.keys[kid];
  if (!key) throw new Error("unknown_kid");
  return key;
}

export interface OidcClaims {
  email?: string;
  sub?: string;
  aud?: string;
  exp?: number;
  iss?: string;
}

export async function verifyGoogleOidc(
  token: string,
  options: OidcVerifyOptions,
): Promise<OidcClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed_jwt");

  let header: Record<string, any>;
  let claims: OidcClaims;
  try {
    header = decodeSegment(parts[0]);
    claims = decodeSegment(parts[1]) as OidcClaims;
  } catch {
    throw new Error("malformed_jwt");
  }

  if (header.alg !== "RS256") throw new Error("unexpected_alg");

  const key = await getKey(String(header.kid ?? ""), options.certsUrl ?? DEFAULT_CERTS_URL);
  const signatureBytes = b64urlToBytes(parts[2]);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signatureBytes.buffer as ArrayBuffer,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) throw new Error("invalid_signature");

  const now = Math.floor(Date.now() / 1000);
  const skew = options.clockSkewSeconds ?? 60;
  if (typeof claims.exp !== "number" || claims.exp < now - skew) {
    throw new Error("token_expired");
  }
  if (claims.iss !== "https://accounts.google.com" && claims.iss !== "accounts.google.com") {
    throw new Error("invalid_issuer");
  }
  if (claims.aud !== options.audience) throw new Error("invalid_audience");
  if ((claims as any).email_verified === false) throw new Error("email_not_verified");
  if (options.expectedEmail && claims.email !== options.expectedEmail) {
    throw new Error("unexpected_service_account");
  }

  return claims;
}
