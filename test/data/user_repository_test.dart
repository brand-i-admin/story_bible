import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/data/user_repository.dart';

void main() {
  group('cleanNullableText', () {
    test('null을 null로 유지', () {
      expect(cleanNullableText(null), isNull);
    });

    test('빈 문자열은 null 반환', () {
      expect(cleanNullableText(''), isNull);
    });

    test('공백만 있는 문자열은 null 반환', () {
      expect(cleanNullableText('   '), isNull);
      expect(cleanNullableText('\t\n'), isNull);
    });

    test('유효한 텍스트는 trim만 적용', () {
      expect(cleanNullableText('  hello  '), 'hello');
      expect(cleanNullableText('world'), 'world');
    });
  });

  group('normalizeImageExtension', () {
    test('jpg 변종을 jpg로 정규화', () {
      expect(normalizeImageExtension('jpg'), 'jpg');
      expect(normalizeImageExtension('JPG'), 'jpg');
      expect(normalizeImageExtension('jpeg'), 'jpg');
      expect(normalizeImageExtension('.jpg'), 'jpg');
      expect(normalizeImageExtension('.JPEG'), 'jpg');
    });

    test('webp는 그대로', () {
      expect(normalizeImageExtension('webp'), 'webp');
      expect(normalizeImageExtension('WEBP'), 'webp');
      expect(normalizeImageExtension('.webp'), 'webp');
    });

    test('png는 그대로', () {
      expect(normalizeImageExtension('png'), 'png');
      expect(normalizeImageExtension('PNG'), 'png');
    });

    test('미지원 확장자는 png로 폴백', () {
      expect(normalizeImageExtension('bmp'), 'png');
      expect(normalizeImageExtension('gif'), 'png');
      expect(normalizeImageExtension(''), 'png');
    });
  });

  group('contentTypeForImageExtension', () {
    test('jpg → image/jpeg', () {
      expect(contentTypeForImageExtension('jpg'), 'image/jpeg');
    });

    test('webp → image/webp', () {
      expect(contentTypeForImageExtension('webp'), 'image/webp');
    });

    test('그 외 → image/png', () {
      expect(contentTypeForImageExtension('png'), 'image/png');
      expect(contentTypeForImageExtension('unknown'), 'image/png');
    });
  });

  group('companion diary helpers', () {
    test('동행 일지 제목과 본문은 trim 후 최대 길이로 제한', () {
      expect(normalizeCompanionDiaryTitle('  오늘의 동행  '), '오늘의 동행');
      expect(normalizeCompanionDiaryTitle('가' * 81).length, 80);

      expect(normalizeCompanionDiaryBody('  본문  '), '본문');
      expect(normalizeCompanionDiaryBody('나' * 1001).length, 1000);
    });

    test('동행 일지 날짜 키는 날짜만 yyyy-mm-dd로 변환', () {
      expect(companionDiaryDateKey(DateTime(2026, 6, 3, 22)), '2026-06-03');
      expect(companionDiaryDateKey(DateTime(2026, 12, 25)), '2026-12-25');
    });
  });
}
