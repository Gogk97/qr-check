-- ============================================================================
-- SECURITY HARDENING (hasil audit 2026-11-17)
-- ----------------------------------------------------------------------------
-- Menutup:
--   M-1 device quota farming  : device_id tidak bisa diganti + batas device/akun
--   M-2 cross-user quota      : client tidak boleh menulis profiles.device_id
--   M-4 tanpa rate limit      : helper check_rate_limit() dipakai RPC sensitif
--   H-1 claim_ad_reward       : RPC server-side (bukan tambah kuota lokal)
--   refund                    : refund_quota() idempoten saat hapus dibatalkan
-- Idempotent (aman dijalankan ulang).
-- ============================================================================

-- 1. PROFILES: cabut hak UPDATE kolom device_id -------------------------------
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (
  display_name,
  avatar_url,
  device_platform,
  device_brand,
  device_model,
  os_version,
  device_summary,
  last_sign_in_at
) ON public.profiles TO authenticated;
-- device_id hanya boleh di-set lewat RPC (update_device_info / claim_device_*).

-- 2. RATE LIMIT ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rpc_rate_limits (
  user_id      UUID        NOT NULL,
  action       TEXT        NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  hits         INT         NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, action, window_start)
);
ALTER TABLE public.rpc_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rpc_rate_limits FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_action TEXT,
  p_max    INT,
  p_window INTERVAL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_bucket TIMESTAMPTZ;
  v_hits   INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;
  IF p_window IS NULL OR extract(epoch FROM p_window) <= 0 THEN
    p_window := interval '1 hour';
  END IF;

  v_bucket := to_timestamp(
    floor(extract(epoch FROM now()) / extract(epoch FROM p_window)) * extract(epoch FROM p_window)
  );

  INSERT INTO public.rpc_rate_limits (user_id, action, window_start, hits)
  VALUES (v_uid, p_action, v_bucket, 1)
  ON CONFLICT (user_id, action, window_start)
  DO UPDATE SET hits = public.rpc_rate_limits.hits + 1
  RETURNING hits INTO v_hits;

  RETURN v_hits <= GREATEST(p_max, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.check_rate_limit(text, int, interval)
  FROM PUBLIC, anon, authenticated;  -- hanya dipakai fungsi SECURITY DEFINER internal

-- 3. UPDATE_DEVICE_INFO: device_id hanya boleh diikat sekali ------------------
CREATE OR REPLACE FUNCTION public.update_device_info(
  p_device_id       TEXT DEFAULT NULL,
  p_device_brand    TEXT DEFAULT NULL,
  p_device_model    TEXT DEFAULT NULL,
  p_os_version      TEXT DEFAULT NULL,
  p_device_platform TEXT DEFAULT NULL,
  p_device_summary  TEXT DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         UUID := auth.uid();
  v_prof        public.profiles%ROWTYPE;
  v_new_device  TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHENTICATED');
  END IF;

  SELECT * INTO v_prof FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'PROFILE_NOT_FOUND');
  END IF;

  -- Ikat perangkat sekali; percobaan mengganti device_id diabaikan.
  IF v_prof.device_id IS NULL OR length(trim(v_prof.device_id)) = 0 THEN
    v_new_device := NULLIF(trim(p_device_id), '');
  ELSE
    v_new_device := v_prof.device_id;
  END IF;

  UPDATE public.profiles
  SET
    device_id       = v_new_device,
    device_brand    = COALESCE(p_device_brand, device_brand),
    device_model    = COALESCE(p_device_model, device_model),
    os_version      = COALESCE(p_os_version, os_version),
    device_platform = COALESCE(p_device_platform, device_platform),
    device_summary  = COALESCE(p_device_summary, device_summary),
    last_sign_in_at = now(),
    updated_at      = now()
  WHERE id = v_uid;

  RETURN json_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.update_device_info(text, text, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_device_info(text, text, text, text, text, text)
  TO authenticated;

-- 4. CONSUME_QUOTA: + rate limit ---------------------------------------------
CREATE OR REPLACE FUNCTION public.consume_quota(p_amount int, p_ref_id text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_pro       boolean;
  v_quota     int;
  v_device_id text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'code', 'UNAUTHORIZED');
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 1000 THEN
    RETURN json_build_object('success', false, 'code', 'INVALID_AMOUNT');
  END IF;
  IF NOT public.check_rate_limit('consume_quota', 120, interval '1 hour') THEN
    RETURN json_build_object('success', false, 'code', 'RATE_LIMITED');
  END IF;

  SELECT is_pro, remaining_quota INTO v_pro, v_quota
  FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'PROFILE_NOT_FOUND');
  END IF;

  IF v_pro THEN
    RETURN json_build_object('success', true, 'is_pro', true,
                             'remaining_quota', v_quota, 'consumed', 0);
  END IF;

  IF p_ref_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.quota_ledger
    WHERE user_id = v_uid AND ref_id = p_ref_id AND reason = 'DELETE_PHOTO'
  ) THEN
    RETURN json_build_object('success', true, 'is_pro', false,
                             'remaining_quota', v_quota, 'consumed', 0, 'replayed', true);
  END IF;

  IF v_quota < p_amount THEN
    RETURN json_build_object('success', false, 'code', 'INSUFFICIENT_QUOTA',
                             'remaining_quota', v_quota);
  END IF;

  v_quota := v_quota - p_amount;
  UPDATE public.profiles SET remaining_quota = v_quota, updated_at = now() WHERE id = v_uid;

  SELECT device_id INTO v_device_id FROM public.profiles WHERE id = v_uid;
  IF v_device_id IS NOT NULL THEN
    UPDATE public.device_allowances SET remaining_quota = v_quota, last_seen_at = now()
    WHERE device_id = v_device_id;
    UPDATE public.profiles SET remaining_quota = v_quota, updated_at = now()
    WHERE device_id = v_device_id AND id != v_uid;
  END IF;

  INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
  VALUES (v_uid, -p_amount, 'DELETE_PHOTO', v_quota, p_ref_id);

  RETURN json_build_object('success', true, 'is_pro', false,
                           'remaining_quota', v_quota, 'consumed', p_amount);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_quota(int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_quota(int, text) TO authenticated;

-- 5. REFUND_QUOTA: kembalikan kuota bila hapus dibatalkan ---------------------
CREATE OR REPLACE FUNCTION public.refund_quota(
  p_ref_id TEXT,
  p_amount INT
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_original INT;
  v_quota    INT;
  v_refund   INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'code', 'UNAUTHORIZED');
  END IF;
  IF p_ref_id IS NULL OR length(trim(p_ref_id)) = 0 OR p_amount IS NULL OR p_amount <= 0 THEN
    RETURN json_build_object('success', false, 'code', 'INVALID_ARGUMENTS');
  END IF;

  SELECT -delta INTO v_original
  FROM public.quota_ledger
  WHERE user_id = v_uid AND reason = 'DELETE_PHOTO' AND ref_id = p_ref_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'NO_SUCH_CONSUMPTION');
  END IF;

  -- Idempoten: satu ref_id hanya bisa di-refund sekali.
  IF EXISTS (
    SELECT 1 FROM public.quota_ledger
    WHERE user_id = v_uid AND reason = 'ADMIN_ADJUST' AND ref_id = 'refund_' || p_ref_id
  ) THEN
    SELECT remaining_quota INTO v_quota FROM public.profiles WHERE id = v_uid;
    RETURN json_build_object('success', true, 'replayed', true, 'remaining_quota', v_quota);
  END IF;

  v_refund := LEAST(p_amount, v_original);

  UPDATE public.profiles
  SET remaining_quota = remaining_quota + v_refund, updated_at = now()
  WHERE id = v_uid
  RETURNING remaining_quota INTO v_quota;

  INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
  VALUES (v_uid, v_refund, 'ADMIN_ADJUST', v_quota, 'refund_' || p_ref_id);

  RETURN json_build_object('success', true, 'remaining_quota', v_quota, 'refunded', v_refund);
END;
$$;

REVOKE ALL ON FUNCTION public.refund_quota(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refund_quota(text, int) TO authenticated;

-- 6. CLAIM_AD_REWARD: reward iklan server-side (batas harian) -----------------
-- CATATAN: ini pengganti sementara selama iklan masih simulasi. Saat AdMob
-- terpasang, pakai `grant_ad_reward` lewat Edge Function SSV dan hapus RPC ini.
CREATE OR REPLACE FUNCTION public.claim_ad_reward(p_ref_id text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_quota INT;
  v_today INT;
  v_ref   TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'code', 'UNAUTHORIZED');
  END IF;
  IF NOT public.check_rate_limit('claim_ad_reward', 20, interval '1 hour') THEN
    RETURN json_build_object('success', false, 'code', 'RATE_LIMITED');
  END IF;

  SELECT count(*) INTO v_today
  FROM public.ad_reward_events
  WHERE user_id = v_uid AND created_at > now() - interval '1 day';

  IF v_today >= 5 THEN
    RETURN json_build_object('success', false, 'code', 'DAILY_LIMIT_REACHED');
  END IF;

  v_ref := COALESCE(NULLIF(trim(p_ref_id), ''), 'auto_' || gen_random_uuid()::text);

  INSERT INTO public.ad_reward_events (transaction_id, user_id)
  VALUES ('client:' || v_ref, v_uid)
  ON CONFLICT (transaction_id) DO NOTHING;

  IF NOT FOUND THEN
    SELECT remaining_quota INTO v_quota FROM public.profiles WHERE id = v_uid;
    RETURN json_build_object('success', true, 'replayed', true, 'remaining_quota', v_quota);
  END IF;

  UPDATE public.profiles
  SET remaining_quota = remaining_quota + 1, updated_at = now()
  WHERE id = v_uid
  RETURNING remaining_quota INTO v_quota;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile % not found', v_uid;
  END IF;

  INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
  VALUES (v_uid, 1, 'AD_REWARD', v_quota, 'client_ad_' || v_ref);

  RETURN json_build_object('success', true, 'remaining_quota', v_quota);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_ad_reward(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_ad_reward(text) TO authenticated;

-- 7. CLAIM_DEVICE_WELCOME_QUOTA: anti farming --------------------------------
CREATE OR REPLACE FUNCTION public.claim_device_welcome_quota(
  p_device_id       TEXT,
  p_device_brand    TEXT DEFAULT NULL,
  p_device_model    TEXT DEFAULT NULL,
  p_os_version      TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_profile        public.profiles%ROWTYPE;
  v_existing_allow public.device_allowances%ROWTYPE;
  v_pool_quota     INT := 0;
  v_is_first_claim BOOLEAN := false;
  v_device_count   INT := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHENTICATED');
  END IF;

  IF p_device_id IS NULL OR length(trim(p_device_id)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_DEVICE_ID');
  END IF;

  IF NOT public.check_rate_limit('claim_device_quota', 10, interval '1 hour') THEN
    RETURN json_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'PROFILE_NOT_FOUND');
  END IF;

  -- Anti-farming: akun yang sudah terikat ke satu perangkat tidak bisa
  -- mengklaim bonus untuk device_id lain.
  IF v_profile.device_id IS NOT NULL
     AND length(trim(v_profile.device_id)) > 0
     AND v_profile.device_id <> p_device_id THEN
    RETURN json_build_object(
      'success', false,
      'error', 'DEVICE_MISMATCH',
      'remaining_quota', v_profile.remaining_quota,
      'is_pro', v_profile.is_pro
    );
  END IF;

  SELECT * INTO v_existing_allow FROM public.device_allowances
  WHERE device_id = p_device_id FOR UPDATE;

  IF NOT FOUND THEN
    -- Batasi jumlah perangkat yang boleh menerima bonus per akun.
    SELECT count(*) INTO v_device_count
    FROM public.device_allowances WHERE first_user_id = v_uid;

    IF v_device_count >= 2 THEN
      RETURN json_build_object(
        'success', false,
        'error', 'DEVICE_LIMIT_REACHED',
        'remaining_quota', v_profile.remaining_quota,
        'is_pro', v_profile.is_pro
      );
    END IF;

    v_is_first_claim := true;
    v_pool_quota := CASE WHEN v_profile.is_guest THEN 5 ELSE 10 END;

    INSERT INTO public.device_allowances (
      device_id, first_user_id, first_auth_type, bonus_claimed,
      remaining_quota, claimed_at, last_seen_at, device_brand, device_model, os_version
    ) VALUES (
      p_device_id, v_uid, CASE WHEN v_profile.is_guest THEN 'guest' ELSE 'google' END,
      true, v_pool_quota, now(), now(), p_device_brand, p_device_model, p_os_version
    );

    UPDATE public.profiles
    SET remaining_quota = v_pool_quota,
        device_id = p_device_id,
        device_brand = COALESCE(p_device_brand, device_brand),
        device_model = COALESCE(p_device_model, device_model),
        os_version = COALESCE(p_os_version, os_version),
        updated_at = now()
    WHERE id = v_uid;

    IF NOT EXISTS (SELECT 1 FROM public.quota_ledger WHERE user_id = v_uid) THEN
      INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
      VALUES (v_uid, v_pool_quota, 'INITIAL', v_pool_quota, 'welcome_' || p_device_id);
    END IF;

  ELSE
    v_pool_quota := v_existing_allow.remaining_quota;

    UPDATE public.device_allowances
    SET last_seen_at = now(),
        device_brand = COALESCE(p_device_brand, device_brand),
        device_model = COALESCE(p_device_model, device_model),
        os_version = COALESCE(p_os_version, os_version)
    WHERE device_id = p_device_id;

    UPDATE public.profiles
    SET remaining_quota = v_pool_quota,
        device_id = p_device_id,
        device_brand = COALESCE(p_device_brand, device_brand),
        device_model = COALESCE(p_device_model, device_model),
        os_version = COALESCE(p_os_version, os_version),
        updated_at = now()
    WHERE id = v_uid;

    IF NOT EXISTS (SELECT 1 FROM public.quota_ledger WHERE user_id = v_uid) THEN
      INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
      VALUES (v_uid, v_pool_quota, 'INITIAL', v_pool_quota, 'shared_device_' || p_device_id);
    END IF;
  END IF;

  RETURN json_build_object(
    'success', true,
    'bonus_granted', true,
    'is_first_device_claim', v_is_first_claim,
    'remaining_quota', v_pool_quota,
    'is_pro', v_profile.is_pro
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_device_welcome_quota(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_device_welcome_quota(text, text, text, text) TO authenticated;

-- 8. SUBMIT_PAYMENT: + rate limit --------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_payment(
  p_sender_bank text,
  p_proof_path  text,
  p_notes       text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_price constant int := 15000;
  v_uid   uuid := auth.uid();
  v_prof  public.profiles%ROWTYPE;
  v_id    text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'code', 'UNAUTHORIZED');
  END IF;

  IF NOT public.check_rate_limit('submit_payment', 5, interval '1 hour') THEN
    RETURN json_build_object('success', false, 'code', 'RATE_LIMITED');
  END IF;

  SELECT * INTO v_prof FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'PROFILE_NOT_FOUND');
  END IF;
  IF v_prof.is_pro THEN
    RETURN json_build_object('success', false, 'code', 'ALREADY_PRO');
  END IF;
  IF p_proof_path IS NULL OR split_part(p_proof_path, '/', 1) <> v_uid::text THEN
    RETURN json_build_object('success', false, 'code', 'INVALID_PROOF_PATH');
  END IF;
  IF EXISTS (SELECT 1 FROM public.payments WHERE user_id = v_uid AND status = 'PENDING') THEN
    RETURN json_build_object('success', false, 'code', 'PENDING_EXISTS');
  END IF;

  INSERT INTO public.payments (user_id, user_name, user_email, sender_bank, amount, proof_path, notes)
  VALUES (v_uid, v_prof.display_name, v_prof.email,
          left(COALESCE(NULLIF(trim(p_sender_bank), ''), 'QRIS'), 40),
          c_price, p_proof_path, left(p_notes, 500))
  RETURNING id INTO v_id;

  RETURN json_build_object('success', true, 'payment_id', v_id, 'status', 'PENDING');
END;
$$;

REVOKE ALL ON FUNCTION public.submit_payment(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_payment(text, text, text) TO authenticated;
