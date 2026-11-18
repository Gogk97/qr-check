// ============================================================================
// Test: verifikasi OIDC token Pub/Sub (security-critical path)
// Jalankan: npx deno test --allow-net --allow-env supabase/functions/tests/oidc_test.ts
// ============================================================================

import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { __resetOidcCache, verifyGoogleOidc } from "../_shared/oidc.ts";

const KID = "test-kid";
const AUDIENCE = "https://example.supabase.co/functions/v1/play-rtdn";
const SA_EMAIL = "pubsub-push@example.iam.gserviceaccount.com";

function b64urlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlJson(value: unknown): string {
  return b64urlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

const keyPair = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);

const publicJwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);

// Server JWKS lokal (meniru https://www.googleapis.com/oauth2/v3/certs).
const jwksServer = Deno.serve({ port: 0, hostname: "127.0.0.1" }, () =>
  new Response(
    JSON.stringify({
      keys: [{ ...publicJwk, kid: KID, alg: "RS256", use: "sig" }],
    }),
    { headers: { "content-type": "application/json" } },
  )
);
const certsUrl = `http://127.0.0.1:${(jwksServer.addr as Deno.NetAddr).port}/certs`;

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

function baseClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const now = nowSeconds();
  return {
    aud: AUDIENCE,
    azp: "113774264463038321964",
    email: SA_EMAIL,
    email_verified: true,
    sub: "113774264463038321964",
    iat: now,
    exp: now + 3600,
    iss: "https://accounts.google.com",
    ...overrides,
  };
}

async function mintToken(
  claims: Record<string, unknown>,
  options: { kid?: string; tamper?: boolean } = {},
): Promise<string> {
  const header = b64urlJson({ alg: "RS256", kid: options.kid ?? KID, typ: "JWT" });
  const payload = b64urlJson(claims);
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    keyPair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  let sig = b64urlBytes(new Uint8Array(signature));
  if (options.tamper) {
    sig = (sig[0] === "A" ? "B" : "A") + sig.slice(1);
  }
  return `${signingInput}.${sig}`;
}

Deno.test("token valid diterima", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims());
  const claims = await verifyGoogleOidc(token, {
    audience: AUDIENCE,
    expectedEmail: SA_EMAIL,
    certsUrl,
  });
  assertEquals(claims.email, SA_EMAIL);
});

Deno.test("audience salah ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims({ aud: "https://attacker.example.com" }));
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "invalid_audience",
  );
});

Deno.test("token kedaluwarsa ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims({ exp: nowSeconds() - 600 }));
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "token_expired",
  );
});

Deno.test("signature yang dimodifikasi ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims(), { tamper: true });
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "invalid_signature",
  );
});

Deno.test("issuer tidak dikenal ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims({ iss: "https://evil.example.com" }));
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "invalid_issuer",
  );
});

Deno.test("service account berbeda ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims({ email: "other@example.iam.gserviceaccount.com" }));
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, expectedEmail: SA_EMAIL, certsUrl }),
    Error,
    "unexpected_service_account",
  );
});

Deno.test("kid tidak dikenal ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims(), { kid: "unknown-kid" });
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "unknown_kid",
  );
});

Deno.test("email_verified=false ditolak", async () => {
  __resetOidcCache();
  const token = await mintToken(baseClaims({ email_verified: false }));
  await assertRejects(
    () => verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl }),
    Error,
    "email_not_verified",
  );
});

Deno.test("token bukan JWT ditolak", async () => {
  __resetOidcCache();
  await assertRejects(
    () => verifyGoogleOidc("not-a-jwt", { audience: AUDIENCE, certsUrl }),
    Error,
    "malformed_jwt",
  );
});

Deno.test("token 3 segmen tapi bukan base64 JSON ditolak sebagai malformed", async () => {
  __resetOidcCache();
  await assertRejects(
    () => verifyGoogleOidc("abc.def.ghi", { audience: AUDIENCE, certsUrl }),
    Error,
    "malformed_jwt",
  );
});

Deno.test("cache JWKS dipakai ulang (tidak fetch berkali-kali)", async () => {
  __resetOidcCache();
  let hits = 0;
  const counting = Deno.serve({ port: 0, hostname: "127.0.0.1" }, () => {
    hits += 1;
    return new Response(JSON.stringify({ keys: [{ ...publicJwk, kid: KID, alg: "RS256" }] }), {
      headers: { "content-type": "application/json" },
    });
  });
  const url = `http://127.0.0.1:${(counting.addr as Deno.NetAddr).port}/certs`;
  try {
    for (let i = 0; i < 3; i++) {
      const token = await mintToken(baseClaims());
      await verifyGoogleOidc(token, { audience: AUDIENCE, certsUrl: url });
    }
    assert(hits === 1, `JWKS harus di-cache, tapi di-fetch ${hits}x`);
  } finally {
    await counting.shutdown();
  }
});

// Cleanup
Deno.test("teardown", async () => {
  __resetOidcCache();
  await jwksServer.shutdown();
});
