import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/landmark.dart';
import 'package:story_bible/widgets/v2/region_pick_panel.dart';

void main() {
  testWidgets('분열왕국 시대에서 북이스라엘과 남유다 region을 선택할 수 있다', (tester) async {
    Landmark? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: RegionPickPanel(
              allEras: const [
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
              ],
              selectedEraIds: const {'era_divided_kingdom'},
              selectedLandmarkId: null,
              regions: const [
                Landmark(
                  id: 'rgn_div_north_israel',
                  code: 'rgn_div_north_israel',
                  name: '북이스라엘',
                  emoji: '🟦',
                  lat: 32.4,
                  lng: 35.2,
                  displayPriority: 120,
                  eraCodes: ['era_divided_kingdom'],
                  relatedEventCodes: [],
                  kind: 'region',
                  description: '분열왕국 시대의 북쪽 왕국',
                ),
                Landmark(
                  id: 'rgn_div_south_judah',
                  code: 'rgn_div_south_judah',
                  name: '남유다',
                  emoji: '🟨',
                  lat: 31.8,
                  lng: 35.2,
                  displayPriority: 118,
                  eraCodes: ['era_divided_kingdom'],
                  relatedEventCodes: [],
                  kind: 'region',
                  description: '분열왕국 시대의 남쪽 유다 왕국',
                ),
              ],
              onSelect: (landmark) => selected = landmark,
            ),
          ),
        ),
      ),
    );

    expect(find.text('분열왕국 시대'), findsOneWidget);
    expect(find.text('2곳'), findsOneWidget);
    expect(find.text('북이스라엘'), findsOneWidget);
    expect(find.text('남유다'), findsOneWidget);

    await tester.tap(find.text('남유다'));
    expect(selected?.id, 'rgn_div_south_judah');

    await tester.tap(find.text('북이스라엘'));
    expect(selected?.id, 'rgn_div_north_israel');
  });
}
