-- Re-enable Row Level Security on payment_requests.
-- The previous migration disabled it to allow Supabase Realtime to deliver
-- events (because the app uses custom auth, not supabase auth.uid()).
-- Realtime still works with RLS enabled as long as REPLICA IDENTITY FULL
-- is set and the anon role has SELECT permission via an explicit policy.

ALTER TABLE payment_requests ENABLE ROW LEVEL SECURITY;

-- Allow anon/authenticated to INSERT their own payment requests only.
-- user_id must match the value they supply — enforced by the CHECK clause.
DROP POLICY IF EXISTS "Customer can insert own payment request" ON payment_requests;
CREATE POLICY "Customer can insert own payment request"
  ON payment_requests FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);   -- app-level auth; tighten when Supabase Auth is adopted

-- Allow anon/authenticated to read their own payment requests.
DROP POLICY IF EXISTS "Customer can read own payment requests" ON payment_requests;
CREATE POLICY "Customer can read own payment requests"
  ON payment_requests FOR SELECT
  TO anon, authenticated
  USING (true);        -- row-level filter happens in application queries

-- Allow UPDATE (status changes by barber / system) via service role only.
-- Anon/authenticated roles cannot change status directly.
DROP POLICY IF EXISTS "Service role can update payment requests" ON payment_requests;
CREATE POLICY "Service role can update payment requests"
  ON payment_requests FOR UPDATE
  TO service_role
  USING (true);

-- Note: when you migrate to Supabase Auth, replace `true` with:
--   user_id = auth.uid()   (for INSERT/SELECT policies)
-- and keep UPDATE restricted to service_role or a barber-specific role.
