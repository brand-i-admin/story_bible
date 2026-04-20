import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/person.dart';
import 'package:story_bible/models/person_study_progress.dart';

void main() {
  const testPerson = Person(
    id: 'p1',
    code: 'adam',
    name: '아담',
    tagline: '최초의 사람',
    description: null,
    avatarUrl: null,
    avatarThumbUrl: null,
    displayOrder: 1,
  );

  group('PersonStudyProgress.fraction', () {
    test('totalCount가 0이면 0.0을 반환한다', () {
      const progress = PersonStudyProgress(
        person: testPerson,
        completedCount: 0,
        totalCount: 0,
      );
      expect(progress.fraction, 0.0);
    });

    test('totalCount가 음수여도 0.0을 반환한다', () {
      const progress = PersonStudyProgress(
        person: testPerson,
        completedCount: 3,
        totalCount: -1,
      );
      expect(progress.fraction, 0.0);
    });

    test('일부 완료 시 비율을 정확히 계산한다', () {
      const progress = PersonStudyProgress(
        person: testPerson,
        completedCount: 3,
        totalCount: 10,
      );
      expect(progress.fraction, closeTo(0.3, 1e-9));
    });

    test('전부 완료 시 1.0을 반환한다', () {
      const progress = PersonStudyProgress(
        person: testPerson,
        completedCount: 5,
        totalCount: 5,
      );
      expect(progress.fraction, 1.0);
    });

    test('미완료 시 0.0을 반환한다', () {
      const progress = PersonStudyProgress(
        person: testPerson,
        completedCount: 0,
        totalCount: 7,
      );
      expect(progress.fraction, 0.0);
    });
  });
}
