import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingInfoCard extends StatelessWidget {
  const LandingInfoCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.iconBackgroundColor,
    this.delayIndex = 0,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final int delayIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.primary;
    final effectiveBackground =
        iconBackgroundColor ?? colorScheme.primary.withValues(alpha: 0.14);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: effectiveBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: effectiveIconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 110 * delayIndex),
          duration: 420.ms,
        )
        .slideY(
          begin: 0.12,
          end: 0,
          delay: Duration(milliseconds: 110 * delayIndex),
          duration: 420.ms,
        );
  }
}

class LandingSectionTitle extends StatelessWidget {
  const LandingSectionTitle({
    Key? key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: GoogleFonts.roboto(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.roboto(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: GoogleFonts.roboto(
            fontSize: 15,
            height: 1.5,
            color: colorScheme.onSurface.withValues(alpha: 0.88),
          ),
        ),
      ],
    );
  }
}

class LandingFooterLink extends StatelessWidget {
  const LandingFooterLink({
    Key? key,
    required this.label,
    required this.onPressed,
  }) : super(key: key);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      child: Text(
        label,
        style: GoogleFonts.roboto(fontWeight: FontWeight.w500),
      ),
    );
  }
}

class LandingCtaButton extends StatefulWidget {
  const LandingCtaButton({
    Key? key,
    required this.label,
    required this.onPressed,
    required this.filled,
    this.icon,
  }) : super(key: key);

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final IconData? icon;

  @override
  State<LandingCtaButton> createState() => _LandingCtaButtonState();
}

class _LandingCtaButtonState extends State<LandingCtaButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = widget.filled ? colorScheme.primary : Colors.transparent;
    final foreground = widget.filled ? Colors.white : colorScheme.onSurface;

    final child = widget.icon == null
        ? Text(widget.label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.02 : 1,
        duration: const Duration(milliseconds: 160),
        child: SizedBox(
          width: double.infinity,
          child: widget.filled
              ? ElevatedButton(
                  onPressed: widget.onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: background,
                    foregroundColor: foreground,
                    minimumSize: const Size.fromHeight(56),
                    elevation: _hovered ? 3 : 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: child,
                )
              : OutlinedButton(
                  onPressed: widget.onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    side: BorderSide(color: colorScheme.outline),
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: _hovered
                        ? colorScheme.surface.withValues(alpha: 0.88)
                        : colorScheme.surface.withValues(alpha: 0.72),
                  ),
                  child: child,
                ),
        ),
      ),
    );
  }
}
