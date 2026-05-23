-- Allow Supabase Realtime to deliver payment_request events to clients.
-- The app uses custom auth (auth.uid() is always null), so RLS must be
-- disabled — otherwise Supabase Realtime silently drops every event.
alter table payment_requests disable row level security;

-- REPLICA IDENTITY FULL is required so that Realtime can filter events
-- by column value (e.g. barber_id = X) on UPDATE and DELETE as well.
alter table payment_requests replica identity full;
