-- Add onboarding visibility flag for login-time tutorial behavior.
ALTER TABLE IF EXISTS public.profiles
ADD COLUMN IF NOT EXISTS has_seen_onboarding boolean NOT NULL DEFAULT true;

-- Backfill existing rows safely.
UPDATE public.profiles
SET has_seen_onboarding = COALESCE(has_seen_onboarding, true)
WHERE has_seen_onboarding IS NULL;
