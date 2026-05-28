-- ══════════════════════════════════════════════════════════════
-- Consolidated migration — adds every column the app needs.
-- Safe to run multiple times (all use IF NOT EXISTS / DEFAULT).
-- Paste this entire file into Supabase Dashboard › SQL Editor.
-- ══════════════════════════════════════════════════════════════

-- ── barbers table ─────────────────────────────────────────────
ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS location            TEXT,
  ADD COLUMN IF NOT EXISTS payment_number      TEXT,
  ADD COLUMN IF NOT EXISTS tiktok_url          TEXT,
  ADD COLUMN IF NOT EXISTS booking_code_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS booking_code        TEXT,
  ADD COLUMN IF NOT EXISTS menu_queue_type     TEXT    NOT NULL DEFAULT 'both';

CREATE INDEX IF NOT EXISTS idx_barbers_booking_code_enabled
  ON barbers (booking_code_enabled)
  WHERE booking_code_enabled = TRUE;

-- ── users table ───────────────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS fcm_token  TEXT,
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN NOT NULL DEFAULT FALSE;
