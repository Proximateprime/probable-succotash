-- Migration 002: Add exclusion_zones column to properties table
-- This column stores GeoJSON polygons as a JSONB array of exclusion zones (no-spray areas)

ALTER TABLE properties
ADD COLUMN exclusion_zones JSONB DEFAULT NULL;

-- Create index for faster queries on exclusion_zones
COMMENT ON COLUMN properties.exclusion_zones IS 'Array of GeoJSON Polygon objects representing no-spray exclusion zones';
