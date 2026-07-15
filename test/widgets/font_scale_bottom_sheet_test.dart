import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/state/color_palette_providers.dart';
import 'package:story_bible/state/font_scale_providers.dart';
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/widgets/font_scale_bottom_sheet.dart';

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  FontScale initial = FontScale.normal,
  AppColorPalette initialPalette = AppColorPalette.classic,
  DisplaySettingsSection? section,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'font_scale': initial.storageKey,
    'color_palette': initialPalette.storageKey,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: FontScaleBottomSheet(section: section)),
      ),
    ),
  );
  return container;
}

void main() {
  group('FontScaleBottomSheet', () {
    testWidgets('색 조합과 글자 크기 섹션을 렌더한다', (tester) async {
      await _pumpSheet(tester);

      expect(find.text('색/글자 설정'), findsOneWidget);
      expect(find.text('색 조합'), findsOneWidget);
      expect(find.text('글자 크기'), findsOneWidget);
      expect(find.text('클래식'), findsOneWidget);
      expect(find.text('네이비'), findsOneWidget);
      expect(find.text('지도 남색'), findsNothing);
      expect(find.text('밝은 해안'), findsNothing);
      expect(find.text('알록 지도'), findsNothing);
      expect(find.text('블랙 지도'), findsNothing);
      expect(find.text('파스텔'), findsOneWidget);
      expect(find.text('다크'), findsOneWidget);
    });

    testWidgets('오늘 헤더의 테마 버튼은 색 조합만 보여준다', (tester) async {
      await _pumpSheet(tester, section: DisplaySettingsSection.theme);

      expect(find.text('테마'), findsOneWidget);
      expect(find.text('색 조합'), findsOneWidget);
      expect(find.text('글자 크기'), findsNothing);
    });

    testWidgets('오늘 헤더의 큰글자 버튼은 글자 크기만 보여준다', (tester) async {
      await _pumpSheet(tester, section: DisplaySettingsSection.font);

      expect(find.text('큰글자'), findsOneWidget);
      expect(find.text('색 조합'), findsNothing);
      expect(find.text('글자 크기'), findsOneWidget);
    });

    testWidgets('색 조합 버튼 4개를 한 줄에 배치한다', (tester) async {
      await _pumpSheet(tester);

      final classic = find.byKey(
        const ValueKey('color-palette-button-classic'),
      );
      final atlas = find.byKey(
        const ValueKey('color-palette-button-atlasNavy'),
      );
      final colorful = find.byKey(
        const ValueKey('color-palette-button-colorfulMap'),
      );
      final black = find.byKey(const ValueKey('color-palette-button-blackMap'));

      expect(classic, findsOneWidget);
      expect(atlas, findsOneWidget);
      expect(colorful, findsOneWidget);
      expect(black, findsOneWidget);
      expect(
        (tester.getTopLeft(classic).dy - tester.getTopLeft(atlas).dy).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        (tester.getTopLeft(atlas).dy - tester.getTopLeft(colorful).dy).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        (tester.getTopLeft(colorful).dy - tester.getTopLeft(black).dy).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        tester.getCenter(classic).dx,
        lessThan(tester.getCenter(atlas).dx),
      );
      expect(
        tester.getCenter(atlas).dx,
        lessThan(tester.getCenter(colorful).dx),
      );
      expect(
        tester.getCenter(colorful).dx,
        lessThan(tester.getCenter(black).dx),
      );
    });

    testWidgets('3단계 버튼(보통/크게/아주크게)을 렌더한다', (tester) async {
      await _pumpSheet(tester);

      expect(find.text('작게'), findsNothing);
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('크게'), findsOneWidget);
      expect(find.text('아주크게'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('1.2x'), findsOneWidget);
      expect(find.text('1.4x'), findsOneWidget);
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
        find.byKey(const ValueKey('font-scale-button-veryLarge')),
      );
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.veryLarge);
    });

    testWidgets('색 조합 버튼 탭 시 colorPaletteProvider.set이 호출된다', (tester) async {
      final container = await _pumpSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('color-palette-button-colorfulMap')),
      );
      await tester.pump();

      expect(container.read(colorPaletteProvider), AppColorPalette.colorfulMap);
    });

    testWidgets('다크 버튼 탭 시 colorPaletteProvider.set이 호출된다', (tester) async {
      final container = await _pumpSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('color-palette-button-blackMap')),
      );
      await tester.pump();

      expect(container.read(colorPaletteProvider), AppColorPalette.blackMap);
    });

    test('다크 색 조합 미리보기는 어두운 표면색을 우선 사용한다', () {
      final colors = paletteWheelPreviewColors(AppColorPalette.blackMap);

      expect(colors, [
        AppColorPalette.blackMap.pageBottom,
        AppColorPalette.blackMap.panelSurface,
        AppColorPalette.blackMap.cardSurface,
        AppColorPalette.blackMap.currentFill,
      ]);
      expect(colors, isNot(contains(AppColorPalette.blackMap.primary)));
      expect(colors, isNot(contains(AppColorPalette.blackMap.stepStory)));
    });

    testWidgets('다크 색 조합에서는 선택 카드들이 어두운 표면을 사용한다', (tester) async {
      await _pumpSheet(tester, initialPalette: AppColorPalette.blackMap);

      final source = find.byKey(const ValueKey('color-palette-button-classic'));
      final paletteButton = tester.widget<Container>(
        find.descendant(of: source, matching: find.byType(Container)).first,
      );
      final paletteDecoration = paletteButton.decoration! as BoxDecoration;
      expect(paletteDecoration.color, AppColorPalette.blackMap.cardSurface);

      final fontScaleSource = find.byKey(
        const ValueKey('font-scale-button-large'),
      );
      final fontScaleButton = tester.widget<Container>(
        find
            .descendant(of: fontScaleSource, matching: find.byType(Container))
            .first,
      );
      final fontScaleDecoration = fontScaleButton.decoration! as BoxDecoration;
      expect(fontScaleDecoration.color, AppColorPalette.blackMap.cardSurface);
    });

    testWidgets('동일한 단계 탭은 state를 변경하지 않는다', (tester) async {
      final container = await _pumpSheet(tester, initial: FontScale.normal);

      await tester.tap(find.byKey(const ValueKey('font-scale-button-normal')));
      await tester.pump();

      expect(container.read(fontScaleProvider), FontScale.normal);
    });

    testWidgets('미리보기 Text는 글자 크기 제목 아래와 크기 버튼 위에 표시된다', (tester) async {
      await _pumpSheet(tester, initial: FontScale.veryLarge);

      expect(find.text('태초에 하나님이 천지를 창조하시니라 (창세기 1:1)'), findsOneWidget);
      final previewTop = tester
          .getTopLeft(find.text('태초에 하나님이 천지를 창조하시니라 (창세기 1:1)'))
          .dy;
      expect(previewTop, greaterThan(tester.getTopLeft(find.text('글자 크기')).dy));
      expect(
        previewTop,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('font-scale-button-normal')),
              )
              .dy,
        ),
      );
    });

    testWidgets('아주크게 상태에서도 바텀시트 overflow가 발생하지 않는다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSheet(tester, initial: FontScale.veryLarge);

      expect(find.text('아주크게'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
