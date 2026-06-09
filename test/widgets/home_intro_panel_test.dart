import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/widgets/v2/home_intro_panel.dart';

const _eras = [
  Era(
    id: 'era_exodus',
    code: 'era_exodus',
    testament: 'old',
    name: '출애굽 시대',
    displayOrder: 3,
    startYear: -1446,
    endYear: -1406,
    mapCenterLat: 30.0,
    mapCenterLng: 35.0,
    mapZoom: 5.0,
  ),
  Era(
    id: 'era_divided_kingdom',
    code: 'era_divided_kingdom',
    testament: 'old',
    name: '분열왕국 시대',
    displayOrder: 6,
    startYear: -930,
    endYear: -586,
    mapCenterLat: 32.2,
    mapCenterLng: 35.25,
    mapZoom: 5.7,
  ),
];

void main() {
  testWidgets('시간 순 버튼은 timeline 모드를 선택한다', (tester) async {
    SelectionMode? pickedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: 'era_divided_kingdom',
              onSelectEra: (_) {},
              onPickMode: (mode) => pickedMode = mode,
            ),
          ),
        ),
      ),
    );

    expect(find.text('시간 순'), findsOneWidget);
    expect(find.text('선택한 시대의 사건을 시간 순으로 봅니다'), findsOneWidget);
    expect(find.text('인물과 걷기'), findsOneWidget);
    expect(find.text('선택한 인물들의 사건을 비교합니다'), findsOneWidget);
    expect(find.text('장소로 시작'), findsOneWidget);
    expect(find.text('한 장소에서 이야기를 시간 순으로 봅니다'), findsOneWidget);
    expect(
      tester.getCenter(find.text('시간 순')).dx,
      lessThan(tester.getCenter(find.text('인물과 걷기')).dx),
    );
    expect(
      tester.getCenter(find.text('인물과 걷기')).dx,
      lessThan(tester.getCenter(find.text('장소로 시작')).dx),
    );

    await tester.tap(find.text('시간 순'));
    expect(pickedMode, SelectionMode.timeline);
  });

  testWidgets('선택된 시대 단계는 흐려진 뒤 다시 눌러도 시대를 바꾸지 않는다', (tester) async {
    var selectCount = 0;
    SelectionMode? pickedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: HomeIntroPanel(
              eras: _eras,
              selectedEraId: 'era_divided_kingdom',
              onSelectEra: (_) => selectCount++,
              onPickMode: (mode) => pickedMode = mode,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('출애굽 시대'), warnIfMissed: false);
    await tester.tap(find.text('분열왕국 시대'), warnIfMissed: false);

    expect(selectCount, 0);

    await tester.tap(find.text('장소로 시작'));
    expect(pickedMode, SelectionMode.region);
  });
}
