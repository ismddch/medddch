-- Add prepayment feature flag to barbers
ALTER TABLE barbers ADD COLUMN IF NOT EXISTS prepayment_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Payment requests table
CREATE TABLE IF NOT EXISTS payment_requests (
  id          UUID          DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID          NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  chair_id    UUID          NOT NULL REFERENCES chairs(id)  ON DELETE CASCADE,
  barber_id   UUID          NOT NULL REFERENCES barbers(id) ON DELETE CASCADE,
  amount      DECIMAL(10,2),
  wallet_type TEXT          NOT NULL,
  photo_url   TEXT          NOT NULL,
  queue_type  TEXT          NOT NULL DEFAULT 'normal',
  status      TEXT          NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at  TIMESTAMPTZ   DEFAULT NOW()
);

ALTER TABLE payment_requests DISABLE ROW LEVEL SECURITY;

-- Payment manager account (safe upsert)
INSERT INTO users (name, phone, password, role)
SELECT 'مدير المدفوعات', '41126428', 'Pay28', 'payment'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE phone = '41126428');
