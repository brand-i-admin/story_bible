import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_bible/data/journey_selection_repository.dart';
import 'package:story_bible/models/journey_selection.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  test('선택한 여정을 앱 재시작용 저장소에 기록하고 복원한다', () async {
    final repository = JourneySelectionRepository(preferences);
    const selection = JourneySelection(
      source: JourneySource.person,
      scope: JourneyScope.targetOnly,
      personCode: 'paul',
      personName: '바울',
    );

    await repository.write(selection);

    final restored = repository.read();
    expect(restored.source, JourneySource.person);
    expect(restored.scope, JourneyScope.targetOnly);
    expect(restored.personCode, 'paul');
    expect(restored.personName, '바울');
  });

  test('저장값이 없거나 깨졌으면 전체 순서를 사용한다', () async {
    final repository = JourneySelectionRepository(preferences);
    expect(repository.read().source, JourneySource.all);

    await preferences.setString(JourneySelectionRepository.key, '{broken');
    expect(repository.read().source, JourneySource.all);
  });
}
