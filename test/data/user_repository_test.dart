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

  group('dateOnly', () {
    test('시/분/초를 0으로 맞춰 날짜만 남긴다', () {
      final result = dateOnly(DateTime(2026, 4, 16, 13, 45, 30));
      expect(result, DateTime(2026, 4, 16));
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });
  });

  group('computeDailyStreak', () {
    test('빈 rows면 0', () {
      expect(computeDailyStreak(const [], 'attended_on'), 0);
    });

    test('오늘과 어제 모두 없으면 0 (연속 끊김)', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final rows = [
        {'attended_on': twoDaysAgo.toIso8601String().split('T').first},
      ];
      expect(computeDailyStreak(rows, 'attended_on'), 0);
    });

    test('오늘 포함 연속 3일', () {
      final today = dateOnly(DateTime.now());
      final rows = [
        {
          'attended_on': today
              .subtract(const Duration(days: 2))
              .toIso8601String()
              .split('T')
              .first,
        },
        {
          'attended_on': today
              .subtract(const Duration(days: 1))
              .toIso8601String()
              .split('T')
              .first,
        },
        {'attended_on': today.toIso8601String().split('T').first},
      ];
      expect(computeDailyStreak(rows, 'attended_on'), 3);
    });

    test('어제 시작 연속 2일 (오늘은 미출석)', () {
      final today = dateOnly(DateTime.now());
      final rows = [
        {
          'attended_on': today
              .subtract(const Duration(days: 2))
              .toIso8601String()
              .split('T')
              .first,
        },
        {
          'attended_on': today
              .subtract(const Duration(days: 1))
              .toIso8601String()
              .split('T')
              .first,
        },
      ];
      expect(computeDailyStreak(rows, 'attended_on'), 2);
    });

    test('중간에 빠지면 오늘부터 연속된 것만 집계', () {
      final today = dateOnly(DateTime.now());
      final rows = [
        {
          'attended_on': today
              .subtract(const Duration(days: 5))
              .toIso8601String()
              .split('T')
              .first,
        },
        {
          'attended_on': today
              .subtract(const Duration(days: 4))
              .toIso8601String()
              .split('T')
              .first,
        },
        // gap: -3일 누락
        {
          'attended_on': today
              .subtract(const Duration(days: 1))
              .toIso8601String()
              .split('T')
              .first,
        },
        {'attended_on': today.toIso8601String().split('T').first},
      ];
      expect(computeDailyStreak(rows, 'attended_on'), 2);
    });

    test('중복 날짜는 1회로 집계', () {
      final today = dateOnly(DateTime.now());
      final todayStr = today.toIso8601String().split('T').first;
      final rows = [
        {'attended_on': todayStr},
        {'attended_on': todayStr},
        {'attended_on': todayStr},
      ];
      expect(computeDailyStreak(rows, 'attended_on'), 1);
    });
  });
}
