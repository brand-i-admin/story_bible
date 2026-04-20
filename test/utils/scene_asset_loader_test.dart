import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/utils/scene_asset_loader.dart';

void main() {
  late SceneAssetLoader loader;

  setUp(() {
    loader = SceneAssetLoader();
  });

  group('sceneDirectoryNameForTitle', () {
    test('일반 제목은 그대로 반환', () {
      expect(loader.sceneDirectoryNameForTitle('창조_ 7일과 안식'), '창조_ 7일과 안식');
    });

    test('잘못된 문자(\\/:*?"<>|)는 _로 치환', () {
      expect(loader.sceneDirectoryNameForTitle('제목:부제/설명'), '제목_부제_설명');
    });

    test('앞뒤 점(.)은 제거', () {
      expect(loader.sceneDirectoryNameForTitle('..제목..'), '제목');
    });

    test('연속 공백은 단일 공백으로 축소', () {
      expect(
        loader.sceneDirectoryNameForTitle('여러   공백   있는   제목'),
        '여러 공백 있는 제목',
      );
    });

    test('빈 문자열이면 untitled_event 반환', () {
      expect(loader.sceneDirectoryNameForTitle(''), 'untitled_event');
    });

    test('특수문자만 있으면 치환 결과를 반환 (:::→_)', () {
      expect(loader.sceneDirectoryNameForTitle(':::'), '_');
    });
  });

  group('normalizeSceneLookupKey', () {
    test('소문자로 변환하고 구분자를 제거', () {
      expect(loader.normalizeSceneLookupKey('ABC_DEF-GHI'), 'abcdefghi');
    });

    test('한글은 그대로 보존 (구분자만 제거)', () {
      expect(loader.normalizeSceneLookupKey('창조_ 7일과 안식'), '창조7일과안식');
    });

    test('콜론, 쉼표, 괄호 등 제거', () {
      expect(
        loader.normalizeSceneLookupKey("title: (sub) [note] 'q'"),
        'titlesubnoteq',
      );
    });

    test('빈 문자열은 빈 문자열 반환', () {
      expect(loader.normalizeSceneLookupKey(''), '');
    });
  });

  group('stripSceneDirectoryPrefix', () {
    test('숫자 접두사를 제거한다', () {
      expect(loader.stripSceneDirectoryPrefix('001 창조_ 7일과 안식'), '창조_ 7일과 안식');
    });

    test('숫자 없으면 그대로 반환', () {
      expect(loader.stripSceneDirectoryPrefix('창조_ 7일과 안식'), '창조_ 7일과 안식');
    });

    test('숫자만 있으면 빈 문자열', () {
      expect(loader.stripSceneDirectoryPrefix('001'), '');
    });

    test('빈 문자열은 빈 문자열', () {
      expect(loader.stripSceneDirectoryPrefix(''), '');
    });
  });

  group('scenePrefixForCode', () {
    test('코드 끝의 숫자를 3자리 패딩', () {
      expect(loader.scenePrefixForCode('EVT1'), '001');
      expect(loader.scenePrefixForCode('EVT42'), '042');
      expect(loader.scenePrefixForCode('EVT215'), '215');
    });

    test('숫자가 없으면 null', () {
      expect(loader.scenePrefixForCode('NONUM'), isNull);
    });

    test('빈 문자열이면 null', () {
      expect(loader.scenePrefixForCode(''), isNull);
    });

    test('앞뒤 공백을 trim', () {
      expect(loader.scenePrefixForCode('  EVT5  '), '005');
    });
  });
}
