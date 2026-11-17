// ============================================================================
// Parsing & klasifikasi notifikasi RTDN Google Play (pure functions, mudah dites).
// Referensi: https://developer.android.com/google/play/billing/rtdn-reference
// ============================================================================

export interface DeveloperNotification {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  oneTimeProductNotification?: {
    version?: string;
    notificationType?: number; // 1 = PURCHASED, 2 = CANCELED
    purchaseToken?: string;
    sku?: string;
  };
  voidedPurchaseNotification?: {
    purchaseToken?: string;
    orderId?: string;
    productType?: number; // 1 = subscription, 2 = one-time
    refundType?: number; // 1 = full, 2 = partial (quantity-based)
  };
  pendingRefundReviewNotification?: {
    version?: string;
    pendingRefundToken?: string;
    orderId?: string;
    refundReason?: number;
  };
  testNotification?: { version?: string };
}

export type RtdnEventType =
  | "TEST"
  | "ONE_TIME_PRODUCT_PURCHASED"
  | "ONE_TIME_PRODUCT_CANCELED"
  | "VOIDED_PURCHASE"
  | "PENDING_REFUND_REVIEW"
  | "UNKNOWN";

/** Decode field `message.data` (base64) dari envelope Pub/Sub. */
export function decodeDeveloperNotification(base64Data: string): DeveloperNotification {
  const normalized = base64Data.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  const parsed = JSON.parse(new TextDecoder().decode(bytes));
  if (!parsed || typeof parsed !== "object") {
    throw new Error("invalid_notification_payload");
  }
  return parsed as DeveloperNotification;
}

export function classifyNotification(notification: DeveloperNotification): RtdnEventType {
  if (notification.testNotification) return "TEST";

  const oneTime = notification.oneTimeProductNotification;
  if (oneTime) {
    if (oneTime.notificationType === 1) return "ONE_TIME_PRODUCT_PURCHASED";
    if (oneTime.notificationType === 2) return "ONE_TIME_PRODUCT_CANCELED";
    return "UNKNOWN";
  }

  if (notification.voidedPurchaseNotification) return "VOIDED_PURCHASE";
  if (notification.pendingRefundReviewNotification) return "PENDING_REFUND_REVIEW";
  return "UNKNOWN";
}

/** Apakah event ini harus mencabut hak PRO? */
export function shouldRevoke(eventType: RtdnEventType): boolean {
  return eventType === "ONE_TIME_PRODUCT_CANCELED" || eventType === "VOIDED_PURCHASE";
}

export type RtdnAction =
  | { kind: "test" }
  | { kind: "purchase"; purchaseToken: string; sku: string }
  | { kind: "cancel"; purchaseToken: string; reason: string }
  | { kind: "void"; purchaseToken: string; reason: string }
  | { kind: "pending_refund_review"; orderId: string | null }
  | { kind: "ignore"; reason: string };

/**
 * Tentukan aksi yang harus dijalankan untuk sebuah notifikasi.
 * Pure function — tidak menyentuh jaringan/DB, sehingga mudah dites.
 */
export function decideAction(
  notification: DeveloperNotification,
  defaultSku: string,
): RtdnAction {
  if (notification.testNotification) return { kind: "test" };

  const oneTime = notification.oneTimeProductNotification;
  if (oneTime) {
    if (!oneTime.purchaseToken) return { kind: "ignore", reason: "missing_token" };
    if (oneTime.notificationType === 1) {
      return {
        kind: "purchase",
        purchaseToken: oneTime.purchaseToken,
        sku: oneTime.sku ?? defaultSku,
      };
    }
    if (oneTime.notificationType === 2) {
      return {
        kind: "cancel",
        purchaseToken: oneTime.purchaseToken,
        reason: "one_time_product_canceled",
      };
    }
    return { kind: "ignore", reason: `unhandled_type_${oneTime.notificationType}` };
  }

  const voided = notification.voidedPurchaseNotification;
  if (voided) {
    if (!voided.purchaseToken) return { kind: "ignore", reason: "missing_token" };
    if (voided.productType === 1) {
      // Aplikasi ini tidak menjual subscription.
      return { kind: "ignore", reason: "subscription_not_used" };
    }
    return {
      kind: "void",
      purchaseToken: voided.purchaseToken,
      reason: `voided_purchase_refund_${voided.refundType ?? "unknown"}`,
    };
  }

  const pendingRefund = notification.pendingRefundReviewNotification;
  if (pendingRefund) {
    return { kind: "pending_refund_review", orderId: pendingRefund.orderId ?? null };
  }

  return { kind: "ignore", reason: "unknown_notification" };
}
