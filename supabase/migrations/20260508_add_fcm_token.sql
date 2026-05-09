-- Add FCM device token column to users table for push notifications.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;
