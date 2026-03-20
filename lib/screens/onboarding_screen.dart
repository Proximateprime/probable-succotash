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
  static const Color _green = Color(0xFF4CAF50);
  static const Color _blue = Color(0xFF2196F3);

  final PageController _pageController = PageController();

  int _currentIndex = 0;
  bool _isSaving = false;

  static const List<_Slide> _slides = [
    _Slide(
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.white,
      gradientStart: Color(0xFF43A047),
      gradientEnd: Color(0xFF1E88E5),
      title: 'Welcome to SprayMap Pro',
      subtitle: 'Precision GPS coverage for lawn, pest, and farm pros.',
      description: 'Track every pass. Generate proof. Never guess again.',
    ),
    _Slide(
      icon: Icons.home_work_outlined,
      iconColor: Color(0xFF388E3C),
      gradientStart: Color(0xFFE8F5E9),
      gradientEnd: Color(0xFFE3F2FD),
      title: 'Create a Property',
      subtitle: 'Tap + to add a property — residential, commercial, or farm.',
      description: 'Manage multiple properties and field workers from one dashboard.',
    ),
    _Slide(
      icon: Icons.place_outlined,
      iconColor: Color(0xFF1565C0),
      gradientStart: Color(0xFFE3F2FD),
      gradientEnd: Color(0xFFF3E5F5),
      title: 'Set Up Boundaries',
      subtitle: 'Walk the perimeter with your phone or import a drone map.',
      description: 'Define exclusion zones, special areas, and spray lanes precisely.',
    ),
    _Slide(
      icon: Icons.directions_walk_rounded,
      iconColor: Color(0xFF388E3C),
      gradientStart: Color(0xFFE8F5E9),
      gradientEnd: Color(0xFFF9FBE7),
      title: 'Start Tracking',
      subtitle: 'Tap Start — walk your property — watch coverage fill green.',
      description: 'Live GPS tracking with real-time overlap alerts. Reach Mode for edges and bushes.',
    ),
    _Slide(
      icon: Icons.picture_as_pdf_outlined,
      iconColor: Color(0xFF1565C0),
      gradientStart: Color(0xFFE3F2FD),
      gradientEnd: Color(0xFFE8EAF6),
      title: 'Export PDF Proof',
      subtitle: 'Stop the job — sign — auto-generate a professional proof PDF.',
      description: 'Share with clients, comply with regulations, and measure chemical ROI per job.',
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
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (!widget.isFirstLogin)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close guide',
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isLast ? 0 : 1,
                      child: TextButton(
                        onPressed: (_isSaving || isLast) ? null : _onSkip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 114,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentIndex == index ? 26 : 8,
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
            bottom: 28,
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
      final label = widget.isFirstLogin ? 'Get Started' : 'Done';
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
              : Text(
                  label,
                  style: const TextStyle(
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
                    duration: const Duration(milliseconds: 280),
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
                  duration: const Duration(milliseconds: 280),
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
    if (widget.isFirstLogin) {
      await _markComplete();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onComplete() async {
    if (widget.isFirstLogin) {
      await _markComplete();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _markComplete() async {
    setState(() => _isSaving = true);
    try {
      await context.read<SupabaseService>().markFirstLoginComplete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _onboardingLog.e('Onboarding completion error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.error('Could not save progress. Please try again.'),
        );
        setState(() => _isSaving = false);
      }
    }
  }
}

class _Slide {
  final IconData icon;
  final Color iconColor;
  final Color gradientStart;
  final Color gradientEnd;
  final String title;
  final String subtitle;
  final String description;

  const _Slide({
    required this.icon,
    required this.iconColor,
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
          padding: EdgeInsets.fromLTRB(28, paddingTop + 90, 28, 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [slide.gradientStart, slide.gradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: slide.gradientEnd.withValues(alpha: 0.30),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(slide.icon, size: 62, color: slide.iconColor),
              )
                  .animate()
                  .scale(
                    duration: const Duration(milliseconds: 440),
                    curve: Curves.elasticOut,
                  ),
              const SizedBox(height: 38),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                slide.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}