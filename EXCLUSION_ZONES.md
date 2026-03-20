# Exclusion Zones Feature - SprayMap Pro

## Overview
The exclusion zones feature allows lawn care professionals to draw and save "no-spray" areas on their property maps. These zones represent areas where pesticides, fertilizers, or other spray treatments should not be applied (e.g., water sources, children's play areas, protected vegetation).

## Architecture

### New Files Created

#### 1. **lib/models/exclusion_zone_model.dart**
Represents a single exclusion zone polygon.

```dart
class ExclusionZone {
  final String id;                    // Unique identifier
  final List<LatLng> vertices;       // Polygon vertices (lat/lng coordinates)
  final DateTime createdAt;
  final String? notes;               // Optional description
}
```

**Key Methods:**
- `toGeoJSON()` - Converts to GeoJSON Polygon format for storage
- `fromGeoJSON()` - Creates ExclusionZone from GeoJSON
- `toJson()/fromJson()` - Serialization for database

#### 2. **lib/screens/exclusion_zone_draw_screen.dart**
Full-screen drawing interface for creating exclusion zones.

**Features:**
- Interactive flutter_map with OSM tiles
- Finger-drawing interface (tap to add points)
- Real-time polygon visualization
- Numbered point markers for visual feedback
- Completed zones displayed as semi-transparent red overlays
- Current drawing shown in orange

**Drawing Tools:**
- **Point Addition**: Tap on map to add vertices
- **Undo**: Removes last point (blue button, bottom-left)
- **Finish Polygon**: Completes current zone (green button, visible during drawing)
- **Clear All**: Removes all zones
- **Save Zones**: Saves to Supabase after validation (requires minimum 3 points)
- **Cancel**: Discards changes

**Validation:**
- Minimum 3 vertices required per polygon
- Automatically closes polygon by repeating first vertex

#### 3. **lib/models/property_model.dart** (Updated)
Added `exclusion_zones` field to Property model.

```dart
class Property {
  // ... existing fields ...
  final List<Map<String, dynamic>>? exclusionZones;  // JSONB array of GeoJSON Polygons
  
  bool hasExclusionZones() => exclusionZones != null && exclusionZones!.isNotEmpty;
}
```

#### 4. **lib/services/supabase_service.dart** (Updated)
New method to persist exclusion zones.

```dart
Future<void> updateExclusionZones({
  required String propertyId,
  required List<Map<String, dynamic>> zones,
}) async
```

Saves zones as JSONB array in properties table. Follows RLS pattern (owner-only access).

#### 5. **lib/screens/property_detail_screen.dart** (Updated)
- Added "Draw Exclusion Zones" button (red, visible when map imported)
- Shows count of configured zones
- Integrated drawing screen callback
- Saves zones to Supabase on completion

### Database Schema

#### Migration File: **migrations/002_add_exclusion_zones.sql**
```sql
ALTER TABLE properties
ADD COLUMN exclusion_zones JSONB DEFAULT NULL;
```

**To apply migration in Supabase:**
1. Open Supabase SQL Editor
2. Execute migration SQL
3. Verify column added: `SELECT * FROM properties LIMIT 1;`

**Data Format (GeoJSON Polygon):**
```json
{
  "type": "Polygon",
  "coordinates": [
    [
      [-122.4194, 37.7749],
      [-122.4185, 37.7760],
      [-122.4175, 37.7755],
      [-122.4194, 37.7749]
    ]
  ]
}
```

## User Workflow

### Drawing Exclusion Zones

1. **Navigate to Property:**
   - Open property from home screen
   - Verify map is already imported

2. **Open Drawing Screen:**
   - Tap red "Draw Exclusion Zones" button
   - Full-screen map opens at property location

3. **Draw Zone:**
   - Tap on map to add vertices
   - Numbers appear on each point
   - Zone outline appears in orange
   - Continue tapping to create polygon boundary

4. **Finish Zone:**
   - For each zone, tap green "✓" button when done
   - Zone turns red (completed state)
   - Zone count increments
   - Can draw multiple zones

5. **Manage Zones:**
   - **Undo Last Point**: Blue undo button removes last vertex from current zone
   - **Clear All Zones**: Removes all completed and current zones
   - **Cancel**: Exit without saving

6. **Save Zones:**
   - Review all red zones on map
   - Tap "Save Zones" button
   - Zones persist to database
   - Property detail screen shows count
   - Bottom sheet shows success message

### Viewing Saved Zones

On Property Detail screen:
- If zones exist: "✓ 3 zones configured" displayed under "Draw Exclusion Zones" button
- Color: Red text matching the zone overlay color
- Shows current zone count

## Dependencies Added

```yaml
dependencies:
  flutter_map: ^6.0.0   # Interactive map widget with drawing support
  latlong2: ^0.9.0     # Geographic coordinate math (latitude/longitude)
```

**Version Compatibility:**
- Flutter: >=3.0.0
- flutter_map v6 introduces new API (children instead of layers)
- latlong2 provides LatLng type for coordinate pairs

## Implementation Details

### Coordinate System
- **Storage**: WGS84 (lat/lng coordinates)
- **Display**: OpenStreetMap tiles (Web Mercator projection)
- **Format**: GeoJSON standard for interoperability

### Drawing Touch Handling
```dart
void _onMapTap(TapPosition tapPosition, LatLng point) {
  // tapPosition: screen coordinates
  // point: already converted to lat/lng by flutter_map
  _currentPolygon.add(point);  // Add to polygon
}
```

Map controller automatically handles screen-to-geo coordinate conversion.

### Polygon Closure
- User draws N points
- On "Finish Polygon", if last point ≠ first point, first point is added again
- Creates closed polygon for proper geospatial operations

### State Management
- Uses StatefulWidget for _ExclusionZoneDrawScreenState
- Local list tracking: `_completedZones`, `_currentPolygon`
- Callback pattern: `onZonesSaved(List<ExclusionZone>)` to parent screen

## Data Flow

```
Property Detail Screen
    ↓ (tap "Draw Exclusion Zones")
Exclusion Zone Draw Screen
    ↓ (draw polygons via map taps)
  Local State (_completedZones)
    ↓ (tap "Save Zones")
ExclusionZone Model → GeoJSON Conversion
    ↓
Supabase Service.updateExclusionZones()
    ↓
PostgreSQL: properties.exclusion_zones (JSONB)
    ↓
Property updated in Property Detail Screen
    ↓
Display zone count + re-render
```

## Future Enhancements

### Phase 2 (Roadmap)
1. **Tier-Based Limits**: 
   - Hobbyist: 1 zone max
   - Solo Pro: 10 zones max
   - Premium/Corporate: Unlimited

2. **Tracking Integration**:
   - Warn when GPS enters zone during tracking
   - Exclude zones from coverage fill (don't count as sprayed)
   - Log zone entries in session data

3. **Visualization on Tracking Map**:
   - Show zones as red overlays on tracking session map
   - Real-time status: "In zone" vs "Outside zone"

4. **Zone Management UI**:
   - Edit existing zones (rename, reposition)
   - Delete individual zones
   - Merge overlapping zones
   - Set zone properties (type: water, vegetation, etc.)

5. **Export/Import**:
   - Export zones as GeoJSON file
   - Import from previous properties
   - Share zones with team members

6. **Analytics**:
   - Show skipped/excluded area percentage
   - Track zone compliance over time
   - Reports on avoided areas

## Testing Checklist

- [ ] Install dependencies: `flutter pub get`
- [ ] Run app: `flutter run -d chrome` (web) or device
- [ ] Navigate to property with map imported
- [ ] Tap "Draw Exclusion Zones" button
- [ ] Draw 2-3 test zones on map
- [ ] Verify zones display in red
- [ ] Test undo button (removes last point)
- [ ] Test finish polygon (zones change from orange to red)
- [ ] Test clear all (resets everything)
- [ ] Tap Save Zones (should succeed)
- [ ] Navigate away and back to property
- [ ] Verify zones persist and count displays
- [ ] Check Supabase database for JSONB data

## Troubleshooting

**Issue: "Draw Exclusion Zones" button disabled**
- Solution: Import a map first using "Add New Map" button

**Issue: Map not centered on property**
- Cause: No map coordinates found in property.mapGeojson
- Solution: Map defaults to San Francisco; import property map first

**Issue: Cannot finish polygon**
- Cause: Less than 3 points
- Solution: Add at least 3 points and try again

**Issue: Zones not saving**
- Check: Is zone count showing? Are you authenticated?
- Check Supabase: Verify exclusion_zones column exists on properties table

**Issue: flutter_map compile errors**
- Solution: Ensure flutter_map ^6.0.0 is installed (`flutter pub get`)
- Verify: API uses `children` (v6) not `layers` (v5)

## API Reference

### ExclusionZone Model

```dart
// Create from scratch
ExclusionZone(
  id: DateTime.now().toString(),
  vertices: [LatLng(37.7749, -122.4194), ...],
  createdAt: DateTime.now(),
  notes: "Water feature"
)

// Convert to GeoJSON for storage
final geoJson = zone.toGeoJSON();  
// {"type": "Polygon", "coordinates": [[...]], ...}

// Convert from stored GeoJSON
final zone = ExclusionZone.fromGeoJSON(geoJson);
```

### SupabaseService

```dart
final supabase = context.read<SupabaseService>();

// Update exclusion zones
await supabase.updateExclusionZones(
  propertyId: 'prop-123',
  zones: [geoJsonPolygon1, geoJsonPolygon2],
);
```

### ExclusionZoneDrawScreen

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ExclusionZoneDrawScreen(
      property: myProperty,
      onZonesSaved: (zones) {
        // Handle saved zones
        // Convert to GeoJSON and save to DB
      },
    ),
  ),
);
```

## References

- [flutter_map Documentation](https://github.com/fleaflet/flutter_map)
- [GeoJSON Specification](https://geojson.org/)
- [WGS84 Coordinate System](https://en.wikipedia.org/wiki/World_Geodetic_System)
- [latlong2 Package](https://pub.dev/packages/latlong2)
