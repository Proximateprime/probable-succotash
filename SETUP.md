# CoverTrack Setup Guide

## Quick Start (5 minutes)

### 1. Prerequisites
- Flutter 3.0+ installed → [flutter.dev/install](https://flutter.dev/docs/get-started/install)
- Supabase account (free) → [supabase.com](https://supabase.com)

### 2. Get Dependencies
```bash
cd "lawn softwhere"
flutter pub get
```

### 3. Create Supabase Project
1. Go to supabase.com and sign up
2. Create new project
3. Save your **Project URL** and **Anon Key** from Settings → API

### 4. Configure App Credentials
Edit `lib/constants/app_constants.dart`:

```dart
const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
const String supabaseAnonKey = 'eyJ...';  // Your anon key
const String stripePublishableKey = 'pk_test_...';  // Later for Stripe
```

### 5. Create Database Tables
In Supabase SQL Editor, paste and run:

```sql
-- Create users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT auth.uid(),
  email TEXT NOT NULL,
  display_name TEXT,
  role TEXT DEFAULT 'hobbyist' CHECK (role IN ('hobbyist', 'individual', 'corporate_admin', 'worker')),
  active_map_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Create properties table
CREATE TABLE properties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  latitude DECIMAL(10, 6),
  longitude DECIMAL(10, 6),
  acreage DECIMAL(10, 2),
  notes TEXT,
  orthomosaic_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Create tracking_sessions table
CREATE TABLE tracking_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_time TIMESTAMP NOT NULL,
  end_time TIMESTAMP,
  is_completed BOOLEAN DEFAULT FALSE,
  paths JSONB DEFAULT '[]',
  coverage_polygons JSONB DEFAULT '[]',
  coverage_percent DECIMAL(5, 2),
  total_distance_miles DECIMAL(10, 2),
  duration_seconds INTEGER,
  proof_pdf_url TEXT,
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_sessions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can view their own profile"
  ON users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON users FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can view their own properties"
  ON properties FOR SELECT
  USING (auth.uid() = owner_id);

CREATE POLICY "Users can create properties"
  ON properties FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can view their own sessions"
  ON tracking_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create sessions"
  ON tracking_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);
```

### 6. Set Up RLS (Row Level Security)

Enable RLS in Supabase console → Authentication → Policies ✓

### 7. Run App

**Device/Emulator Required**: GPS features need actual or simulated device

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device_id>

# Or let Flutter choose
flutter run
```

### 8. Test Using Demo Account
- Email: `test@example.com`
- Password: `test123456`

(Create it via sign-up first time)

## What Works Now

✅ User authentication (email/password)
✅ Property management (add/list/view)
✅ Real-time GPS tracking
✅ Coverage polygon generation
✅ PDF proof export
✅ Session history
✅ User tier system

## Known Limitations

- ⚠️ PDF export saves to memory (not device storage - enhancement needed)
- ⚠️ Stripe integration stubbed (needs fulfillment)
- ⚠️ Map visualization is placeholder (need map widget integration)

## Common Issues & Fixes

### GPS Permission Denied
```
Fix: Settings → App → Permissions → Location → Allow
```

### Supabase Connection Failed
```
Fix: Verify credentials in app_constants.dart
```

### Build Errors
```bash
flutter clean
flutter pub get
flutter run
```

### iOS Issues
```bash
cd ios
pod update
cd ..
flutter run
```

## Development Tips

### Hot Reload 
Press `r` in terminal (keeps app state)

### Full Restart
Press `R` in terminal (resets app state)

### Debug Logs
```
Look at terminal for logger output - all API calls are logged
```

### Disable GPS for Testing
Edit `lib/services/map_service.dart`:
```dart
// Hardcode test coordinates instead of GPS
latitude = 36.7783;
longitude = -119.4179;
```

## Next Steps

1. **Connect Mapbox** → Add map visualization to tracking screen
   - Package: `mapbox_gl: ^0.16.0`
   - Get API key from mapbox.com
   
2. **Implement Stripe** → Uncomment in `payment_service.dart`
   - Get publishable/secret keys from stripe.com
   - Test with Stripe test cards

3. **Add Worker Accounts** → Assign workers to properties
   - Update UI to manage assigned_workers list

4. **Export Enhancement** → Save PDFs to device
   - Use `path_provider` package
   - Implement share functionality

5. **Real-time Sync** → Add Supabase real-time listeners
   - Live coverage updates during tracking
   - Multi-user session collaboration

## Support

**Stuck?** Check:
- Is GPS enabled on device?
- Are API credentials correct?
- Is Dart SDK version 3.0+?
- Do database tables exist?

Try recreating the project:
```bash
flutter clean
rm -rf pubspec.lock
flutter pub get
flutter run
```

---

**Happy tracking! 🚀**
