# Corporate Features - SprayMap Pro

## Overview
SprayMap Pro now includes comprehensive corporate team management features, allowing corporate admins to manage workers and assign properties to their team members.

## Architecture

### New Components

#### 1. **team_overview_screen.dart**
Central hub for corporate admins to manage all properties and team assignments.

**Features:**
- Dashboard with summary statistics (total properties, team members, assigned properties)
- List of all company properties with assigned workers displayed
- Inline worker assignment management with dialog UI
- Quick navigation to individual property management
- Real-time sync with Supabase

**Summary Cards:**
- Total Properties: Shows count of all properties owned
- Team Members: Shows count of available workers  
- Assigned: Shows count of properties with at least one assigned worker

**Property Cards:**
- Property name and address
- List of assigned workers (displayed as blue chips)
- "Manage Workers" button to update assignments
- Edit button for quick access to property details

#### 2. **Assignment Management Dropdown/Dialog**
Modal dialog for managing worker assignments per property.

**UI:**
- Shows property name at top
- FilterChips for each available worker
- Multi-select interface (can assign multiple workers)
- Save and Cancel buttons
- Only appears for corporate_admin role

**Behavior:**
- Loads all workers from database
- Shows which workers are currently assigned (selected state)
- Allows adding/removing workers with single tap
- Persists changes to Supabase on Save
- Shows loading state during save
- Displays success/error messages

### Files Created/Modified

#### New Files
1. **lib/screens/team_overview_screen.dart** - Corporate admin team management dashboard
2. **migrations/003_corporate_rls_policies.sql** - Enhanced RLS policies for team access

#### Modified Files
1. **lib/screens/home_screen.dart**
   - Added Team Overview button in AppBar (visible for corporate_admin only)
   - Added Team Overview banner on home screen
   - Imports team_overview_screen.dart

2. **lib/services/supabase_service.dart**
   - Already has `fetchUserProperties()` with role-based filtering
   - Already has `updatePropertyAssignments()` method
   - Already has `fetchAllUsers()` method
   - Already has `fetchPropertySessions()` method

3. **lib/screens/property_detail_screen.dart**
   - Already has "Assign to Workers" UI for corporate admins
   - Shows FilterChips for worker selection
   - Saves assignments with _saveAssignments()

## User Workflows

### Corporate Admin Workflow

#### 1. View Team Dashboard
1. Open SprayMap Pro
2. Navigate to home screen
3. Click group icon (👥) in AppBar OR "Team Overview" button on home screen
4. See all properties with assigned workers

#### 2. Assign Workers to Property (from Team Overview)
1. On Team Overview screen
2. Find property card
3. Click "Manage Workers" button
4. Dialog opens showing all available workers
5. Select/deselect workers (FilterChip toggle)
6. Click "Save"
7. Assignments persist to database

#### 3. Assign Workers to Property (from Property Detail)
1. Open specific property
2. Scroll to "Assign to Workers" card
3. Toggle workers with FilterChips
4. Click "Save Assignments" button
5. Assignments persist to database

#### 4. Monitor Team Activity
- Team Overview shows quick stats:
  - How many properties are assigned vs unassigned
  - Total team members
  - How many workers are in system

### Worker Workflow

#### 1. View Assigned Properties
1. Open SprayMap Pro
2. Navigate to home screen
3. See only properties where they are assigned
4. Filtering happens automatically based on auth.uid() in assigned_to array

#### 2. Work on Assigned Property
1. Click on any assigned property
2. Can start tracking, add maps, export PDFs
3. Cannot see unassigned properties
4. Cannot modify property details (worker is read-only)

## Data Model

### Property Assignments
```
properties table:
├── id (uuid, primary key)
├── owner_id (uuid, FK to profiles) - Corporate admin who owns it
├── name (text)
├── address (text)
├── assigned_to (uuid[], NEW FIELD) - Array of worker IDs
├── map_geojson (jsonb)
├── orthomosaic_url (text)
├── exclusion_zones (jsonb)
└── created_at (timestamp)
```

**assigned_to Field:**
- Type: `uuid[]` (array of UUIDs)
- Default: Empty array or NULL
- Indexed with GIN index for performance
- Stores UUIDs of workers assigned to each property
- Referenced in RLS policies

### User Roles
```
profiles table:
├── id (uuid)
├── email (text)
├── role (text) - 'corporate_admin' or 'worker'
├── tier (text) - 'hobby', 'solo', 'premium', etc.
├── active_maps_count (int)
└── created_at (timestamp)
```

**Role Hierarchy:**
- **corporate_admin**: Can create properties, assign workers, view all team properties
- **worker**: Can view only assigned properties, cannot modify assignments or create properties
- **hobbyist/solo/premium**: Individual users (cannot assign workers)

## RLS Policies (Security)

### Policies for Properties Table

#### Corporate Admin Policies
1. **Can select all own properties**
   ```sql
   auth.uid() = owner_id
   ```

2. **Can update own properties and assignments**
   ```sql
   auth.uid() = owner_id
   ```

#### Worker Policies
1. **Can select assigned properties**
   ```sql
   auth.uid() = ANY(assigned_to)
   ```

2. **Cannot update assigned_to (read-only)**
   - Workers cannot modify who is assigned to properties
   - Only corporate admins can update assignments

### How It Works
- Workers automatically see only properties in their assigned_to array
- Corporate admins see only their owner_id properties
- No cross-company visibility
- Database-level enforcement (not just UI)

## Database Schema Migrations

### Migration 003: Corporate RLS Policies
Execute in Supabase SQL Editor:

```sql
-- Create policy for workers to see assigned properties
CREATE POLICY "workers_see_assigned_properties"
ON properties
FOR SELECT
USING (
  auth.uid() = owner_id
  OR auth.uid() = ANY(assigned_to)
);

-- Create policy for admins to manage assignments
CREATE POLICY "admins_can_update_assignments"
ON properties
FOR UPDATE
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);

-- Create index for performance
CREATE INDEX idx_properties_assigned_to ON properties USING GIN (assigned_to);
```

## Data Flow Diagrams

### Assignment Save Flow
```
Team Overview Screen
    ↓ (Click "Manage Workers")
Assignment Dialog
    ↓ (User selects workers + clicks Save)
_updateAssignments() method
    ↓
SupabaseService.updatePropertyAssignments()
    ↓
PostgreSQL: UPDATE properties SET assigned_to = [...] WHERE id = ?
    ↓ (RLS enforces: auth.uid() = owner_id)
✓ Success or ✗ Denied
    ↓
Local state updated
    ↓
UI re-renders with new worker list
```

### Property Visibility Flow (Worker Login)
```
Home Screen _loadData()
    ↓
SupabaseService.fetchUserProperties(userId, userRole='worker')
    ↓
Check: Is role 'worker'?
    ↓ YES
Fetch ALL properties from DB
    ↓
Client-side filter: WHERE userId IN property.assigned_to
    ↓
Return filtered list
    ↓
OR (Optimized: Use RLS at DB level)
    SELECT * FROM properties WHERE auth.uid() = ANY(assigned_to)
    ↓
Return only assigned properties
```

## API Reference

### SupabaseService Methods

#### updatePropertyAssignments()
```dart
Future<void> updatePropertyAssignments({
  required String propertyId,
  required List<String> assignedTo,
}) async
```
- **Purpose**: Update the assigned_to array for a property
- **Parameters**:
  - propertyId: UUID of property to update
  - assignedTo: List of worker UUIDs to assign
- **Returns**: Completes on success, throws on RLS violation or error
- **RLS Check**: Enforces auth.uid() = property.owner_id

#### fetchUserProperties()
```dart
Future<List<Property>> fetchUserProperties(
  String userId,
  {required String userRole}
) async
```
- **Purpose**: Fetch properties visible to user based on role
- **Parameters**:
  - userId: UUID of current user
  - userRole: 'corporate_admin' or 'worker'
- **Returns**: List of properties user can access
- **Logic**:
  - Corporate Admin: owner_id = userId
  - Worker: userId in assigned_to array
- **Implementation**: Client-side filtering (can be optimized with improved RLS)

#### fetchAllUsers()
```dart
Future<List<UserProfile>> fetchAllUsers() async
```
- **Purpose**: Fetch all user profiles
- **Returns**: List of all users in system
- **Note**: Used for worker selection dropdown
- **Todo**: Consider adding filter for workers in same organization

## Installation & Setup

### 1. Add to pubspec.yaml
(Already included in existing dependencies)

### 2. Execute Database Migration
```sql
-- Run the full migration from migrations/003_corporate_rls_policies.sql
-- in Supabase SQL Editor
```

### 3. Import team_overview_screen in home_screen
(Already done)

### 4. Test Corporate Features
1. Create corporate_admin user in Supabase
2. Create worker users in Supabase
3. Login as corporate admin
4. Create properties
5. Assign workers
6. Login as worker
7. Verify they see only assigned properties

## Feature Checklist

✅ **Implemented:**
- [x] Team Overview screen with dashboard
- [x] Corporate admin can view all properties
- [x] Corporate admin can assign workers to properties
- [x] Assignment management dialog
- [x] Worker filtering (client-side via fetchUserProperties)
- [x] Worker sees only assigned properties
- [x] Worker role detection and UI customization
- [x] RLS policy definitions documented
- [x] Integration with existing property detail screen
- [x] Navigation from home screen to team overview
- [x] Real-time sync with Supabase
- [x] Error handling and user feedback

⏳ **Optional Enhancements (Phase 2):**
- [ ] Server-side RLS optimization (filter at DB level)
- [ ] Bulk assignment of workers to properties
- [ ] Worker availability/status tracking
- [ ] Team member management (add/remove users)
- [ ] Role-based worker groups
- [ ] Assignment scheduling (active dates)
- [ ] Worker time tracking and reports
- [ ] Push notifications for assignments
- [ ] Audit log for all assignment changes
- [ ] Worker performance analytics

## Testing Guide

### Test Case 1: Corporate Admin Assignment
1. Login as corporate_admin
2. Create property "Test Property 1"
3. Go to Team Overview
4. Click "Manage Workers" on property
5. Select 2 workers
6. Click Save
7. Verify workers appear as chips on property card
8. Refresh page
9. Verify assignments persisted

### Test Case 2: Worker Property Visibility
1. Create property as corporate_admin
2. Assign "worker_1" to property
3. Assign "worker_2" to different property
4. Login as "worker_1"
5. Verify "Test Property 1" appears
6. Verify other property does NOT appear
7. Click on visible property
8. Verify can view details (tracking, maps, etc.)

### Test Case 3: RLS Enforcement
1. Login as worker_1
2. Attempt to access database directly (if possible in dev)
3. Verify can only SELECT own assigned properties
4. Verify cannot UPDATE properties
5. Verify cannot DELETE properties

### Test Case 4: Unassigned Properties
1. Create property without assigning workers
2. Login as any worker
3. Verify property does NOT appear in their list
4. Login as corporate_admin
5. Verify property DOES appear

## Troubleshooting

### Issue: Worker doesn't see assigned property
**Cause:** RLS policy not applied or assigned_to not updated
**Solution:** 
- Check Supabase: SELECT * FROM properties WHERE id = ?
- Verify assigned_to contains worker's UUID
- Check RLS policies are created in Supabase SQL Editor
- Refresh app

### Issue: Corporate admin can't see Team Overview button
**Cause:** Role not set correctly or cached
**Solution:**
- Verify user profile has role = 'corporate_admin'
- Clear app cache / restart
- Check profiles table in Supabase

### Issue: Assignment dialog doesn't show workers
**Cause:** No workers in system or fetchAllUsers() failing
**Solution:**
- Create worker users first
- Set their role to 'worker'
- Check network request in browser DevTools
- Check Supabase logs

### Issue: Worker filtering not working (showing all properties)
**Cause:** Client-side filtering issue or auth.uid() not set
**Solution:**
- Verify currentUserId is set in SupabaseService
- Check assigned_to array in database is correct
- Review fetchUserProperties() logic

## Security Considerations

1. **RLS is Database-Level Enforcement**
   - Even if UI filtering fails, database enforces access control
   - Workers cannot see properties they're not assigned to
   - Cross-company data leakage prevented

2. **Assignment Updates Restricted**
   - Only corporate admins (owner_id = auth.uid()) can update assignments
   - Workers cannot modify assigned_to array

3. **Role-Based Access**
   - Different code paths for different roles
   - Corporate admin sees Team Overview option
   - Workers don't see assignment management

4. **Audit Trail**
   - All Supabase operations are timestamped
   - Created_at and Updated_at tracked
   - Future: Add audit_log table for compliance

## Performance Optimization

### Current State
- Client-side filtering of properties (fetchUserProperties)
- All workers fetched for assignment UI
- Simple array containment check

### Recommended Optimizations (Phase 2)
- Use RLS at database level instead of client-side filtering
- Pagination for large property lists
- Worker list pagination/search
- Cache team member list in local storage
- Limit assignment dialog to recent properties

## References
- [Flutter Provider docs](https://pub.dev/packages/provider)
- [Supabase Row Level Security](https://supabase.com/docs/guides/realtime/security-rls)
- [PostgreSQL Array Types](https://www.postgresql.org/docs/current/arrays.html)
- [GIN Indexes](https://www.postgresql.org/docs/current/gin-intro.html)
