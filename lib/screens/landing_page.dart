import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/landing_widgets.dart';
import 'about_page.dart';
import 'home_dashboard.dart';
import 'login_screen.dart';
import 'plan_selection_screen.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({Key? key}) : super(key: key);

  bool get _isAuthenticated =>
      Supabase.instance.client.auth.currentSession != null;

  Future<void> _openContact() async {
    final uri = Uri.parse('mailto:support@spraymappro.com');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
                    Color(0xFFE9F4FF),
                    Color(0xFFF5F5F5),
                  ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(
                    alpha: isDark ? 0.14 : 0.10,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(
                    alpha: isDark ? 0.12 : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _buildTopBar(context),
                  const SizedBox(height: 8),
                  _buildHero(context),
                  const SizedBox(height: 24),
                  _buildPainSection(context),
                  const SizedBox(height: 22),
                  _buildSolutionSection(context),
                  const SizedBox(height: 22),
                  _buildPricingTeaser(context),
                  const SizedBox(height: 20),
                  _buildFooterCta(context),
                  const SizedBox(height: 18),
                  _buildFooterLinks(context, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          'SprayMap Pro',
          style: GoogleFonts.roboto(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AboutPage(),
              ),
            );
          },
          child: const Text('About'),
        ),
      ],
    ).animate().fadeIn(duration: 260.ms);
  }

  Widget _buildHero(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1A2320), Color(0xFF17201C)]
              : const [Color(0xFFFDFEFE), Color(0xFFF4F8F4)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coverage proof for lawn care, pest control, and small farm crews',
            style: GoogleFonts.roboto(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          )
              .animate()
              .fadeIn(duration: 360.ms)
              .slideY(begin: 0.12, end: 0, duration: 360.ms),
          const SizedBox(height: 18),
          Text(
            'Never Miss a Spot Again',
            style: GoogleFonts.roboto(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: colorScheme.onSurface,
            ),
          )
              .animate()
              .fadeIn(delay: 80.ms, duration: 420.ms)
              .slideY(begin: 0.14, end: 0, delay: 80.ms, duration: 420.ms),
          const SizedBox(height: 12),
          Text(
            'Live coverage tracking + professional proof — save 10–30% on chemicals, eliminate wasteful overlaps, and give clients undeniable proof.',
            style: GoogleFonts.roboto(
              fontSize: 16,
              height: 1.45,
              color: colorScheme.onSurface.withValues(alpha: 0.90),
            ),
          )
              .animate()
              .fadeIn(delay: 140.ms, duration: 420.ms)
              .slideY(begin: 0.14, end: 0, delay: 140.ms, duration: 420.ms),
          const SizedBox(height: 22),
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF194529),
                  Color(0xFF2A6D47),
                  Color(0xFF356E98)
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.satellite_alt_outlined,
                          size: 52, color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        'Drone map placeholder – your yard view',
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 220.ms, duration: 460.ms).scale(
              begin: const Offset(0.98, 0.98),
              end: const Offset(1, 1),
              delay: 220.ms,
              duration: 460.ms),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: LandingCtaButton(
                  label: 'Sign In',
                  icon: Icons.login,
                  filled: false,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LandingCtaButton(
                  label: _isAuthenticated ? 'Open Dashboard' : 'Join Beta Free',
                  icon: _isAuthenticated
                      ? Icons.dashboard_outlined
                      : Icons.arrow_forward,
                  filled: true,
                  onPressed: () {
                    if (_isAuthenticated) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HomeDashboard()),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const LoginScreen(startInSignUpMode: true),
                      ),
                    );
                  },
                ),
              ),
            ],
          ).animate().fadeIn(delay: 340.ms, duration: 420.ms),
        ],
      ),
    );
  }

  Widget _buildPainSection(BuildContext context) {
    const cards = [
      LandingInfoCard(
        icon: Icons.compare_arrows_outlined,
        title: 'Technicians still cross lines 10–20 times per job',
        subtitle: 'Wasting product and time.',
        iconColor: Color(0xFFB26A00),
        iconBackgroundColor: Color(0xFFFFF1D6),
        delayIndex: 1,
      ),
      LandingInfoCard(
        icon: Icons.money_off_csred_outlined,
        title: 'Heavy overlaps to be safe',
        subtitle: '10–30% chemical waste is common.',
        iconColor: Color(0xFF9C3B2E),
        iconBackgroundColor: Color(0xFFFDE1DC),
        delayIndex: 2,
      ),
      LandingInfoCard(
        icon: Icons.warning_amber_rounded,
        title: 'Client callbacks: You missed a spot',
        subtitle: 'Hard to prove full coverage after the fact.',
        iconColor: Color(0xFFB26A00),
        iconBackgroundColor: Color(0xFFFFF1D6),
        delayIndex: 3,
      ),
      LandingInfoCard(
        icon: Icons.broken_image_outlined,
        title: 'Weak proof from screenshots or photos',
        subtitle: 'They do not create confidence or protect your crew.',
        iconColor: Color(0xFF5B6472),
        iconBackgroundColor: Color(0xFFE8EDF3),
        delayIndex: 4,
      ),
    ];

    return _buildResponsiveSection(
      context,
      title: const LandingSectionTitle(
        eyebrow: 'The Cost of Guesswork',
        title:
            'Misses, overlaps, callbacks, and weak proof all cut into margin.',
        subtitle:
            'SprayMap Pro is built for crews that need tighter execution and cleaner proof without enterprise hardware.',
      ),
      cards: cards,
    );
  }

  Widget _buildSolutionSection(BuildContext context) {
    const cards = [
      LandingInfoCard(
        icon: Icons.map_outlined,
        title: 'Import your drone map once',
        subtitle:
            'Track live with phone GPS plus swath width across the real property layout.',
        delayIndex: 1,
      ),
      LandingInfoCard(
        icon: Icons.visibility_outlined,
        title: 'See treated areas overlaid on real grass and trees',
        subtitle:
            'Correct misses instantly before the crew leaves the job site.',
        delayIndex: 2,
      ),
      LandingInfoCard(
        icon: Icons.description_outlined,
        title: 'Generate clean proof PDFs',
        subtitle:
            'Timestamped map plus coverage percent that clients and managers trust.',
        delayIndex: 3,
      ),
      LandingInfoCard(
        icon: Icons.savings_outlined,
        title: 'Save 10–30% on chemicals',
        subtitle:
            'Cut wasteful double-dosing and reduce overlap without guessing.',
        delayIndex: 4,
      ),
    ];

    return _buildResponsiveSection(
      context,
      title: const LandingSectionTitle(
        eyebrow: 'The Fix',
        title:
            'One workflow that turns field execution into visible, defendable proof.',
        subtitle:
            'Bring drone imagery and live tracking together so your team can work cleaner and prove coverage with confidence.',
      ),
      cards: cards,
    );
  }

  Widget _buildResponsiveSection(
    BuildContext context, {
    required Widget title,
    required List<Widget> cards,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title.animate().fadeIn(duration: 320.ms).slideY(begin: 0.08, end: 0),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            if (!isWide) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i != cards.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map(
                    (card) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: card,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPricingTeaser(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plans from \$59 lifetime — join beta for 90 days free',
            style: GoogleFonts.roboto(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start with the core proof workflow now, then lock in early pricing once the beta closes.',
            style: GoogleFonts.roboto(
              fontSize: 15,
              height: 1.45,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanSelectionScreen(
                      onPlanSelected: () {},
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.payments_outlined),
              label: const Text('See Plans & Pricing'),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 320.ms, duration: 420.ms);
  }

  Widget _buildFooterCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF173A22), Color(0xFF215D3C)],
        ),
      ),
      child: Column(
        children: [
          Text(
            'Join Beta — 90 Days Free',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No credit card required. Cancel anytime.',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 18),
          LandingCtaButton(
            label: _isAuthenticated ? 'Open Dashboard' : 'Join Beta Free',
            icon: _isAuthenticated
                ? Icons.dashboard_outlined
                : Icons.arrow_forward,
            filled: true,
            onPressed: () {
              if (_isAuthenticated) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeDashboard()),
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
        ],
      ),
    ).animate().fadeIn(delay: 420.ms, duration: 420.ms);
  }

  Widget _buildFooterLinks(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            LandingFooterLink(
              label: 'About',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            LandingFooterLink(
              label: 'Pricing',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanSelectionScreen(onPlanSelected: () {}),
                  ),
                );
              },
            ),
            LandingFooterLink(
              label: 'Contact',
              onPressed: _openContact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Serious coverage proof for operators who need cleaner execution and fewer callbacks.',
          textAlign: TextAlign.center,
          style: GoogleFonts.roboto(
            fontSize: 13,
            color: colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 500.ms, duration: 420.ms);
  }
}
