import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atlas_music/services/user_prefs.dart';
import 'package:atlas_music/widgets/floating_glass_nav.dart';
import 'package:atlas_music/widgets/liquid_background.dart';
import 'package:atlas_music/screens/onboarding_screen.dart';

void main() {
  test('name persists locally', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = UserPrefs();
    expect(await prefs.getName(), isNull);
    await prefs.setName('  Ada  ');
    expect(await prefs.getName(), 'Ada');
    await prefs.clearName();
    expect(await prefs.getName(), isNull);
  });

  testWidgets('onboarding shows prompt + glass input + continue',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingContent(onContinue: _noop),
        ),
      ),
    );
    expect(find.text("What's your name?"), findsOneWidget);
    expect(find.byKey(const ValueKey('name_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('name_continue')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('name_input')), 'Ada');
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('floating nav has 4 tabs with active glow', (tester) async {
    int tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: FloatingGlassNav(
            currentIndex: 0,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('nav_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav_3')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav_2')));
    expect(tapped, 2);
  });

  testWidgets('glass panel renders child without overflow on small phone',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: LiquidBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SingleChildScrollView(
              child: GlassPanel(
                radius: 28,
                padding: EdgeInsets.all(16),
                child: SizedBox(height: 200, child: Text('hero')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

void _noop(String _) {}
