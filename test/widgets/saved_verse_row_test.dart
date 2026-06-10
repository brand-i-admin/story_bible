import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/saved_bible_verse.dart';
import 'package:story_bible/widgets/saved_verse_row.dart';

SavedBibleVerse _verse() {
  return SavedBibleVerse(
    id: 'saved_1',
    userId: 'user_1',
    translation: 'KRV',
    bookNo: 1,
    bookName: '창세기',
    chapterNo: 41,
    verseNo: 1,
    verseText: '만 이년 후에 바로가 꿈을 꾼즉 자기가 하숫가에 섰는데',
    comment: '기다림 끝에 하나님이 일하시는 장면이라 저장했습니다.',
    createdAt: DateTime.parse('2026-05-26T09:00:00Z'),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('SavedVerseRow 기본 참조 배지는 본문 첫 줄 옆에 작게 표시한다', (tester) async {
    await tester.pumpWidget(_wrap(SavedVerseRow(verse: _verse())));

    final badge = find.byKey(const ValueKey('saved-verse-reference-badge'));

    expect(badge, findsOneWidget);
    expect(tester.getSize(badge), const Size(32, 32));
    expect(find.text('창'), findsOneWidget);
    expect(find.text('41:1'), findsOneWidget);
    expect(find.textContaining('기다림 끝에'), findsOneWidget);
  });

  testWidgets('SavedVerseRow compact 참조 배지는 더 작게 표시한다', (tester) async {
    await tester.pumpWidget(
      _wrap(SavedVerseRow(verse: _verse(), compact: true)),
    );

    final badge = find.byKey(const ValueKey('saved-verse-reference-badge'));

    expect(badge, findsOneWidget);
    expect(tester.getSize(badge), const Size(28, 28));
  });

  testWidgets('저장 코멘트가 없으면 회색 안내 문구를 표시한다', (tester) async {
    final verse = SavedBibleVerse(
      id: 'saved_1',
      userId: 'user_1',
      translation: 'KRV',
      bookNo: 1,
      bookName: '창세기',
      chapterNo: 41,
      verseNo: 1,
      verseText: '만 이년 후에 바로가 꿈을 꾼즉 자기가 하숫가에 섰는데',
      createdAt: DateTime.parse('2026-05-26T09:00:00Z'),
    );

    await tester.pumpWidget(_wrap(SavedVerseRow(verse: verse)));

    final emptyComment = find.text('남긴 코멘트가 없습니다.');

    expect(emptyComment, findsOneWidget);
    final text = tester.widget<Text>(emptyComment);
    expect(text.style?.color, isNotNull);
  });
}
