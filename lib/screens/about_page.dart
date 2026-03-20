import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_ui.dart';
import 'login_screen.dart';
import 'plan_selection_screen.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  bool get _isAuthenticated =>
      Supabase.instance.client.auth.currentSession != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About SprayMap Pro'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0xFF0F1511),
                    Color(0xFF111B18),
                    Color(0xFF121A21),
                  ]
                : const [
                    Color(0xFFF5F9F5),
                    Color(0xFFEAF5FF),
                    Color(0xFFF5F5F5),
                  ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHero(context),
              const SizedBox(height: 16),
              _animatedSection(
                delayMs: 100,
                child: _buildProblemSection(context),
              ),
              const SizedBox(height: 16),
              _animatedSection(
                delayMs: 180,
                child: _buildSolutionSection(context),
              ),
              const SizedBox(height: 16),
              _animatedSection(
                delayMs: 260,
                child: _buildAudienceSection(context),
              ),
              const SizedBox(height: 16),
              _animatedSection(
                delayMs: 340,
                child: _buildBetaSection(context),
              ),
              const SizedBox(height: 20),
              _animatedSection(
                delayMs: 420,
                child: _buildCtas(context, colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedSection({required int delayMs, required Widget child}) {
    return child
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs), duration: 360.ms)
        .slideY(
          begin: 0.08,
          end: 0,
          delay: Duration(milliseconds: delayMs),
          duration: 360.ms,
        );
  }

  Widget _buildHero(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF153420),
                  Color(0xFF1A4A31),
                  Color(0xFF183B5C),
                ]
              : const [
                  Color(0xFF173A22),
                  Color(0xFF1F5B39),
                  Color(0xFF1B4F7F),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Built for operators who need proof, not guesswork',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Precision Coverage Tracking & Proof — Built for Pros',
            style: GoogleFonts.roboto(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Eliminate missed spots, save 10–30% on chemicals, and deliver undeniable proof to clients and bosses — all with your phone and a cheap drone.',
            style: GoogleFonts.roboto(
              fontSize: 16,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _heroMetric(
                  label: 'Savings',
                  value: '10–30%',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroMetric(
                  label: 'Proof',
                  value: 'PDF + Map',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroMetric(
                  label: 'Setup',
                  value: 'Phone + Drone',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.roboto(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.roboto(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.warning_amber_rounded,
            title: 'The Problem',
          ),
          const SizedBox(height: 14),
          Text(
            'Even top technicians cross lines 10–20 times per job — wasting product, risking callbacks, and leaving weak proof (screenshots or photos).',
            style: GoogleFonts.roboto(
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolutionSection(BuildContext context) {
    final items = [
      const _SolutionItem(
        icon: Icons.map_outlined,
        title: 'Import your drone map once — track coverage live with GPS + swath width',
      ),
      const _SolutionItem(
        icon: Icons.visibility_outlined,
        title: 'See treated areas overlaid on real grass/trees — correct misses before leaving the job',
      ),
      const _SolutionItem(
        icon: Icons.description_outlined,
        title: 'Generate clean, timestamped proof PDFs — map + % covered — clients trust',
      ),
      const _SolutionItem(
        icon: Icons.savings_outlined,
        title: 'Save 10–30% on chemicals by avoiding wasteful overlaps',
      ),
      const _SolutionItem(
        icon: Icons.agriculture_outlined,
        title: 'Works with backpack sprayers, push mowers, small tractors — no expensive hardware needed',
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.verified_outlined,
            title: 'What SprayMap Pro Does',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 700;
              if (!isWide) {
                return Column(
                  children: items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _solutionCard(context, item),
                        ),
                      )
                      .toList(),
                );
              }

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: _solutionCard(context, item),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _solutionCard(BuildContext context, _SolutionItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              item.title,
              style: GoogleFonts.roboto(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.groups_outlined,
            title: 'Who It\'s For',
          ),
          const SizedBox(height: 14),
          Text(
            'Designed for independent lawn & pest pros, small farmers, and large single-property owners who want pro results without enterprise prices.',
            style: GoogleFonts.roboto(
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetaSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.rocket_launch_outlined,
            title: 'Beta & Pricing',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Join limited beta — 90 days free (full Solo Professional features)',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'After beta: 50% lifetime discount (\$114.50 instead of \$229) for early adopters',
            style: GoogleFonts.roboto(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Plans from \$59 lifetime — see full pricing',
            style: GoogleFonts.roboto(
              fontSize: 15,
              height: 1.45,
              color: colorScheme.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtas(BuildContext context, ColorScheme colorScheme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to tighten coverage, reduce waste, and prove the job was done right?',
            style: GoogleFonts.roboto(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: 'Get Started — Join Beta Free',
            icon: Icons.arrow_forward,
            onPressed: () {
              if (_isAuthenticated) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanSelectionScreen(onPlanSelected: () {}),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(startInSignUpMode: true),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                );
              },
              icon: Icon(Icons.login, color: colorScheme.onSurface),
              label: const Text('Sign In'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.roboto(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SolutionItem {
  const _SolutionItem({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;
}
