-- Migration: Harden increment_active_maps RPC
-- Purpose: Prevent users from incrementing other users' counters via SECURITY DEFINER.

CREATE OR REPLACE FUNCTION increment_active_maps(user_id UUID)
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Forbidden: cannot modify another user''s map count';
  END IF;

  UPDATE profiles
  SET active_maps_count = active_maps_count + 1
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION increment_active_maps(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION increment_active_maps(UUID) TO authenticated;
