import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/property_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';
import '../utils/local_storage_service.dart';
import '../utils/theme_controller.dart';
import '../widgets/app_ui.dart';
import '../widgets/dashboard_widgets.dart';
import 'onboarding_screen.dart';
import 'plan_selection_screen.dart';
import 'property_detail_screen.dart';
import 'team_overview_screen.dart';

final logger = Logger();

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _greenPrimary = Color(0xFF4CAF50);
  static const Color _blueAccent = Color(0xFF2196F3);

  UserProfile? _userProfile;
  List<Property> _properties = [];
  List<TrackingSession> _allSessions = [];
  List<TrackingSession> _recentSessions = [];

  double _totalAcresTracked = 0;
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = context.read<SupabaseService>();
      final userId = supabase.currentUserId;
      if (userId == null) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      final profile = await supabase.ensureCurrentUserProfile();
      final localStorage = context.read<LocalStorageService>();
      final onboardingDismissed = localStorage.isOnboardingDismissed(userId);
      final properties = await supabase.fetchUserProperties(
        userId,
        userRole: profile?.role ?? 'hobbyist',
      );
      final sessions = await supabase.fetchUserSessions(
        userId,
        dateFrom: DateTime(2000),
        dateTo: DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        _properties = properties;
        _allSessions = sessions;
        _recentSessions = sessions.take(3).toList();
        _totalAcresTracked = _calculateTotalAcres(sessions);
        _isLoading = false;
      });

      // Show onboarding if first_login is true
      if (profile?.firstLogin == true && !onboardingDismissed && mounted) {
        Future.microtask(() {
          _showOnboarding();
        });
      }
    } catch (e) {
      logger.e('Load dashboard error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar.error('Failed to load dashboard. Pull down to retry.'),
      );
    }
  }

  void _showOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const OnboardingScreen(isFirstLogin: true),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    try {
      final supabase = context.read<SupabaseService>();
      await supabase.signOut();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }

  Future<void> _openUpgradePlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlanSelectionScreen(onPlanSelected: _loadData),
      ),
    );
    _loadData();
  }

  void _showSettingsSheet() {
    final themeController = context.read<ThemeController>();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text('Theme mode'),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('System'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('Light'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                  ),
                ],
                selected: {themeController.themeMode},
                onSelectionChanged: (selection) {
                  themeController.setThemeMode(selection.first);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleProfileAction(String value) async {
    if (value == 'settings') {
      _showSettingsSheet();
      return;
    }

    if (value == 'upgrade') {
      await _openUpgradePlan();
      return;
    }

    if (value == 'sign_out') {
      await _handleSignOut();
    }
  }

  void _showAddPropertyDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Property'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Property Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty ||
                  addressController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              try {
                final supabase = context.read<SupabaseService>();
                if (_userProfile != null && !_userProfile!.canAddNewMap()) {
                  final maxMaps = _userProfile!.getMaxMaps();
                  final upgradeMsg = _userProfile!.tier == 'hobby'
                      ? 'Upgrade to Individual for 3 maps or Corporate for unlimited.'
                      : 'Upgrade to Corporate for unlimited maps.';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Map limit reached ($maxMaps). $upgradeMsg'),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  return;
                }

                await supabase.createProperty(
                  name: nameController.text,
                  address: addressController.text,
                  ownerId: supabase.currentUserId!,
                );
                if (!context.mounted) return;
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('Add Property'),
          ),
        ],
      ),
    );
  }

  void _startTrackingAction() {
    final mapProperties = _properties.where((p) => p.hasMapData()).toList();
    if (mapProperties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No mapped properties yet. Add a map first.'),
        ),
      );
      return;
    }

    if (mapProperties.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(property: mapProperties.first),
        ),
      ).then((_) => _loadData());
      return;
    }

    setState(() => _selectedIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pick a property below to start a new tracking job.'),
      ),
    );
  }

  void _addMapAction() {
    if (_properties.isEmpty) {
      _showAddPropertyDialog();
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final property = _properties[index];
            return ListTile(
              leading: const Icon(Icons.landscape_outlined),
              title: Text(property.name),
              subtitle: Text(
                property.hasMapData()
                    ? 'Map exists: update import'
                    : 'No map yet: add import',
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(property: property),
                  ),
                ).then((_) => _loadData());
              },
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: _properties.length,
        ),
      ),
    );
  }

  void _openTeamOverview() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TeamOverviewScreen()),
    ).then((_) => _loadData());
  }

  double _calculateTotalAcres(List<TrackingSession> sessions) {
    var total = 0.0;
    for (final session in sessions) {
      total += _estimateAcres(session);
    }
    return total;
  }

  double _estimateAcres(TrackingSession session) {
    if (session.paths.length < 2) return 0;

    const distance = Distance();
    var distanceMeters = 0.0;

    for (var i = 0; i < session.paths.length - 1; i++) {
      final a = session.paths[i];
      final b = session.paths[i + 1];
      distanceMeters += distance.as(
        LengthUnit.Meter,
        LatLng(a.latitude, a.longitude),
        LatLng(b.latitude, b.longitude),
      );
    }

    const swathWidth = 2.0;
    final coverageFactor = (session.coveragePercent ?? 100) / 100;
    final areaSqMeters = distanceMeters * swathWidth * coverageFactor;
    return areaSqMeters / 4046.86;
  }

  String _coverageLabel(TrackingSession? session) {
    if (session?.coveragePercent == null) return 'N/A';
    return '${session!.coveragePercent!.toStringAsFixed(0)}% coverage';
  }

  String _displayName() {
    final email = _userProfile?.email ?? 'Operator';
    final raw = email.split('@').first;
    if (raw.isEmpty) return 'Operator';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String _tierDisplay() {
    final tier = (_userProfile?.tier ?? 'hobby').toLowerCase();
    if (tier == 'hobby') return 'Hobby Starter';
    if (tier == 'individual') return 'Solo Professional';
    if (tier == 'corporate') return 'Corporate Operations';
    return tier;
  }

  String _activeMapsLabel() {
    final active = _userProfile?.activeMapsCount ?? 0;
    final maxMaps = _userProfile?.getMaxMaps() ?? 1;
    if (maxMaps < 0) return '$active/Unlimited';
    return '$active/$maxMaps';
  }

  int _jobsThisMonth() {
    final now = DateTime.now();
    return _allSessions
        .where((s) =>
            s.startTime.year == now.year && s.startTime.month == now.month)
        .length;
  }

  double _averageCoveragePercent() {
    final covered =
        _allSessions.where((s) => s.coveragePercent != null).toList();
    if (covered.isEmpty) return 0;
    final total =
        covered.map((s) => s.coveragePercent!).fold<double>(0, (a, b) => a + b);
    return total / covered.length;
  }

  bool _shouldShowUpgradeNudge() {
    final profile = _userProfile;
    if (profile == null) return false;
    final maxMaps = profile.getMaxMaps();
    if (maxMaps < 0) return false;
    final active = profile.activeMapsCount;
    return active >= (maxMaps - 1);
  }

  String _sessionDurationLabel(TrackingSession session) {
    final end = session.endTime ?? DateTime.now();
    final minutes = end.difference(session.startTime).inMinutes;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return '${hours}h ${rem}m';
  }

  Property? _findProperty(String propertyId) {
    for (final property in _properties) {
      if (property.id == propertyId) return property;
    }
    return null;
  }

  String _propertyNameForSession(TrackingSession session) {
    return _findProperty(session.propertyId)?.name ?? 'Property';
  }

  Future<void> _openSessionDetail(TrackingSession session) async {
    final property = _findProperty(session.propertyId);
    if (property == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Property not found for this session.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(property: property)),
    );
    _loadData();
  }

  Future<void> _openProofPdf(TrackingSession session) async {
    final url = session.proofPdfUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No proof PDF available for this session.')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid proof PDF URL.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open proof PDF.')),
      );
    }
  }

  Widget _buildQuickStatsRow() {
    final averageCoverage = _averageCoveragePercent();

    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildTeaserStatCard(
            title: 'Total acres tracked',
            value: AppFormat.acres(_totalAcresTracked),
            icon: Icons.crop_square_outlined,
          ),
          _buildTeaserStatCard(
            title: 'Average coverage',
            value: AppFormat.percent(averageCoverage),
            icon: Icons.radar_outlined,
          ),
          _buildTeaserStatCard(
            title: 'Jobs this month',
            value: '${_jobsThisMonth()}',
            icon: Icons.calendar_month_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildTeaserStatCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 190,
      margin: const EdgeInsets.only(right: 10),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _greenPrimary),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.78),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivityFeed() {
    final sessions = _allSessions.take(4).toList();
    if (sessions.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            children: [
              Icon(
                Icons.history_toggle_off_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                'No sessions yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start a tracking job to see your field activity here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 212,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final dateLabel = DateFormat('MMM d, y').format(session.startTime);
          final coverage = session.coveragePercent != null
              ? '${session.coveragePercent!.toStringAsFixed(0)}%'
              : '--';
          final propertyName = _propertyNameForSession(session);

          return Container(
            width: 290,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _greenPrimary.withValues(alpha: 0.18)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openSessionDetail(session),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        propertyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(dateLabel),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _smallMetric('Coverage', coverage),
                          const SizedBox(width: 10),
                          _smallMetric(
                              'Duration', _sessionDurationLabel(session)),
                        ],
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _openProofPdf(session),
                          icon: const Icon(Icons.picture_as_pdf_outlined,
                              size: 18),
                          label: const Text('View PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _smallMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _greenPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeNudgeCard() {
    final profile = _userProfile;
    if (profile == null || !_shouldShowUpgradeNudge()) {
      return const SizedBox.shrink();
    }

    final active = profile.activeMapsCount;
    final maxMaps = profile.getMaxMaps();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              _greenPrimary.withValues(alpha: 0.12),
              _blueAccent.withValues(alpha: 0.08),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re at $active/$maxMaps maps (${_tierDisplay()}) - upgrade to unlimited?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _openUpgradePlan,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('See Plans'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentJobsPreview() {
    if (_recentSessions.isEmpty) {
      return const Text('No sessions yet');
    }

    return Column(
      children: _recentSessions.map((session) {
        final start = DateFormat('MMM d').format(session.startTime);
        final value = session.coveragePercent != null
            ? '${session.coveragePercent!.toStringAsFixed(0)}%'
            : '--';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: RecentJobLine(label: start, value: value),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActions() {
    final isCorporate = _userProfile?.role == 'corporate_admin';
    final cards = <Widget>[
      QuickActionCard(
        title: 'Start New Tracking',
        subtitle: 'Begin job on a property',
        icon: Icons.play_circle_outline_rounded,
        color: _greenPrimary,
        onTap: _startTrackingAction,
      ),
      QuickActionCard(
        title: 'Add New Map',
        subtitle: 'Import drone footage',
        icon: Icons.map_outlined,
        color: _blueAccent,
        onTap: _addMapAction,
      ),
      QuickActionCard(
        title: 'View Recent Sessions',
        subtitle: 'Latest jobs with coverage',
        icon: Icons.list_alt_rounded,
        color: Colors.teal,
        onTap: () => setState(() => _selectedIndex = 2),
        child: _buildRecentJobsPreview(),
      ),
      if (isCorporate)
        QuickActionCard(
          title: 'Team Overview',
          subtitle: 'Manage assignments and stats',
          icon: Icons.groups_2_outlined,
          color: Colors.indigo,
          onTap: _openTeamOverview,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 700;
        if (isPhone) {
          return Column(
            children: List.generate(cards.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: cards[index]
                    .animate(delay: (80 * index).ms)
                    .fadeIn(duration: 320.ms)
                    .slideY(begin: 0.06, end: 0),
              );
            }),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.65,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            return cards[index]
                .animate(delay: (80 * index).ms)
                .fadeIn(duration: 320.ms)
                .slideY(begin: 0.06, end: 0);
          },
        );
      },
    );
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          DashboardHeroCard(
            welcomeText: 'Welcome back, ${_displayName()}',
            tierLabel: _tierDisplay(),
            activeMaps: _activeMapsLabel(),
            lastJob: _coverageLabel(
                _allSessions.isEmpty ? null : _allSessions.first),
            totalAcres: AppFormat.acres(_totalAcresTracked),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 16),
          const DashboardSectionHeader(title: 'Quick Stats'),
          const SizedBox(height: 10),
          _buildQuickStatsRow()
              .animate(delay: 60.ms)
              .fadeIn(duration: 320.ms)
              .slideY(begin: 0.04, end: 0),
          const SizedBox(height: 16),
          const DashboardSectionHeader(title: 'Recent Activity'),
          const SizedBox(height: 10),
          _buildRecentActivityFeed()
              .animate(delay: 110.ms)
              .fadeIn(duration: 320.ms)
              .slideY(begin: 0.04, end: 0),
          const SizedBox(height: 14),
          _buildUpgradeNudgeCard()
              .animate(delay: 140.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.04, end: 0),
          if (_shouldShowUpgradeNudge()) const SizedBox(height: 16),
          const DashboardSectionHeader(title: 'Quick Actions'),
          const SizedBox(height: 12),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildPropertiesTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          DashboardSectionHeader(
            title: 'Properties (${_properties.length})',
            trailing: FilledButton.icon(
              onPressed: _showAddPropertyDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(height: 12),
          if (_properties.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.landscape_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No properties yet',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap Add above to create your first property.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._properties.map((property) {
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (_greenPrimary).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on_outlined),
                  ),
                  title: Text(property.name),
                  subtitle: Text(
                    property.hasMapData()
                        ? 'Mapped property'
                        : (property.address ?? 'No address'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PropertyDetailScreen(property: property),
                      ),
                    ).then((_) => _loadData());
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final sessionCount = _allSessions.length;
    final coveredSessions =
        _allSessions.where((s) => s.coveragePercent != null).toList();
    final avgCoverage = coveredSessions.isEmpty
        ? 0.0
        : coveredSessions
                .map((s) => s.coveragePercent!)
                .fold<double>(0, (a, b) => a + b) /
            coveredSessions.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const DashboardSectionHeader(title: 'Analytics Snapshot'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metricCard('Sessions', '$sessionCount', Icons.timeline_outlined),
            _metricCard('Avg Coverage', AppFormat.percent(avgCoverage),
                Icons.track_changes_outlined),
            _metricCard('Acres', AppFormat.acres(_totalAcresTracked),
                Icons.crop_square_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open full dashboard',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the full analytics page for charts, team metrics, and range filters.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/analytics'),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Open Analytics'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _blueAccent),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const DashboardSectionHeader(title: 'More'),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.info_outline),
            title: const Text('About SprayMap Pro'),
            subtitle:
                const Text('Read product details and platform capabilities.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/about'),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('App Settings'),
            subtitle: const Text('Theme and dashboard preferences.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showSettingsSheet,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('App Guide'),
            subtitle: const Text('Walkthrough how SprayMap Pro works — anytime.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(isFirstLogin: false),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            subtitle: const Text('Securely sign out of this account.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _handleSignOut,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.star_outline),
            title: const Text('Upgrade Plan'),
            subtitle: const Text('Unlock higher map limits and team features.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openUpgradePlan,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody() {
    if (_selectedIndex == 0) return _buildDashboardTab();
    if (_selectedIndex == 1) return _buildPropertiesTab();
    if (_selectedIndex == 2) return _buildAnalyticsTab();
    return _buildMoreTab();
  }

  @override
  Widget build(BuildContext context) {
    final initial = (_userProfile?.email ?? 'U').trim();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.spa_outlined),
            SizedBox(width: 8),
            Text('SprayMap Pro'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Profile',
            onSelected: _handleProfileAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'upgrade', child: Text('Upgrade plan')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: _blueAccent.withValues(alpha: 0.14),
                child: Text(
                  initial.isEmpty ? 'U' : initial[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey<int>(_selectedIndex),
                child: _buildTabBody(),
              ),
            ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          elevation: 4,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1F1F1F)
              : Colors.white,
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            elevation: 4,
            selectedItemColor: _greenPrimary,
            unselectedItemColor: Colors.grey,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1F1F1F)
                : Colors.white,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Properties',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: 'Analytics',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.more_horiz),
                activeIcon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
