import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/app.dart';
import 'package:story_bible/state/font_scale_providers.dart';

void main() {
  testWidgets(
    'fontScaleBuilder는 fontScaleProvider의 ratio를 MediaQuery.textScaler로 주입한다',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'font_scale': 'large',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(
            builder: fontScaleBuilder,
            home: Scaffold(body: Text('probe')),
          ),
        ),
      );

      final BuildContext innerContext = tester.element(find.text('probe'));
      final textScaler = MediaQuery.textScalerOf(innerContext);

      expect(textScaler.scale(10), closeTo(12.0, 0.001));
    },
  );

  testWidgets('fontScaleBuilder는 저장값이 없으면 normal(1.0×)을 사용한다', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          builder: fontScaleBuilder,
          home: Scaffold(body: Text('probe')),
        ),
      ),
    );

    final BuildContext innerContext = tester.element(find.text('probe'));
    final textScaler = MediaQuery.textScalerOf(innerContext);

    expect(textScaler.scale(10), closeTo(10.0, 0.001));
  });
}
