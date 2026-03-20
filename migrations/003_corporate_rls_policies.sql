-- Migration 003: Corporate Features - RLS Policies for Team Management
-- This migration ensures proper RLS for corporate admin and worker roles

-- 1. Update properties RLS policy to allow corporate admins to see all their properties
-- (This should already be in place from previous migrations)

-- 2. Create policy for workers to see only assigned properties
-- Workers can view properties where auth.uid() is in the assigned_to array
CREATE POLICY "workers_see_assigned_properties"
ON properties
FOR SELECT
USING (
  auth.uid() = owner_id  -- Admins see their own properties
  OR auth.uid() = ANY(assigned_to)  -- Workers see assigned ones
);

-- 3. Create policy for corporate admins to manage assignments
-- Only admins can update assignments
CREATE POLICY "admins_can_update_assignments"
ON properties
FOR UPDATE
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);

-- 4. Ensure assigned_to column exists and is properly indexed for performance
-- ALTER TABLE properties ADD COLUMN assigned_to uuid[] DEFAULT ARRAY[]::uuid[]; -- Already added
CREATE INDEX idx_properties_assigned_to ON properties USING GIN (assigned_to);

-- 5. Document the data model for assigned_to field
-- COMMENT ON COLUMN properties.assigned_to IS 'Array of worker UUIDs assigned to this property. Workers in this array can view and work on this property.';
