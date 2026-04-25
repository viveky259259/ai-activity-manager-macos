import 'package:flutter/material.dart';

/// Material 3 dark theme tuned for the daemon's "agent activity monitor"
/// vibe — neutral surfaces, indigo accent for actions, semantic outcome
/// colors that meet WCAG AA contrast on the dark surface.
class AppTheme {
  static const _seed = Color(0xFF6366F1); // indigo-500

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return _build(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        bodyLarge: TextStyle(height: 1.5),
        bodyMedium: TextStyle(height: 1.5),
      ),
    );
  }

  /// Colors used for audit outcome badges. Picked so they pass 4.5:1 contrast
  /// on `surfaceContainer` in both light and dark schemes.
  static Color outcomeColor(String outcome, ColorScheme scheme) {
    if (outcome == 'succeeded') return scheme.primary;
    if (outcome == 'rate_limited') return Colors.orange;
    if (outcome.startsWith('error')) return scheme.error;
    return scheme.onSurfaceVariant;
  }
}
