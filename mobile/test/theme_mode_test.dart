import 'package:dormly/core/theme/theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const dark = Color(0xFF0B0F17);
  const light = Color(0xFFF6F7FB);

  test('fresh install defaults to the light theme', () async {
    SharedPreferences.setMockInitialValues({});
    await DormlyThemeMode.load();
    expect(DormlyThemeMode.isDark, isFalse);
    expect(themed(dark, light), light);
  });

  test('toggle switches instantly and persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    await DormlyThemeMode.load();

    await DormlyThemeMode.toggle();
    expect(DormlyThemeMode.isDark, isTrue);
    expect(themed(dark, light), dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('darkTheme'), isTrue);

    DormlyThemeMode.mode.value = ThemeMode.light;
    await DormlyThemeMode.load();
    expect(DormlyThemeMode.isDark, isTrue);

    await DormlyThemeMode.toggle();
    expect(DormlyThemeMode.isDark, isFalse);
    expect(prefs.getBool('darkTheme'), isFalse);
  });

  testWidgets('rebuilder repaints getter-based colours on toggle',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DormlyThemeMode.load();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DormlyThemeRebuilder(child: child!),
        home: const _Swatch(),
      ),
    );
    Color current() => tester
        .widget<ColoredBox>(find.byKey(const ValueKey('swatch')))
        .color;

    expect(current(), light);
    await DormlyThemeMode.setDark(true);
    await tester.pump();
    expect(current(), dark);
    await DormlyThemeMode.setDark(false);
    await tester.pump();
    expect(current(), light);
  });
}

class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const ValueKey('swatch'),
        color: themed(const Color(0xFF0B0F17), const Color(0xFFF6F7FB)),
      );
}
