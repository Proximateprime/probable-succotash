class AppConstants {
  static const String supabaseUrl = 'https://spucayasxeedutdpcrqg.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwdWNheWFzeGVlZHV0ZHBjcnFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2OTY1MjEsImV4cCI6MjA4OTI3MjUyMX0.DS4Dhure8b0KLsBBsR5Ng3rMzyUXOlmxCd7vNhpuico';
  // Stripe publishable key — get from stripe.com/dashboard > Developers > API keys
  // Use pk_test_... for testing, pk_live_... for production
  static const String stripePublishableKey = 'pk_test_REPLACE_WITH_YOUR_KEY';

  // Dev/beta flag: when true, plan activation bypasses payment and updates tier directly.
  // Set to true during beta (no charges). Flip to false when Stripe keys + price IDs are live.
  static const bool enableFreeBetaPlanActivation = true;

  static const int gpsUpdateIntervalSeconds = 3;
  static const int hobbyistMaxActiveMaps = 1;
  static const int individualMaxActiveMaps = 3;

  static const double defaultMapZoom = 16.0;
  static const double minMapZoom = 10.0;
  static const double maxMapZoom = 22.0;
}
