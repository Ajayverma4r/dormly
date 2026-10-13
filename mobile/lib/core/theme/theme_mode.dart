// core/theme/theme_mode.dart
//
// Light (default) / dark switch for the Dormly owner screens. Screen palettes
// read [DormlyThemeMode.isDark] through [themed], so the dark values stay the
// original design and the light values are their white-background twins.

import 'package:flutter/material.dart';

import '../storage/app_prefs.dart';

class DormlyThemeMode {
  DormlyThemeMode._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static bool get isDark => mode.value == ThemeMode.dark;

  /// Restores the saved choice; a fresh install stays light.
  static Future<void> load() async {
    try {
      mode.value =
          await AppPrefs.isDarkTheme() ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      mode.value = ThemeMode.light;
    }
  }

  static Future<void> setDark(bool dark) async {
    mode.value = dark ? ThemeMode.dark : ThemeMode.light;
    await AppPrefs.setDarkTheme(dark);
  }

  static Future<void> toggle() => setDark(!isDark);
}

/// [dark] in dark mode, otherwise [light].
Color themed(Color dark, Color light) =>
    DormlyThemeMode.isDark ? dark : light;

/// Rebuilds the whole tree in place when the theme changes, so screens whose
/// palettes are plain getters repaint without losing navigation or state.
class DormlyThemeRebuilder extends StatefulWidget {
  final Widget child;

  const DormlyThemeRebuilder({super.key, required this.child});

  @override
  State<DormlyThemeRebuilder> createState() => _DormlyThemeRebuilderState();
}

class _DormlyThemeRebuilderState extends State<DormlyThemeRebuilder> {
  @override
  void initState() {
    super.initState();
    DormlyThemeMode.mode.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    DormlyThemeMode.mode.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    if (!mounted) return;
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
