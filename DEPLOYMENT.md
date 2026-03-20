# Deployment & Checklist

## Fast Cloudflare Deploy (GitHub Actions)

If the browser uploader hangs, use the GitHub deploy pipeline in [.github/workflows/cloudflare-pages.yml](.github/workflows/cloudflare-pages.yml).

### One-Time Setup
- Create or confirm a Cloudflare Pages project (example name: spraymap-pro).
- Push this repo to GitHub.
- In GitHub, open Settings -> Secrets and variables -> Actions and add:
  - CLOUDFLARE_API_TOKEN
  - CLOUDFLARE_ACCOUNT_ID
  - CLOUDFLARE_PAGES_PROJECT

### Deploy
- Push to main branch, or run the workflow manually from Actions.
- The workflow builds Flutter web and deploys build/web automatically.

## Pre-Launch Checklist

### Configuration
- [ ] Supabase project URL configured in `app_constants.dart`
- [ ] Supabase Anon Key configured in `app_constants.dart`
- [ ] Database tables created (see SETUP.md)
- [ ] RLS policies enabled on all tables
- [ ] Email/password auth enabled in Supabase

### GPS & Location (Mobile)
- [ ] AndroidManifest.xml has location permissions
- [ ] Info.plist has NSLocationWhenInUseUsageDescription
- [ ] GPS tested on real device (emulator GPS can be unreliable)
- [ ] Accuracy threshold validated (currently 5 meters)

### API Keys & Secrets
- [ ] No API keys committed to version control
- [ ] Use build flavors for dev/staging/prod credentials
- [ ] Stripe public key added for payment feature
- [ ] Mapbox token added when map integration begins

### App Store & Play Store
- [ ] Privacy policy written (GDPR, location data)
- [ ] App icon created (1024x1024 PNG)
- [ ] Screenshots prepared for store listing
- [ ] Description & keywords optimized
- [ ] Developer account created (Apple, Google)
- [ ] Billing setup complete

## Build & Release Process

### Android Release

```bash
# Build signed APK
flutter build apk --release

# Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# Output locations:
# APK: build/app/outputs/flutter-apk/app-release.apk
# AAB: build/app/outputs/bundle/release/app-release.aab
```

### iOS Release

```bash
# Build release IPA
flutter build ios --release

# Prepare for TestFlight/App Store
# In Xcode:
# 1. Set team ID
# 2. Increment build number
# 3. Archive
# 4. Upload to App Store Connect

# Or use fastlane:
cd ios
fastlane beta  # to TestFlight
fastlane release  # to App Store
```

### Release Notes Template

```
Version 1.0.0 - Initial Release

✨ Features:
- Real-time GPS tracking for coverage mapping
- Multi-property management
- Proof of coverage PDF export
- User tier system (hobbyist, individual, corporate)
- Offline support

🐛 Bug Fixes:
- Fixed GPS accuracy filtering

📊 Improvements:
- Improved app startup performance
- Better error messages

🙏 Special Thanks:
[Contributors]
```

## Production Configuration

### Environment Variables
Create a config for production:

```dart
// lib/constants/app_constants.dart - requires manual entry
const String environment = 'production';
const String supabaseUrl = 'https://xxxx.supabase.co';
const String supabaseAnonKey = 'eyJxx...';
const String stripePublishableKey = 'pk_live_xxx';
```

### Supabase Production Setup

```sql
-- 1. Enable RLS on all tables (MANDATORY)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_sessions ENABLE ROW LEVEL SECURITY;

-- 2. Create comprehensive read policies
CREATE POLICY "users_read_own"
  ON users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "properties_read_own"
  ON properties FOR SELECT
  USING (auth.uid() = owner_id);

CREATE POLICY "sessions_read_own"
  ON tracking_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- 3. Create insert policies with validation
CREATE POLICY "properties_create"
  ON properties FOR INSERT
  WITH CHECK (
    auth.uid() = owner_id
    AND (SELECT role FROM users WHERE id = auth.uid()) != 'worker'
  );

-- 4. Create backups
-- Supabase → Settings → Backups → Enable automatic daily
```

### Stripe Integration (if ready)

```dart
// Uncomment in lib/services/payment_service.dart

Future<String> startCheckout(String priceId) async {
  try {
    final result = await _stripe.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'CoverTrack',
      ),
    );
    
    if (result.error == null) {
      await _stripe.presentPaymentSheet();
      return 'success';
    }
  } catch (e) {
    _logger.e('Stripe error: $e');
  }
  return 'cancelled';
}
```

### Analytics (Optional)

```dart
// Add Firebase Analytics:
import 'package:firebase_analytics/firebase_analytics.dart';

final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

// Track events:
await _analytics.logEvent(
  name: 'session_started',
  parameters: {'property_id': propertyId},
);
```

## Monitoring After Launch

### Sentry for Error Tracking (Optional)

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

await SentryFlutter.init(
  (options) => options.dsn = 'YOUR_SENTRY_DSN',
  appRunner: () => runApp(CoverTrackApp()),
);
```

### Metrics to Monitor

1. **Crash Rate**: Should be < 0.1%
2. **Session Duration**: Average time to complete session
3. **Active Users**: DAU / MAU
4. **Feature Usage**: Tracking vs export vs property mgmt
5. **GPS Accuracy**: Average accuracy at time of tracking
6. **App Performance**: Startup time, screen transitions

### Supabase Monitoring

```
Database → Inspect:
- Slow queries (check indexes)
- Auth usage (user growth)
- Storage (PDF files saved)
- Real-time connections

Auth → Activity:
- Sign-ups per day
- Failed login attempts (brute force?)
- Geographic distribution
```

## Post-Launch Support

### Version Updates

**Minor Updates** (1.1.x):
- Bug fixes
- Performance improvements
- Small feature additions
- No database migration needed

**Major Updates** (2.0.x):
- Significant new features
- Database schema changes
- Requires user update + data migration

### Patch Policy
- Critical bugs: Release within 24 hours
- Important bugs: Release within 1 week
- Minor: Bundle with next release

## Rollback Plan

If critical issue detected:

```bash
# Revert to previous version in App Store:
1. Previous version still available
2. Users on old version stay connected
3. New users can opt-in to old version

# Or release hotfix:
flutter build appbundle --release
# Submit new build within 2 hours
```

## User Support

### FAQ Template

**Q: GPS not working**
A: Check Settings → Location → Allow for CoverTrack

**Q: Can't sync tracking sessions**
A: Ensure internet connection + Supabase credentials correct

**Q: PDF not generating**
A: Try closing & reopening app, check device storage space

**Q: How do I reset my account?**
A: Contact support@covertrack.app

### Bug Report Form

```
Title: [One line description]
Device: [Model, OS version]
Steps to reproduce:
1. [First step]
2. [Second step]
3. [Expected vs actual result]

Settings:
- Tier: [hobbyist/individual/corporate]
- Last used: [date]
- GPS enabled: [yes/no]
```

## Security Audit Checklist

Before launch, verify:

- [ ] No hardcoded secrets in code (check git history)
- [ ] HTTPS only for all API calls
- [ ] JWT tokens not logged
- [ ] RLS policies enforce user boundaries
- [ ] No SQL injection vectors (use parameterized queries)
- [ ] Sensitive data (PDF) not cached insecurely
- [ ] Rate limiting enabled on auth endpoints
- [ ] App signature verification enabled (Android)

### OWASP Mobile Top 10 Review

- [ ] Broken cryptography: Use Supabase built-in SSL
- [ ] Weak server controls: RLS enabled ✓
- [ ] Insecure data storage: No sensitive local storage
- [ ] Unvalidated input: All inputs validated
- [ ] Poor encryption: JWT + SSL ✓
- [ ] API abuse: Rate limiting to implement
- [ ] Security misconfiguration: RLS, CORS set ✓
- [ ] Insecure authentication: Supabase auth ✓
- [ ] Insufficient logging: Logger configured ✓
- [ ] Code tampering: Obfuscation recommended for release ✓

## 30-Day Post-Launch Plan

**Day 1**: Monitor crashes, user feedback, server load
**Day 3**: First hotfix if needed
**Day 7**: Analytics review, user growth metrics
**Day 14**: Feature usage analysis, UX improvements
**Day 21**: Plan first feature release (v1.1)
**Day 30**: Determine success criteria met?

## Key Metrics for Success

### Day 30 Targets
- Sign-ups: 100+ users
- Active users: 40+ DAU
- Retention: 30% returning after 7 days
- Avg session: 15+ minutes
- Crash rate: < 0.1%

### Success Criteria
✅ = Yes, ⚠️ = Minor issues, ❌ = Major issues

- [ ] ✅ Stable on real devices (3+ phones tested)
- [ ] ✅ < 3 second app startup
- [ ] ✅ GPS tracks reliably
- [ ] ✅ PDF exports without errors
- [ ] ✅ All auth flows work
- [ ] ✅ Error messages helpful
- [ ] ✅ Online & offline modes handled

## Roadmap for Future Versions

### v1.1 (1-2 months)
- [ ] Mapbox map widget integration
- [ ] Real-time multi-user tracking
- [ ] Worker assignment system
- [ ] Session sharing

### v1.2 (2-3 months)
- [ ] Stripe payment integration (full)
- [ ] Advanced analytics dashboard
- [ ] Mobile web version
- [ ] Offline PDF generation

### v2.0 (3-6 months)
- [ ] Web platform (React)
- [ ] API for third-party integrations
- [ ] Machine learning coverage optimization
- [ ] Real estate partnerships

---

**Version**: 1.0 Deployment Guide  
**Last Updated**: Q1 2024  
**Status**: Ready for Production ✓
