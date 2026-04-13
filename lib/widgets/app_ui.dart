import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/app_theme.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.spaceMd),
  }) : super(key: key);

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: child,
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.elevation = 3,
    this.margin,
    this.radius = 16,
  }) : super(key: key);

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double elevation;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}


class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isDense;
  final bool isHighContrast;
  final bool isLoading;

  const AppPrimaryButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDense = false,
    this.isHighContrast = false,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = isDense ? 48.0 : 56.0;
    final bgColor = isHighContrast
        ? Colors.black
        : theme.colorScheme.primary;
    final fgColor = isHighContrast
        ? Colors.white
        : theme.colorScheme.onPrimary;

    final style = ElevatedButton.styleFrom(
      minimumSize: Size.fromHeight(height),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      textStyle: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: isDense ? 16 : 18,
        letterSpacing: 0.1,
      ),
      elevation: isHighContrast ? 2 : 0,
    );

    final child = isLoading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Text(label);

    if (icon != null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: Icon(icon, size: isDense ? 22 : 26),
          label: child,
          style: style,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: child,
      ),
    );
  }
}

class AppSnackBar {
  static SnackBar success(String message) {
    return _build(
      message: message,
      backgroundColor: const Color(0xFF1B5E20),
      icon: Icons.check_circle_outline,
    );
  }

  static SnackBar error(String message) {
    return _build(
      message: message,
      backgroundColor: Colors.red.shade700,
      icon: Icons.error_outline,
    );
  }

  static SnackBar warning(String message) {
    return _build(
      message: message,
      backgroundColor: const Color(0xFFB26A00),
      icon: Icons.warning_amber_outlined,
    );
  }

  static SnackBar info(String message) {
    return _build(
      message: message,
      backgroundColor: const Color(0xFF0D47A1),
      icon: Icons.info_outline,
    );
  }

  static SnackBar _build({
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    return SnackBar(
      content: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    );
  }
}

class AppFormat {
  static final NumberFormat _oneDecimal = NumberFormat('0.0');

  static String acres(num? acres, {String fallback = 'N/A'}) {
    if (acres == null) return fallback;
    return '${_oneDecimal.format(acres)} ac';
  }

  static String percent(num? percent, {String fallback = 'N/A'}) {
    if (percent == null) return fallback;
    return '${_oneDecimal.format(percent)}%';
  }

  static String durationMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) return '${hours}h';
    return '${hours}h ${remainder}m';
  }

  static String durationSeconds(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return durationMinutes(minutes);
  }

  static String miles(num miles) {
    return '${_oneDecimal.format(miles)} mi';
  }

  static String feet(num feet) {
    return '${_oneDecimal.format(feet)} ft';
  }

  static String meters(num meters) {
    return '${_oneDecimal.format(meters)} m';
  }

  static String temperatureF(num temp) {
    return '${_oneDecimal.format(temp)} F';
  }

  static String latLng(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}
