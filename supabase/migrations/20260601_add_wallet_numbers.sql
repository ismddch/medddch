-- Per-wallet account numbers for each barber.
-- Stored as JSONB: {"Bankily":"12345","Sedad":"67890",...}
ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS wallet_numbers JSONB NOT NULL DEFAULT '{}';
