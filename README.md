# CoverTrack - Precision Coverage Tracking

A production-ready Flutter mobile app for tracking precision coverage in lawn care, pest control, and small farming operations using GPS and Supabase.

## Features

- **GPS Tracking**: Real-time GPS tracking with accuracy feedback
- **Coverage Mapping**: Automatic polygon generation from GPS paths
- **Proof of Coverage**: Generate PDF proof documents with coverage metrics
- **Multi-Property Support**: Manage multiple properties with tier-based limits
- **User Roles**: Support for different user types (hobbyist, individual, corporate admin, worker)
- **Payment Integration**: Stripe integration for subscription management
- **Offline Support**: Local caching with SharedPreferences
- **Cloud Sync**: Supabase real-time database synchronization

## Tech Stack

- **Frontend**: Flutter 3.0+, Material Design 3
- **Backend**: Supabase (Auth, PostgreSQL, Real-time)
- **GPS**: Geolocator ^9.0.0
- **State Management**: Provider ^6.0.0
- **PDF Generation**: PDF ^3.10.0
- **Payment**: Stripe ^3.0.0 (stub ready)
- **Logging**: Logger ^1.3.0

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/                  # UI screens
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── property_detail_screen.dart
│   ├── tracking_screen.dart
│   └── export_screen.dart
├── services/                 # Business logic
│   ├── supabase_service.dart       # Database & auth
│   ├── map_service.dart            # GPS & geometry
│   └── payment_service.dart        # Payments
├── models/                   # Data models
│   ├── user_model.dart
│   ├── property_model.dart
│   └── session_model.dart
├── utils/                    # Utilities
│   ├── app_theme.dart
│   └── local_storage_service.dart
└── constants/
    └── app_constants.dart
```

## Setup Instructions

### Prerequisites
- Flutter 3.0+ ([install](https://flutter.dev/docs/get-started/install))
- Dart SDK (included with Flutter)
- Supabase account ([create free](https://supabase.com))

### Step 1: Clone & Install

```bash
cd lawn\ softwhere
flutter pub get
```

### Step 2: Configure Supabase

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Open [lib/constants/app_constants.dart](lib/constants/app_constants.dart)
3. Replace placeholders with your Supabase credentials:

```dart
const String supabaseUrl = 'YOUR_SUPABASE_URL';
const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

### Step 3: Database Schema

Create these tables in Supabase SQL editor:

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  display_name TEXT,
  role TEXT DEFAULT 'hobbyist',
  active_map_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Properties table
CREATE TABLE properties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  latitude DECIMAL(10, 6),
  longitude DECIMAL(10, 6),
  acreage DECIMAL(10, 2),
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Tracking sessions table
CREATE TABLE tracking_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  property_id UUID NOT NULL REFERENCES properties(id),
  user_id UUID NOT NULL REFERENCES users(id),
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
```

### Step 4: Run

```bash
# Run on Android/iOS device or emulator
flutter run

# Release build
flutter build apk    # Android
flutter build ios    # iOS
```

### Windows Test Workaround (spaces in user profile path)

If `flutter test` fails with a path like `C:\Users\First Last` being split,
run tests through the project script, which uses a workspace-local pub cache:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_flutter_test.ps1
```

Optional: run a specific test file for a quick check:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_flutter_test.ps1 test\widget_test.dart
```

## Key Screens

### Login Screen
- Email/password authentication
- Sign up option
- Error handling

### Home Screen
- List of user's properties
- Add new property dialog
- User tier information
- Navigation to property details

### Property Detail Screen
- Property information display
- List of tracking sessions
- Start tracking button
- Session history

### Tracking Screen ⭐
- **Core feature**: Real-time GPS tracking
- Live latitude, longitude, accuracy display
- Adjustable swath width (5-100 ft)
- Elapsed time counter
- GPS path points visualization
- Stop & export button

### Export Screen
- Coverage statistics summary
- PDF generation with proof details
- Distance and coverage metrics
- Export confirmation

## Architecture

### Clean Architecture Layers

1. **Presentation Layer** (screens/)
   - Flutter widgets & screens
   - User interaction handling
   - Provider for state management

2. **Business Logic Layer** (services/)
   - SupabaseService: Database & auth
   - MapService: GPS & geospatial calculations
   - PaymentService: Stripe integration

3. **Data Layer** (models/)
   - Data models with JSON serialization
   - Type-safe data structures
   - Business logic methods

4. **Utilities** (utils/)
   - Theme & styling
   - Local storage wrapper
   - Logging utilities

### Singleton Services

All services use singleton pattern for consistent state:

```dart
class MyService {
  static final _instance = MyService._internal();
  factory MyService() => _instance;
  MyService._internal();
}
```

## Data Models

### UserProfile
- Roles: hobbyist, individual, corporate_admin, worker
- Tier limits: 1/3/unlimited active maps
- Methods: canAddNewMap(), isWorker(), isAdmin()

### Property
- Owner assignment
- Geolocation (lat/lon)
- Acreage tracking
- Orthomosaic URL support

### TrackingSession
- GPS path tracking (latitude, longitude, accuracy, timestamp)
- Coverage polygons (offset from GPS paths by swath width)
- Coordinates, coverage percent, distance

## GPS & Coverage Calculation

The MapService provides:

- **GPS Tracking**: Position stream with configurable intervals (default: 3 seconds)
- **Coverage Polygon**: Offset buffer polygon from GPS path by swath width
- **Distance Calculation**: Haversine formula for accurate distance between points
- **Bearing Calculation**: Great circle bearing between GPS points

## Authentication

- **Provider**: Supabase Auth
- **Methods**: Email/password, Google OAuth (ready)
- **Session**: Persistent JWT tokens

## Offline Support

SharedPreferences stores:
- Current user ID
- Default swath width preference
- Local session cache (optional enhancement)

## Error Handling

All services include:
- Try/catch error handling
- Logger output for debugging
- User-friendly error messages
- Recovery options

## Deployment

### Android
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS
```bash
flutter build ios --release
# Output: build/ios/iphoneos/Runner.app
```

### Play Store
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/
```

## Troubleshooting

### GPS not activating
- Check location permissions in mobile settings
- Ensure device has GPS enabled
- Verify geolocator plugin configuration

### Supabase connection error
- Verify API credentials in app_constants.dart
- Check Supabase project status
- Ensure internet connection

### Build errors
- Run `flutter clean && flutter pub get`
- Check Dart SDK version (3.0+)
- Verify no circular imports

## Contributing

1. Create feature branch: `git checkout -b feature/new-feature`
2. Commit changes: `git commit -am 'Add feature'`
3. Push to branch: `git push origin feature/new-feature`
4. Open pull request

## License

MIT License - see LICENSE file

## Support

For issues or features: create an issue on GitHub

---

**Version**: 1.0.0  
**Last Updated**: 2024
