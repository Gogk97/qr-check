-- ============================================================================
-- QR-CHECK • SUPABASE SCHEMA v2 (hardened)
-- Postgres + Supabase Auth (Google & Anonymous) + Storage + RLS
--
-- Prinsip keamanan:
--   * Client TIDAK PERNAH menulis langsung ke kuota / is_pro / status pembayaran.
--   * Semua mutasi sensitif lewat fungsi SECURITY DEFINER yang divalidasi.
--   * Fungsi admin hanya untuk JWT dengan app_metadata.role = 'admin'
--     (app_metadata hanya bisa diubah server-side / service_role).
--   * Reward iklan hanya bisa diberikan oleh service_role (Edge Function SSV).
--   * Ledger kuota bersifat append-only.
-- Script ini idempotent (aman dijalankan ulang).
-- ============================================================================

-- 1. ENUMS ------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.payment_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.quota_reason AS ENUM ('INITIAL', 'DELETE_PHOTO', 'AD_REWARD', 'ADMIN_ADJUST');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. TABLES -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name     TEXT NOT NULL DEFAULT 'User',
  email            TEXT NOT NULL DEFAULT '',
  avatar_url       TEXT,
  is_guest         BOOLEAN NOT NULL DEFAULT false,
  is_pro           BOOLEAN NOT NULL DEFAULT false,
  pro_activated_at TIMESTAMPTZ,
  remaining_quota  INT NOT NULL DEFAULT 5 CHECK (remaining_quota >= 0),
  device_platform  TEXT,
  device_id        TEXT,
  device_brand     TEXT,
  device_model     TEXT,
  os_version       TEXT,
  device_summary   TEXT,
  last_sign_in_at  TIMESTAMPTZ DEFAULT now(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quota_ledger (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delta         INT NOT NULL,
  reason        public.quota_reason NOT NULL,
  balance_after INT NOT NULL,
  ref_id        TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_quota_ledger_user ON public.quota_ledger(user_id, created_at DESC);
-- Idempotency: satu ref_id hanya boleh memotong kuota sekali per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_quota_ledger_delete_ref
  ON public.quota_ledger(user_id, ref_id)
  WHERE reason = 'DELETE_PHOTO' AND ref_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.ad_reward_events (
  transaction_id TEXT PRIMARY KEY,           -- dari AdMob SSV (anti replay)
  user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- ANTI-EXPLOIT / MULTI-ACCOUNT TAMPER PROTECTION (Device-Bound Quota & Guest)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.device_allowances (
  device_id         TEXT PRIMARY KEY,
  first_user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  first_auth_type   TEXT NOT NULL DEFAULT 'google', -- 'google' atau 'guest'
  bonus_claimed     BOOLEAN NOT NULL DEFAULT true,
  remaining_quota   INT NOT NULL DEFAULT 10 CHECK (remaining_quota >= 0),
  claimed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  device_brand      TEXT,
  device_model      TEXT,
  os_version        TEXT
);
ALTER TABLE public.device_allowances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.device_allowances FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.payments (
  id          TEXT PRIMARY KEY DEFAULT ('PAY-' || replace(gen_random_uuid()::text, '-', '')),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_name   TEXT NOT NULL,
  user_email  TEXT NOT NULL DEFAULT '',
  sender_bank TEXT NOT NULL DEFAULT 'QRIS',
  amount      INT  NOT NULL CHECK (amount > 0),
  proof_path  TEXT,
  status      public.payment_status NOT NULL DEFAULT 'PENDING',
  notes       TEXT,
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_user   ON public.payments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status, created_at DESC);
-- Maksimal 1 pembayaran PENDING per user (anti spam)
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_one_pending
  ON public.payments(user_id) WHERE status = 'PENDING';

-- 3. HELPERS ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

-- Ledger append-only: tolak UPDATE/DELETE
CREATE OR REPLACE FUNCTION public.block_ledger_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'quota_ledger is append-only';
END;
$$;
DROP TRIGGER IF EXISTS trg_ledger_immutable ON public.quota_ledger;
CREATE TRIGGER trg_ledger_immutable
  BEFORE UPDATE OR DELETE ON public.quota_ledger
  FOR EACH ROW EXECUTE FUNCTION public.block_ledger_mutation();

-- 4. ROW LEVEL SECURITY -----------------------------------------------------
ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quota_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_reward_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"  ON public.profiles;
DROP POLICY IF EXISTS "ledger_select_own"    ON public.quota_ledger;
DROP POLICY IF EXISTS "payments_select_own"  ON public.payments;
DROP POLICY IF EXISTS "payments_select_admin" ON public.payments;

CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "ledger_select_own" ON public.quota_ledger
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "payments_select_own" ON public.payments
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "payments_select_admin" ON public.payments
  FOR SELECT TO authenticated USING (public.is_admin());
-- ad_reward_events: tanpa policy → hanya service_role yang bisa akses.

-- Privilege hardening (defense in depth di atas RLS)
REVOKE ALL ON public.profiles, public.quota_ledger, public.payments, public.ad_reward_events
  FROM anon, authenticated;
GRANT SELECT ON public.profiles, public.quota_ledger, public.payments TO authenticated;
-- Client hanya boleh mengubah kolom non-sensitif pada profil:
GRANT UPDATE (
  display_name,
  avatar_url,
  device_platform,
  device_id,
  device_brand,
  device_model,
  os_version,
  device_summary,
  last_sign_in_at
) ON public.profiles TO authenticated;

-- 5. TRIGGER: PROFIL OTOMATIS SAAT SIGNUP -----------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_is_guest boolean;
  v_name     text;
  v_avatar   text;
BEGIN
  v_is_guest := COALESCE(
    (new.is_anonymous IS TRUE) OR ((new.raw_user_meta_data ->> 'is_guest') = 'true'),
    false
  );

  v_name := COALESCE(
    NULLIF(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    NULLIF(trim(new.raw_user_meta_data ->> 'name'), ''),
    CASE WHEN v_is_guest THEN 'Pengguna Tamu' ELSE 'Pengguna' END
  );

  v_avatar := COALESCE(
    NULLIF(trim(new.raw_user_meta_data ->> 'avatar_url'), ''),
    NULLIF(trim(new.raw_user_meta_data ->> 'picture'), '')
  );

  INSERT INTO public.profiles (
    id, display_name, email, avatar_url, is_guest, remaining_quota,
    device_id, device_brand, device_model, os_version, device_platform, device_summary,
    last_sign_in_at
  )
  VALUES (
    new.id,
    v_name,
    COALESCE(new.email, ''),
    v_avatar,
    v_is_guest,
    0, -- Kuota awal dikelola oleh RPC claim_device_welcome_quota (Shared Device Quota Pool)
    new.raw_user_meta_data ->> 'device_id',
    new.raw_user_meta_data ->> 'device_brand',
    new.raw_user_meta_data ->> 'device_model',
    new.raw_user_meta_data ->> 'os_version',
    new.raw_user_meta_data ->> 'device_platform',
    new.raw_user_meta_data ->> 'device_summary',
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = COALESCE(EXCLUDED.display_name, public.profiles.display_name),
    email = COALESCE(NULLIF(EXCLUDED.email, ''), public.profiles.email),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    device_id = COALESCE(EXCLUDED.device_id, public.profiles.device_id),
    device_brand = COALESCE(EXCLUDED.device_brand, public.profiles.device_brand),
    device_model = COALESCE(EXCLUDED.device_model, public.profiles.device_model),
    os_version = COALESCE(EXCLUDED.os_version, public.profiles.os_version),
    device_platform = COALESCE(EXCLUDED.device_platform, public.profiles.device_platform),
    device_summary = COALESCE(EXCLUDED.device_summary, public.profiles.device_summary),
    last_sign_in_at = now(),
    updated_at = now();

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 6. RPC: KUOTA -------------------------------------------------------------
-- Potong kuota atomik + idempotent (p_ref_id sama → tidak dipotong dua kali).
CREATE OR REPLACE FUNCTION public.consume_quota(p_amount int, p_ref_id text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

  SELECT is_pro, remaining_quota INTO v_pro, v_quota
  FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'PROFILE_NOT_FOUND');
  END IF;

  IF v_pro THEN  -- PRO: unlimited, tidak ada pemotongan
    RETURN json_build_object('success', true, 'is_pro', true,
                             'remaining_quota', v_quota, 'consumed', 0);
  END IF;

  IF p_ref_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.quota_ledger
    WHERE user_id = v_uid AND ref_id = p_ref_id AND reason = 'DELETE_PHOTO'
  ) THEN  -- replay request yang sama
    RETURN json_build_object('success', true, 'is_pro', false,
                             'remaining_quota', v_quota, 'consumed', 0, 'replayed', true);
  END IF;

  IF v_quota < p_amount THEN
    RETURN json_build_object('success', false, 'code', 'INSUFFICIENT_QUOTA',
                             'remaining_quota', v_quota);
  END IF;

  v_quota := v_quota - p_amount;
  UPDATE public.profiles SET remaining_quota = v_quota, updated_at = now() WHERE id = v_uid;

  -- Sinkronkan pool perangkat jika akun terhubung ke device fisik
  SELECT device_id INTO v_device_id FROM public.profiles WHERE id = v_uid;
  IF v_device_id IS NOT NULL THEN
    UPDATE public.device_allowances SET remaining_quota = v_quota, last_seen_at = now() WHERE device_id = v_device_id;
    UPDATE public.profiles SET remaining_quota = v_quota, updated_at = now() WHERE device_id = v_device_id AND id != v_uid;
  END IF;

  INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
  VALUES (v_uid, -p_amount, 'DELETE_PHOTO', v_quota, p_ref_id);

  RETURN json_build_object('success', true, 'is_pro', false,
                           'remaining_quota', v_quota, 'consumed', p_amount);
END;
$$;

-- Reward iklan: HANYA service_role (Edge Function yang memverifikasi AdMob SSV).
CREATE OR REPLACE FUNCTION public.grant_ad_reward(p_user_id uuid, p_transaction_id text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_quota int;
BEGIN
  IF p_transaction_id IS NULL OR length(p_transaction_id) = 0 THEN
    RETURN json_build_object('success', false, 'code', 'INVALID_TRANSACTION');
  END IF;

  INSERT INTO public.ad_reward_events (transaction_id, user_id)
  VALUES (p_transaction_id, p_user_id)
  ON CONFLICT (transaction_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'DUPLICATE_TRANSACTION');
  END IF;

  UPDATE public.profiles
  SET remaining_quota = remaining_quota + 1, updated_at = now()
  WHERE id = p_user_id
  RETURNING remaining_quota INTO v_quota;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile % not found', p_user_id;
  END IF;

  INSERT INTO public.quota_ledger (user_id, delta, reason, balance_after, ref_id)
  VALUES (p_user_id, 1, 'AD_REWARD', v_quota, p_transaction_id);

  RETURN json_build_object('success', true, 'remaining_quota', v_quota);
END;
$$;

-- 7. RPC: PEMBAYARAN --------------------------------------------------------
-- Client tidak bisa INSERT langsung → status & nominal dipaksa server.
CREATE OR REPLACE FUNCTION public.submit_payment(
  p_sender_bank text,
  p_proof_path  text,
  p_notes       text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

CREATE OR REPLACE FUNCTION public.approve_payment(p_payment_id text, p_notes text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user   uuid;
  v_status public.payment_status;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'code', 'FORBIDDEN');
  END IF;

  SELECT user_id, status INTO v_user, v_status
  FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'NOT_FOUND');
  END IF;
  IF v_status <> 'PENDING' THEN
    RETURN json_build_object('success', false, 'code', 'NOT_PENDING', 'status', v_status);
  END IF;

  UPDATE public.payments
  SET status = 'APPROVED', notes = COALESCE(p_notes, notes),
      reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  WHERE id = p_payment_id;

  UPDATE public.profiles
  SET is_pro = true, pro_activated_at = now(), updated_at = now()
  WHERE id = v_user;

  RETURN json_build_object('success', true, 'payment_id', p_payment_id,
                           'user_id', v_user, 'status', 'APPROVED');
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_payment(p_payment_id text, p_notes text DEFAULT 'Bukti transfer tidak valid')
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_status public.payment_status;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN json_build_object('success', false, 'code', 'FORBIDDEN');
  END IF;

  SELECT status INTO v_status FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'code', 'NOT_FOUND');
  END IF;
  IF v_status <> 'PENDING' THEN
    RETURN json_build_object('success', false, 'code', 'NOT_PENDING', 'status', v_status);
  END IF;

  UPDATE public.payments
  SET status = 'REJECTED', notes = p_notes,
      reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  WHERE id = p_payment_id;

  RETURN json_build_object('success', true, 'payment_id', p_payment_id, 'status', 'REJECTED');
END;
$$;

-- 8. EXECUTE PRIVILEGES (default Postgres: PUBLIC boleh EXECUTE → dicabut) ---
REVOKE EXECUTE ON FUNCTION
  public.consume_quota(int, text),
  public.grant_ad_reward(uuid, text),
  public.submit_payment(text, text, text),
  public.approve_payment(text, text),
  public.reject_payment(text, text),
  public.handle_new_user(),
  public.block_ledger_mutation()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.consume_quota(int, text)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_payment(text, text, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment(text, text)       TO authenticated;  -- dijaga is_admin()
GRANT EXECUTE ON FUNCTION public.reject_payment(text, text)        TO authenticated;  -- dijaga is_admin()
GRANT EXECUTE ON FUNCTION public.grant_ad_reward(uuid, text)       TO service_role;

-- 8b. UPDATE DEVICE INFO HELPER ---------------------------------------------
CREATE OR REPLACE FUNCTION public.update_device_info(
  p_device_id text DEFAULT NULL,
  p_device_brand text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_device_platform text DEFAULT NULL,
  p_device_summary text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHENTICATED');
  END IF;

  UPDATE public.profiles
  SET
    device_id = COALESCE(p_device_id, device_id),
    device_brand = COALESCE(p_device_brand, device_brand),
    device_model = COALESCE(p_device_model, device_model),
    os_version = COALESCE(p_os_version, os_version),
    device_platform = COALESCE(p_device_platform, device_platform),
    device_summary = COALESCE(p_device_summary, device_summary),
    last_sign_in_at = now(),
    updated_at = now()
  WHERE id = auth.uid();

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_device_info TO authenticated;

-- 8c. CLAIM DEVICE WELCOME QUOTA (SHARED DEVICE POOL) ------------------------
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHENTICATED');
  END IF;

  IF p_device_id IS NULL OR length(trim(p_device_id)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'INVALID_DEVICE_ID');
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'PROFILE_NOT_FOUND');
  END IF;

  -- Kunci baris hardware di device_allowances
  SELECT * INTO v_existing_allow FROM public.device_allowances WHERE device_id = p_device_id FOR UPDATE;

  IF NOT FOUND THEN
    -- PERANGKAT BARU PERTAMA KALI: Buat pool kuota baru (10 untuk Google, 5 untuk Guest)
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
    -- PERANGKAT SUDAH TERDAFTAR: Akun apa pun di HP ini mengikuti sisa pool kuota perangkat
    v_pool_quota := v_existing_allow.remaining_quota;

    UPDATE public.device_allowances
    SET last_seen_at = now(),
        device_brand = COALESCE(p_device_brand, device_brand),
        device_model = COALESCE(p_device_model, device_model),
        os_version = COALESCE(p_os_version, os_version)
    WHERE device_id = p_device_id;

    -- Update profil user saat ini agar nilainya identik dengan sisa kuota hardware
    UPDATE public.profiles
    SET remaining_quota = v_pool_quota,
        device_id = p_device_id,
        device_brand = COALESCE(p_device_brand, device_brand),
        device_model = COALESCE(p_device_model, device_model),
        os_version = COALESCE(p_os_version, os_version),
        updated_at = now()
    WHERE id = v_uid;

    -- Catat initial sync di ledger jika akun baru
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
GRANT EXECUTE ON FUNCTION public.claim_device_welcome_quota(TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 9. STORAGE: bucket privat bukti bayar -------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('payment-proofs', 'payment-proofs', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "proofs_insert_own"  ON storage.objects;
DROP POLICY IF EXISTS "proofs_select_own"  ON storage.objects;
DROP POLICY IF EXISTS "proofs_select_admin" ON storage.objects;

-- Upload hanya ke folder <uid>/...
CREATE POLICY "proofs_insert_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "proofs_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "proofs_select_admin" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.is_admin());
