// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Project imports:
import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/widgets/font_scale_bottom_sheet.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  FontScale initial = FontScale.normal,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'font_scale': initial.storageKey,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: FontScaleBottomSheet()),
      ),
    ),
  );
  return container;
}

void main() {
  group('FontScaleBottomSheet', () {
    testWidgets('3단계 버튼(작게/보통/크게)을 렌더한다', (tester) async {
      await _pumpSheet(tester);

      expect(find.text('작게'), findsOneWidget);
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('크게'), findsOneWidget);
    });

    testWidgets('현재 선택된 단계에 체크 아이콘을 표시한다', (tester) async {
      await _pumpSheet(tester, initial: FontScale.large);

      final checkIcons = find.byIcon(Icons.check);
      expect(checkIcons, findsOneWidget);

      final checkWidget = tester.widget<Icon>(checkIcons);
      final parentText = find
          .ancestor(
            of: checkIcons,
            matching: find.byKey(const ValueKey('font-scale-button-large')),
          )
          .evaluate();
      expect(parentText, isNotEmpty);
      expect(checkWidget.icon, Icons.check);
    });

    testWidgets('다른 버튼 탭 시 fontScaleProvider.set이 호출된다', (tester) async {
      final container = await _pumpSheet(tester, initial: FontScale.normal);

      await tester.tap(
        find.byKey(const ValueKey('font-scale-button-large')),
      );
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.large);
    });

    testWidgets('동일한 단계 탭은 state를 변경하지 않는다', (tester) async {
      final container = await _pumpSheet(tester, initial: FontScale.normal);

      await tester.tap(
        find.byKey(const ValueKey('font-scale-button-normal')),
      );
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.normal);
    });

    testWidgets('미리보기 Text가 현재 textScaler로 렌더된다', (tester) async {
      await _pumpSheet(tester, initial: FontScale.large);

      expect(find.text('태초에 하나님이 천지를 창조하시니라 (창세기 1:1)'),
          findsOneWidget);
    });
  });
}
