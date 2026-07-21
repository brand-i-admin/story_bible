import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:story_bible/data/font_scale_repository.dart';
import 'package:story_bible/state/font_scale_providers.dart';

class _MockFontScaleRepository extends Mock implements FontScaleRepository {}

void main() {
  group('FontScale enum', () {
    test('각 단계의 ratio 값이 정확하다', () {
      expect(FontScale.normal.ratio, 1.0);
      expect(FontScale.large.ratio, 1.2);
      expect(FontScale.veryLarge.ratio, 1.4);
    });

    test('라벨은 한국어로 표시된다', () {
      expect(FontScale.normal.label, '작게');
      expect(FontScale.large.label, '보통');
      expect(FontScale.veryLarge.label, '크게');
    });

    test('storageKey는 사용자에게 보이는 크기 의미와 동일하다', () {
      expect(FontScale.normal.storageKey, 'small');
      expect(FontScale.large.storageKey, 'normal');
      expect(FontScale.veryLarge.storageKey, 'large');
    });

    group('fromStorage', () {
      test('현재 저장 키는 대응되는 enum으로 복원된다', () {
        expect(FontScale.fromStorage('small'), FontScale.normal);
        expect(FontScale.fromStorage('normal'), FontScale.large);
        expect(FontScale.fromStorage('large'), FontScale.veryLarge);
      });

      test('이전 veryLarge 저장 키는 가장 큰 단계로 복원된다', () {
        expect(FontScale.fromStorage('veryLarge'), FontScale.veryLarge);
      });

      test('null은 기본 크기인 large로 복원된다', () {
        expect(FontScale.fromStorage(null), FontScale.large);
      });

      test('알 수 없는 값은 기본 크기인 large로 복원된다', () {
        expect(FontScale.fromStorage('xlarge'), FontScale.large);
        expect(FontScale.fromStorage(''), FontScale.large);
      });
    });
  });

  group('FontScaleNotifier', () {
    late _MockFontScaleRepository repo;

    setUpAll(() {
      registerFallbackValue(FontScale.normal);
    });

    setUp(() {
      repo = _MockFontScaleRepository();
      when(() => repo.write(any())).thenAnswer((_) async {});
    });

    ProviderContainer makeContainer(FontScale initial) {
      when(repo.read).thenReturn(initial);
      return ProviderContainer(
        overrides: [fontScaleRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test('build()는 저장소의 현재 값을 초기 상태로 사용한다', () {
      final container = makeContainer(FontScale.large);
      addTearDown(container.dispose);

      expect(container.read(fontScaleProvider), FontScale.large);
      verify(repo.read).called(1);
    });

    test('set()은 state를 갱신하고 저장소에 기록한다', () async {
      final container = makeContainer(FontScale.normal);
      addTearDown(container.dispose);

      await container.read(fontScaleProvider.notifier).set(FontScale.large);

      expect(container.read(fontScaleProvider), FontScale.large);
      verify(() => repo.write(FontScale.large)).called(1);
    });

    test('set()을 동일한 값으로 호출하면 write를 생략한다', () async {
      final container = makeContainer(FontScale.normal);
      addTearDown(container.dispose);

      await container.read(fontScaleProvider.notifier).set(FontScale.normal);

      verifyNever(() => repo.write(any()));
    });
  });
}
