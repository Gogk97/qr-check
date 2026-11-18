// ============================================================================
// Test: parsing & klasifikasi notifikasi RTDN
// Jalankan: npx deno test --allow-env supabase/functions/tests/rtdn_test.ts
// ============================================================================

import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyNotification,
  decideAction,
  decodeDeveloperNotification,
  shouldRevoke,
} from "../_shared/rtdn.ts";

const PKG = "com.qrcheck.app.qr_check";

function encode(payload: unknown): string {
  return btoa(JSON.stringify(payload));
}

Deno.test("decode payload one-time purchase", () => {
  const raw = encode({
    version: "1.0",
    packageName: PKG,
    eventTimeMillis: "1503349566168",
    oneTimeProductNotification: {
      version: "1.0",
      notificationType: 1,
      purchaseToken: "TOKEN_1234567890",
      sku: "pro_lifetime",
    },
  });

  const notification = decodeDeveloperNotification(raw);
  assertEquals(notification.packageName, PKG);
  assertEquals(notification.oneTimeProductNotification?.purchaseToken, "TOKEN_1234567890");
  assertEquals(notification.oneTimeProductNotification?.sku, "pro_lifetime");
  assertEquals(classifyNotification(notification), "ONE_TIME_PRODUCT_PURCHASED");
});

Deno.test("klasifikasi one-time canceled", () => {
  const notification = decodeDeveloperNotification(
    encode({
      packageName: PKG,
      oneTimeProductNotification: { notificationType: 2, purchaseToken: "T", sku: "pro_lifetime" },
    }),
  );
  assertEquals(classifyNotification(notification), "ONE_TIME_PRODUCT_CANCELED");
  assertEquals(shouldRevoke("ONE_TIME_PRODUCT_CANCELED"), true);
});

Deno.test("klasifikasi voided purchase (refund)", () => {
  const notification = decodeDeveloperNotification(
    encode({
      packageName: PKG,
      voidedPurchaseNotification: {
        purchaseToken: "T",
        orderId: "GPA.1234-5678-9012-34567",
        productType: 2,
        refundType: 1,
      },
    }),
  );
  assertEquals(classifyNotification(notification), "VOIDED_PURCHASE");
  assertEquals(shouldRevoke("VOIDED_PURCHASE"), true);
});

Deno.test("klasifikasi test notification", () => {
  const notification = decodeDeveloperNotification(
    encode({ packageName: PKG, testNotification: { version: "1.0" } }),
  );
  assertEquals(classifyNotification(notification), "TEST");
  assertEquals(shouldRevoke("TEST"), false);
});

Deno.test("klasifikasi pending refund review", () => {
  const notification = decodeDeveloperNotification(
    encode({
      packageName: PKG,
      pendingRefundReviewNotification: {
        pendingRefundToken: "tok",
        orderId: "GPA.1",
        refundReason: 7,
      },
    }),
  );
  assertEquals(classifyNotification(notification), "PENDING_REFUND_REVIEW");
  assertEquals(shouldRevoke("PENDING_REFUND_REVIEW"), false);
});

Deno.test("notifikasi tidak dikenal -> UNKNOWN dan tidak mencabut", () => {
  const notification = decodeDeveloperNotification(encode({ packageName: PKG }));
  assertEquals(classifyNotification(notification), "UNKNOWN");
  assertEquals(shouldRevoke("UNKNOWN"), false);

  const weirdType = decodeDeveloperNotification(
    encode({ packageName: PKG, oneTimeProductNotification: { notificationType: 99 } }),
  );
  assertEquals(classifyNotification(weirdType), "UNKNOWN");
});

Deno.test("purchase event tidak mencabut PRO", () => {
  assertEquals(shouldRevoke("ONE_TIME_PRODUCT_PURCHASED"), false);
});

Deno.test("payload rusak ditolak", () => {
  assertThrows(() => decodeDeveloperNotification("bukan-base64-json"), Error);
});

// ─── decideAction ──────────────────────────────────────────────────────────
const DEFAULT_SKU = "pro_lifetime";

Deno.test("decideAction: purchase memakai sku dari payload", () => {
  const action = decideAction(
    {
      packageName: PKG,
      oneTimeProductNotification: {
        notificationType: 1,
        purchaseToken: "TOKEN_A",
        sku: "pro_lifetime",
      },
    },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "purchase", purchaseToken: "TOKEN_A", sku: "pro_lifetime" });
});

Deno.test("decideAction: purchase tanpa sku memakai default", () => {
  const action = decideAction(
    { oneTimeProductNotification: { notificationType: 1, purchaseToken: "TOKEN_B" } },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "purchase", purchaseToken: "TOKEN_B", sku: DEFAULT_SKU });
});

Deno.test("decideAction: cancel", () => {
  const action = decideAction(
    { oneTimeProductNotification: { notificationType: 2, purchaseToken: "TOKEN_C" } },
    DEFAULT_SKU,
  );
  assertEquals(action, {
    kind: "cancel",
    purchaseToken: "TOKEN_C",
    reason: "one_time_product_canceled",
  });
});

Deno.test("decideAction: voided one-time purchase", () => {
  const action = decideAction(
    {
      voidedPurchaseNotification: {
        purchaseToken: "TOKEN_D",
        orderId: "GPA.1",
        productType: 2,
        refundType: 1,
      },
    },
    DEFAULT_SKU,
  );
  assertEquals(action, {
    kind: "void",
    purchaseToken: "TOKEN_D",
    reason: "voided_purchase_refund_1",
  });
});

Deno.test("decideAction: voided subscription diabaikan", () => {
  const action = decideAction(
    {
      voidedPurchaseNotification: {
        purchaseToken: "TOKEN_E",
        productType: 1,
        refundType: 1,
      },
    },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "ignore", reason: "subscription_not_used" });
});

Deno.test("decideAction: token kosong diabaikan", () => {
  const action = decideAction(
    { oneTimeProductNotification: { notificationType: 1 } },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "ignore", reason: "missing_token" });
});

Deno.test("decideAction: tipe tidak dikenal diabaikan", () => {
  const action = decideAction(
    { oneTimeProductNotification: { notificationType: 99, purchaseToken: "TOKEN_F" } },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "ignore", reason: "unhandled_type_99" });
});

Deno.test("decideAction: pending refund review diteruskan", () => {
  const action = decideAction(
    { pendingRefundReviewNotification: { orderId: "GPA.2", refundReason: 7 } },
    DEFAULT_SKU,
  );
  assertEquals(action, { kind: "pending_refund_review", orderId: "GPA.2" });
});

Deno.test("decideAction: test notification", () => {
  const action = decideAction({ testNotification: { version: "1.0" } }, DEFAULT_SKU);
  assertEquals(action, { kind: "test" });
});
