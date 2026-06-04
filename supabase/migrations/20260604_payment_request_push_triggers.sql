-- Enable pg_net extension (required to call HTTP endpoints from SQL triggers).
-- Already enabled on most Supabase projects; this is a no-op if so.
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ── Helper: call the queue-notifications Edge Function ───────────────────────
-- Replace the URL and key if your project ID changes.
CREATE OR REPLACE FUNCTION _notify_payment_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  payload jsonb;
BEGIN
  payload := jsonb_build_object(
    'type',       TG_OP,
    'table',      TG_TABLE_NAME,
    'record',     row_to_json(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
  );

  PERFORM net.http_post(
    url     := 'https://xwgwzhbpbwwgbedaxqec.supabase.co/functions/v1/queue-notifications',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('supabase.anon_key', true)
    ),
    body    := payload
  );

  RETURN NEW;
END;
$$;

-- ── Trigger: fire after INSERT (new booking request) ─────────────────────────
DROP TRIGGER IF EXISTS trg_payment_request_insert ON payment_requests;
CREATE TRIGGER trg_payment_request_insert
  AFTER INSERT ON payment_requests
  FOR EACH ROW
  EXECUTE FUNCTION _notify_payment_request();

-- ── Trigger: fire after UPDATE (approval / rejection) ────────────────────────
DROP TRIGGER IF EXISTS trg_payment_request_update ON payment_requests;
CREATE TRIGGER trg_payment_request_update
  AFTER UPDATE OF status ON payment_requests
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION _notify_payment_request();

-- ── Also ensure queues triggers exist (in case they were set up via dashboard) ─

CREATE OR REPLACE FUNCTION _notify_queue_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  payload jsonb;
BEGIN
  payload := jsonb_build_object(
    'type',       TG_OP,
    'table',      TG_TABLE_NAME,
    'record',     row_to_json(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
  );

  PERFORM net.http_post(
    url     := 'https://xwgwzhbpbwwgbedaxqec.supabase.co/functions/v1/queue-notifications',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('supabase.anon_key', true)
    ),
    body    := payload
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_queue_insert ON queues;
CREATE TRIGGER trg_queue_insert
  AFTER INSERT ON queues
  FOR EACH ROW
  EXECUTE FUNCTION _notify_queue_change();

DROP TRIGGER IF EXISTS trg_queue_update ON queues;
CREATE TRIGGER trg_queue_update
  AFTER UPDATE OF position ON queues
  FOR EACH ROW
  WHEN (OLD.position IS DISTINCT FROM NEW.position)
  EXECUTE FUNCTION _notify_queue_change();
