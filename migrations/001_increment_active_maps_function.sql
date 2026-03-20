-- Migration: Create increment_active_maps function
-- Purpose: Atomically increment active_maps_count for a user in profiles table
-- Usage: SELECT increment_active_maps('user-id-here'::UUID);

CREATE OR REPLACE FUNCTION increment_active_maps(user_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE profiles
  SET active_maps_count = active_maps_count + 1
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION increment_active_maps(UUID) TO authenticated;

-- Alternative: Create a Supabase RPC by running this in Supabase SQL editor
-- The function above needs to be called via rpc() from Dart client
