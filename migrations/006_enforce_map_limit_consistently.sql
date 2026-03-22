-- Migration: Authoritative map/property limit enforcement
-- Enforces limits consistently using profiles.active_maps_count + tier.

CREATE OR REPLACE FUNCTION public.tier_max_maps(input_tier TEXT)
RETURNS INTEGER AS $$
DECLARE
  normalized TEXT := lower(trim(coalesce(input_tier, 'hobbyist')));
BEGIN
  IF normalized IN ('corporate', 'solo_professional', 'premium_solo') THEN
    RETURN -1;
  END IF;

  IF normalized = 'individual' THEN
    RETURN 3;
  END IF;

  IF normalized IN ('hobby', 'hobbyist', 'individual_large_land') THEN
    RETURN 1;
  END IF;

  RETURN 1;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.check_map_limit()
RETURNS TABLE (
  allowed BOOLEAN,
  active_count INTEGER,
  max_maps INTEGER,
  tier TEXT,
  message TEXT
) AS $$
DECLARE
  current_uid UUID := auth.uid();
  current_count INTEGER;
  current_tier TEXT;
  tier_limit INTEGER;
BEGIN
  IF current_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT
    COALESCE(p.active_maps_count, 0),
    COALESCE(p.tier, 'hobbyist'),
    public.tier_max_maps(p.tier)
  INTO current_count, current_tier, tier_limit
  FROM public.profiles p
  WHERE p.id = current_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN tier_limit < 0 THEN TRUE
      ELSE current_count < tier_limit
    END AS allowed,
    current_count,
    tier_limit,
    current_tier,
    CASE
      WHEN tier_limit < 0 THEN 'Unlimited maps allowed.'
      WHEN current_count >= tier_limit THEN 'Max maps reached - upgrade?'
      ELSE 'Map available.'
    END AS message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.check_map_limit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_map_limit() TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_map_limit_on_property_insert()
RETURNS TRIGGER AS $$
DECLARE
  current_uid UUID := auth.uid();
  current_count INTEGER;
  current_tier TEXT;
  tier_limit INTEGER;
BEGIN
  IF current_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NEW.owner_id <> current_uid THEN
    RAISE EXCEPTION 'Forbidden: owner mismatch';
  END IF;

  SELECT p.active_maps_count, p.tier, public.tier_max_maps(p.tier)
  INTO current_count, current_tier, tier_limit
  FROM public.profiles p
  WHERE p.id = current_uid
  FOR UPDATE;

  IF current_count IS NULL THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  IF tier_limit >= 0 AND current_count >= tier_limit THEN
    RAISE EXCEPTION 'Map limit reached for tier % (%/%). Upgrade required.', current_tier, current_count, tier_limit;
  END IF;

  UPDATE public.profiles
  SET active_maps_count = active_maps_count + 1
  WHERE id = current_uid;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_enforce_map_limit_on_property_insert ON public.properties;
CREATE TRIGGER trg_enforce_map_limit_on_property_insert
BEFORE INSERT ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.enforce_map_limit_on_property_insert();
