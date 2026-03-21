// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../widgets/app_ui.dart';

final _onboardingLog = Logger();

class OnboardingScreen extends StatefulWidget {
  final bool isFirstLogin;

  const OnboardingScreen({Key? key, this.isFirstLogin = true}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _blue = Color(0xFF1976D2);

  final PageController _pageController = PageController();

  int _currentIndex = 0;
  bool _isSaving = false;

  static const List<_Slide> _slides = [
    _Slide(
      icon: Icons.spa_outlined,
      gradientStart: Color(0xFF2E7D32),
      gradientEnd: Color(0xFF1565C0),
      title: 'Welcome to SprayMap Pro',
      subtitle: 'Precision tracking to never miss a spot.',
      description: 'Track every pass with confidence and keep proof for every job.',
    ),
    _Slide(
      icon: Icons.add_business_outlined,
      gradientStart: Color(0xFFE8F5E9),
      gradientEnd: Color(0xFFE3F2FD),
      title: 'Create a Property',
      subtitle: 'Tap + or open the Properties list.',
      description: 'Add customer locations so each job stays organized and easy to revisit.',
    ),
    _Slide(
      icon: Icons.route_outlined,
      gradientStart: Color(0xFFE3F2FD),
      gradientEnd: Color(0xFFE8F5E9),
      title: 'Set Boundaries',
      subtitle: 'Quick Setup - Walk Perimeter, or import a Drone Map.',
      description: 'Walking perimeter is fastest onsite. Import is ideal when you already mapped the yard.',
    ),
    _Slide(
      icon: Icons.block_outlined,
      gradientStart: Color(0xFFF1F8E9),
      gradientEnd: Color(0xFFE3F2FD),
      title: 'Add Exclusions',
      subtitle: 'Walk or draw no-spray zones.',
      description: 'Use colors, notes, and zone types so everyone understands what to avoid.',
    ),
    _Slide(
      icon: Icons.play_circle_outline,
      gradientStart: Color(0xFFE8F5E9),
      gradientEnd: Color(0xFFE3F2FD),
      title: 'Start Tracking',
      subtitle: 'Tap Start, then walk the yard to see live coverage fill.',
      description: 'Coverage fills green in normal tracking and yellow in preemergent workflows.',
    ),
    _Slide(
      icon: Icons.tune_outlined,
      gradientStart: Color(0xFFE3F2FD),
      gradientEnd: Color(0xFFE8F5E9),
      title: 'Use Special Modes',
      subtitle: 'Reach Mode for edges, Spot Treatment for ant hills.',
      description: 'Enable Spot Treatment and tap Mark Spot for targeted applications.',
    ),
    _Slide(
      icon: Icons.picture_as_pdf_outlined,
      gradientStart: Color(0xFFE8F5E9),
      gradientEnd: Color(0xFFE3F2FD),
      title: 'Finish Job',
      subtitle: 'Tap Stop or Mark Done to finalize the session.',
      description: 'Generate a signed PDF proof with route and coverage for your records.',
    ),
    _Slide(
      icon: Icons.help_outline,
      gradientStart: Color(0xFF2E7D32),
      gradientEnd: Color(0xFF1976D2),
      title: 'Ready to Spray',
      subtitle: 'Questions later? Open Settings -> Help.',
      description: 'You can re-open this tutorial anytime from Settings or the dashboard help icon.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentIndex == _slides.length - 1;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => _SlideWidget(slide: _slides[index]),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (!widget.isFirstLogin)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close tutorial',
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    TextButton(
                      onPressed: _isSaving ? null : _onSkip,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 112,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentIndex == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: _currentIndex == index
                        ? scheme.primary
                        : scheme.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: _buildButtons(isLast),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(bool isLast) {
    if (isLast) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _isSaving ? null : _onComplete,
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Get Started',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      );
    }

    return Row(
      children: [
        if (_currentIndex > 0) ...[
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                  );
                },
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Back'),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSkip() async {
    await _markComplete();
  }

  Future<void> _onComplete() async {
    await _markComplete();
  }

  Future<void> _markComplete() async {
    setState(() => _isSaving = true);
    final supabase = context.read<SupabaseService>();

    try {
      await supabase.markFirstLoginComplete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _onboardingLog.e('Onboarding completion error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.warning(
            'Could not sync tutorial state right now. We will try again later.',
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }
}

class _Slide {
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;
  final String title;
  final String subtitle;
  final String description;

  const _Slide({
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}

class _SlideWidget extends StatelessWidget {
  final _Slide slide;

  const _SlideWidget({required this.slide});

  @override
  Widget build(BuildContext context) {
    final paddingTop = MediaQuery.of(context).padding.top;
    final theme = Theme.of(context);

    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, paddingTop + 88, 28, 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [slide.gradientStart, slide.gradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: slide.gradientEnd.withValues(alpha: 0.25),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  slide.icon,
                  size: 58,
                  color: Colors.white,
                ),
              )
                  .animate()
                  .scale(
                    duration: const Duration(milliseconds: 440),
                    curve: Curves.elasticOut,
                  ),
              const SizedBox(height: 34),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1565C0),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
