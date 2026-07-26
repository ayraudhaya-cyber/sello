import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme mode architecture.
///
/// Dark theme is **supported in the API** but not visually implemented yet.
/// Selecting [ThemeMode.dark] falls back to light until a dark palette ships.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void setMode(ThemeMode mode) {
    // Dark is architecturally accepted but resolves to light in AppTheme.
    state = mode;
  }

  void toggleLightDark() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Effective brightness for UI that must know whether dark is actually active.
final effectiveBrightnessProvider = Provider<Brightness>((ref) {
  final mode = ref.watch(themeModeProvider);
  // Until dark theme is implemented, always light.
  switch (mode) {
    case ThemeMode.light:
    case ThemeMode.dark:
    case ThemeMode.system:
      return Brightness.light;
  }
});
