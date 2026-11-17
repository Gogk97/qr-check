-- ============================================================================
-- GOOGLE PLAY RTDN (Real-time Developer Notifications)
-- ----------------------------------------------------------------------------
-- Mendukung function `play-rtdn`:
--   * play_rtdn_events        -> dedupe pesan Pub/Sub (message_id unik) + audit
--   * play_purchase_inbox     -> pembelian yang sudah di-acknowledge tapi belum
--                                dipetakan ke akun (user belum pernah restore)
--   * record_play_rtdn_event  -> return true jika pesan pertama kali diproses
--   * upsert_play_purchase_inbox
-- Semua RPC hanya bisa dipanggil service_role (Edge Function).
-- Script ini idempotent (aman dijalankan ulang).
-- ============================================================================

-- 1. DEDUPE & AUDIT ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.play_rtdn_events (
  message_id     TEXT PRIMARY KEY,
  event_type     TEXT NOT NULL DEFAULT 'UNKNOWN',
  purchase_token TEXT,
  package_name   TEXT,
  payload        JSONB,
  processed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_play_rtdn_events_token
  ON public.play_rtdn_events(purchase_token, processed_at DESC);
CREATE INDEX IF NOT EXISTS idx_play_rtdn_events_time
  ON public.play_rtdn_events(processed_at DESC);

ALTER TABLE public.play_rtdn_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.play_rtdn_events FROM anon, authenticated;

-- 2. INBOX PEMBELIAN BELUM TERKLAIM -----------------------------------------
CREATE TABLE IF NOT EXISTS public.play_purchase_inbox (
  purchase_token TEXT PRIMARY KEY,
  product_id     TEXT,
  order_id       TEXT,
  state          TEXT NOT NULL DEFAULT 'PURCHASED', -- PURCHASED | CANCELLED
  acknowledged   BOOLEAN NOT NULL DEFAULT false,
  region_code    TEXT,
  raw_payload    JSONB,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_play_inbox_state
  ON public.play_purchase_inbox(state, updated_at DESC);

ALTER TABLE public.play_purchase_inbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.play_purchase_inbox FROM anon, authenticated;

-- 3. RPC: DEDUPE EVENT -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_play_rtdn_event(
  p_message_id     text,
  p_event_type     text    DEFAULT 'UNKNOWN',
  p_purchase_token text    DEFAULT NULL,
  p_package_name   text    DEFAULT NULL,
  p_payload        jsonb   DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted int := 0;
BEGIN
  IF p_message_id IS NULL OR length(p_message_id) = 0 THEN
    RAISE EXCEPTION 'invalid_message_id';
  END IF;

  INSERT INTO public.play_rtdn_events (
    message_id, event_type, purchase_token, package_name, payload
  ) VALUES (
    p_message_id, COALESCE(p_event_type, 'UNKNOWN'), p_purchase_token, p_package_name, p_payload
  )
  ON CONFLICT (message_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.record_play_rtdn_event(text, text, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_play_rtdn_event(text, text, text, text, jsonb)
  TO service_role;

-- 4. RPC: UPSERT INBOX -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_play_purchase_inbox(
  p_purchase_token text,
  p_product_id     text    DEFAULT NULL,
  p_order_id       text    DEFAULT NULL,
  p_state          text    DEFAULT 'PURCHASED',
  p_acknowledged   boolean DEFAULT false,
  p_region_code    text    DEFAULT NULL,
  p_raw            jsonb   DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_purchase_token IS NULL OR length(p_purchase_token) < 10 THEN
    RAISE EXCEPTION 'invalid_purchase_token';
  END IF;

  INSERT INTO public.play_purchase_inbox (
    purchase_token, product_id, order_id, state, acknowledged, region_code, raw_payload
  ) VALUES (
    p_purchase_token, p_product_id, p_order_id,
    COALESCE(p_state, 'PURCHASED'), COALESCE(p_acknowledged, false),
    p_region_code, p_raw
  )
  ON CONFLICT (purchase_token) DO UPDATE
    SET state        = EXCLUDED.state,
        acknowledged = EXCLUDED.acknowledged,
        product_id   = COALESCE(EXCLUDED.product_id, play_purchase_inbox.product_id),
        order_id     = COALESCE(EXCLUDED.order_id, play_purchase_inbox.order_id),
        region_code  = COALESCE(EXCLUDED.region_code, play_purchase_inbox.region_code),
        raw_payload  = COALESCE(EXCLUDED.raw_payload, play_purchase_inbox.raw_payload),
        updated_at   = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_play_purchase_inbox(text, text, text, text, boolean, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_play_purchase_inbox(text, text, text, text, boolean, text, jsonb)
  TO service_role;

-- 5. OPERASIONAL: pembelian yang sudah dibayar tapi belum masuk akun mana pun --
CREATE OR REPLACE VIEW public.play_unclaimed_purchases AS
SELECT i.purchase_token,
       i.product_id,
       i.order_id,
       i.state,
       i.acknowledged,
       i.created_at,
       i.updated_at
FROM public.play_purchase_inbox i
LEFT JOIN public.play_purchases p ON p.purchase_token = i.purchase_token
WHERE p.purchase_token IS NULL
  AND i.state = 'PURCHASED';

REVOKE ALL ON public.play_unclaimed_purchases FROM anon, authenticated;
