import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/bible_ref.dart';

void main() {
  group('BibleRef', () {
    test('단일 절은 displayText에 from만 표시', () {
      const ref = BibleRef(book: '창', from: '1:1', to: '1:1');
      expect(ref.displayText, '창 1:1');
    });

    test('범위 참조는 from-to 형식', () {
      const ref = BibleRef(book: '창', from: '1:1', to: '2:3');
      expect(ref.displayText, '창 1:1-2:3');
    });

    test('fromMap은 jsonb 형태 그대로 파싱', () {
      final ref = BibleRef.fromMap(<String, dynamic>{
        'book': '요',
        'from': '3:16',
        'to': '3:16',
      });
      expect(ref.book, '요');
      expect(ref.from, '3:16');
      expect(ref.to, '3:16');
      expect(ref.displayText, '요 3:16');
    });

    test('fromMap은 누락된 키를 빈 문자열로 처리한다', () {
      final ref = BibleRef.fromMap(<String, dynamic>{'book': '시'});
      expect(ref.book, '시');
      expect(ref.from, '');
      expect(ref.to, '');
    });

    test('fromList는 jsonb 배열을 List<BibleRef>로 변환', () {
      final refs = BibleRef.fromList(<dynamic>[
        {'book': '창', 'from': '1:1', 'to': '2:3'},
        {'book': '요', 'from': '1:1', 'to': '1:14'},
      ]);
      expect(refs, hasLength(2));
      expect(refs[0].displayText, '창 1:1-2:3');
      expect(refs[1].displayText, '요 1:1-1:14');
    });

    test('fromList는 null 입력을 빈 리스트로 처리', () {
      expect(BibleRef.fromList(null), isEmpty);
    });

    test('fromList는 dict가 아닌 항목을 무시한다', () {
      final refs = BibleRef.fromList(<dynamic>[
        {'book': '창', 'from': '1:1', 'to': '1:1'},
        '문자열 무시',
        42,
      ]);
      expect(refs, hasLength(1));
      expect(refs.single.book, '창');
    });
  });
}
