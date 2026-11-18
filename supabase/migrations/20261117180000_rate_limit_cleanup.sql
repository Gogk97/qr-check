-- ============================================================================
-- RATE LIMIT HOUSEKEEPING
-- ----------------------------------------------------------------------------
-- Masalah: rpc_rate_limits menyimpan 1 baris per (user, action, bucket waktu).
-- Dengan 4 action dan bucket per jam, satu user aktif menghasilkan ~96 baris/hari
-- (~4 MB/user/tahun). Tanpa pembersihan, kuota DB 500 MB habis di ~115 user/tahun.
--
-- Solusi: check_rate_limit() membersihkan bucket lama:
--   1. deterministik untuk user yang sedang aktif (selalu)
--   2. sapuan global probabilistik (2%) untuk user yang berhenti aktif
-- Tanpa pg_cron, tanpa Edge Function tambahan.
-- ============================================================================

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

  -- (1) Buang bucket lama milik user ini: cukup simpan 2 jam terakhir.
  DELETE FROM public.rpc_rate_limits
  WHERE user_id = v_uid
    AND window_start < v_bucket - interval '2 hours';

  -- (2) Sapuan global sesekali untuk user yang sudah tidak aktif.
  IF random() < 0.02 THEN
    DELETE FROM public.rpc_rate_limits
    WHERE window_start < now() - interval '2 hours';
  END IF;

  RETURN v_hits <= GREATEST(p_max, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.check_rate_limit(text, int, interval)
  FROM PUBLIC, anon, authenticated;

-- Helper manual/opsional: panggil dari SQL Editor atau cron eksternal.
CREATE OR REPLACE FUNCTION public.purge_rate_limits(p_older_than INTERVAL DEFAULT interval '2 hours')
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM public.rpc_rate_limits WHERE window_start < now() - p_older_than;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_rate_limits(interval) FROM PUBLIC, anon, authenticated;

-- Monitoring: ukuran per tabel (untuk cek berkala sebelum kuota penuh).
CREATE OR REPLACE VIEW public.db_usage AS
SELECT
  c.relname                              AS table_name,
  pg_total_relation_size(c.oid)          AS total_bytes,
  pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty,
  c.reltuples::bigint                    AS est_rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

REVOKE ALL ON public.db_usage FROM anon, authenticated;
