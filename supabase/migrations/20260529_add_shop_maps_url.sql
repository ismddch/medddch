-- Add Google Maps URL to shops table so admins can link the shop location.
ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS maps_url TEXT;
