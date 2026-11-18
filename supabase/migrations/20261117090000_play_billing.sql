-- ============================================================================
-- GOOGLE PLAY BILLING • PRO LIFETIME (one-time product)
-- ----------------------------------------------------------------------------
-- Prinsip:
--   * Client TIDAK PERNAH menulis is_pro / play_purchases secara langsung.
--   * Hanya service_role (Edge Function `verify-play-purchase`) yang boleh
--     memanggil RPC grant/revoke setelah purchase token diverifikasi ke
--     Google Play Developer API.
--   * Satu purchase_token hanya boleh diklaim satu akun (anti replay/sharing).
-- Script ini idempotent (aman dijalankan ulang).
-- ============================================================================

-- 1. PROFILES: sumber aktivasi PRO -------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS pro_source TEXT; -- 'play' | 'qris' | 'admin' | NULL

-- 2. TABEL PLAY PURCHASES -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.play_purchases (
  purchase_token  TEXT PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id      TEXT NOT NULL,
  order_id        TEXT,
  purchase_state  TEXT NOT NULL DEFAULT 'PURCHASED',  -- PURCHASED | CANCELLED | PENDING
  acknowledged    BOOLEAN NOT NULL DEFAULT false,
  is_test         BOOLEAN NOT NULL DEFAULT false,     -- license tester purchase
  region_code     TEXT,
  raw_payload     JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_play_purchases_user
  ON public.play_purchases(user_id, created_at DESC);

ALTER TABLE public.play_purchases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.play_purchases FROM anon, authenticated;
GRANT SELECT ON public.play_purchases TO authenticated;

DROP POLICY IF EXISTS "play_purchases_select_own" ON public.play_purchases;
CREATE POLICY "play_purchases_select_own" ON public.play_purchases
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- 3. RPC: GRANT PRO DARI GOOGLE PLAY -----------------------------------------
CREATE OR REPLACE FUNCTION public.grant_pro_from_play(
  p_user_id        uuid,
  p_purchase_token text,
  p_product_id     text,
  p_order_id       text    DEFAULT NULL,
  p_is_test        boolean DEFAULT false,
  p_region_code    text    DEFAULT NULL,
  p_raw            jsonb   DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
BEGIN
  IF p_user_id IS NULL OR p_purchase_token IS NULL OR length(p_purchase_token) < 10 THEN
    RAISE EXCEPTION 'invalid_arguments';
  END IF;
  IF p_product_id IS NULL OR length(p_product_id) = 0 THEN
    RAISE EXCEPTION 'invalid_product';
  END IF;

  SELECT user_id INTO v_owner
  FROM public.play_purchases
  WHERE purchase_token = p_purchase_token;

  IF v_owner IS NOT NULL AND v_owner <> p_user_id THEN
    -- Token sudah diklaim akun lain: tolak (indikasi replay / share akun).
    RAISE EXCEPTION 'purchase_token_already_claimed';
  END IF;

  INSERT INTO public.play_purchases (
    purchase_token, user_id, product_id, order_id, purchase_state,
    acknowledged, is_test, region_code, raw_payload
  ) VALUES (
    p_purchase_token, p_user_id, p_product_id, p_order_id, 'PURCHASED',
    true, COALESCE(p_is_test, false), p_region_code, p_raw
  )
  ON CONFLICT (purchase_token) DO UPDATE
    SET purchase_state = 'PURCHASED',
        acknowledged   = true,
        order_id       = COALESCE(play_purchases.order_id, EXCLUDED.order_id),
        region_code    = COALESCE(EXCLUDED.region_code, play_purchases.region_code),
        raw_payload    = COALESCE(EXCLUDED.raw_payload, play_purchases.raw_payload),
        updated_at     = now();

  UPDATE public.profiles
     SET is_pro           = true,
         pro_source       = 'play',
         pro_activated_at = COALESCE(pro_activated_at, now()),
         updated_at       = now()
   WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'is_pro', true,
    'product_id', p_product_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.grant_pro_from_play(uuid, text, text, text, boolean, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_pro_from_play(uuid, text, text, text, boolean, text, jsonb)
  TO service_role;

-- 4. RPC: REVOKE PRO (refund / voided purchase / chargeback) ------------------
CREATE OR REPLACE FUNCTION public.revoke_pro_from_play(
  p_purchase_token text,
  p_reason         text DEFAULT 'refunded'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  uuid;
  v_other int;
BEGIN
  SELECT user_id INTO v_user
  FROM public.play_purchases
  WHERE purchase_token = p_purchase_token;

  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'purchase_not_found');
  END IF;

  UPDATE public.play_purchases
     SET purchase_state = 'CANCELLED',
         acknowledged   = false,
         updated_at     = now(),
         raw_payload    = COALESCE(raw_payload, '{}'::jsonb) || jsonb_build_object('revoke_reason', p_reason)
   WHERE purchase_token = p_purchase_token;

  -- Masih punya pembelian Play lain yang aktif? Jangan cabut PRO-nya.
  SELECT count(*) INTO v_other
  FROM public.play_purchases
  WHERE user_id = v_user
    AND purchase_state = 'PURCHASED';

  IF v_other = 0 THEN
    UPDATE public.profiles
       SET is_pro     = false,
           pro_source = NULL,
           updated_at = now()
     WHERE id = v_user
       AND pro_source = 'play';
  END IF;

  RETURN jsonb_build_object('success', true, 'is_pro', (v_other > 0));
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_pro_from_play(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_pro_from_play(text, text)
  TO service_role;
