-- Add TikTok profile URL to barbers table.
ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS tiktok_url TEXT;
