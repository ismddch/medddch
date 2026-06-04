-- Atomic function: inserts a queue entry and returns the assigned position.
-- Using a single DB transaction prevents two simultaneous callers from
-- receiving the same position number (race condition in client-side code).

CREATE OR REPLACE FUNCTION join_queue_atomic(
  p_barber_id          uuid,
  p_user_id            uuid,
  p_queue_type         text DEFAULT 'normal',
  p_selected_services  jsonb DEFAULT NULL,
  p_services_total     numeric DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_position integer;
BEGIN
  -- Lock the barber's queue rows to prevent concurrent inserts
  PERFORM 1 FROM queues WHERE barber_id = p_barber_id FOR UPDATE;

  -- Calculate next position
  SELECT COALESCE(MAX(position), 0) + 1
    INTO v_position
    FROM queues
   WHERE barber_id = p_barber_id;

  -- Insert the new queue entry
  INSERT INTO queues (barber_id, user_id, position, queue_type,
                      selected_services, services_total)
  VALUES (p_barber_id, p_user_id, v_position, p_queue_type,
          p_selected_services, p_services_total);

  RETURN v_position;
END;
$$;

-- Revoke direct table insert from anon/authenticated roles so all queue
-- inserts must go through this function (enforces the lock).
-- Remove this if other flows need direct table access.
-- REVOKE INSERT ON queues FROM anon, authenticated;
-- GRANT EXECUTE ON FUNCTION join_queue_atomic TO anon, authenticated;
