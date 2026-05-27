import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/bible_verse.dart';
import 'package:story_bible/models/paged_result.dart';
import 'package:story_bible/models/saved_bible_verse.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';
import 'package:story_bible/widgets/bible_reader_page.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

void main() {
  group('BibleReaderPage 저장 구절 이동', () {
    late _MockStoryRepository storyRepository;
    late _MockUserRepository userRepository;

    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-05-26T00:00:00Z',
    );

    setUp(() {
      storyRepository = _MockStoryRepository();
      userRepository = _MockUserRepository();

      when(
        () => userRepository.fetchSavedVerseKeys('user-1'),
      ).thenAnswer((_) async => const <String>{});
      when(
        () => storyRepository.fetchBibleVersesByChapter(
          translation: 'KRV',
          bookNo: 1,
          chapterNo: 1,
        ),
      ).thenAnswer(
        (_) async => [
          _verse(bookNo: 1, bookName: '창세기', chapterNo: 1, verseNo: 1),
        ],
      );
      when(
        () => storyRepository.fetchBibleVersesByChapter(
          translation: 'KRV',
          bookNo: 1,
          chapterNo: 45,
        ),
      ).thenAnswer(
        (_) async => [
          _verse(
            bookNo: 1,
            bookName: '창세기',
            chapterNo: 45,
            verseNo: 1,
            text: '요셉이 시종하는 자들 앞에서 그 정을 억제하지 못하여',
          ),
        ],
      );
      when(
        () => userRepository.fetchSavedVersesPage(
          userId: 'user-1',
          pageIndex: 0,
          pageSize: 10,
        ),
      ).thenAnswer(
        (_) async => PagedResult<SavedBibleVerse>(
          items: [
            SavedBibleVerse(
              id: 'saved-1',
              userId: 'user-1',
              translation: 'KRV',
              bookNo: 1,
              bookName: '창세기',
              chapterNo: 45,
              verseNo: 1,
              verseText: '요셉이 시종하는 자들 앞에서 그 정을 억제하지 못하여',
              createdAt: DateTime.parse('2026-05-26T00:00:00Z'),
            ),
          ],
          pageIndex: 0,
          pageSize: 10,
          hasNextPage: false,
        ),
      );
    });

    testWidgets('저장 목록 로우를 누르면 해당 장으로 이동한다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: const MaterialApp(home: BibleReaderPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('창세기 1장'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_book_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('요셉이 시종하는'));
      await tester.pumpAndSettle();

      expect(find.text('창세기 45장'), findsOneWidget);
      expect(find.textContaining('요셉이 시종하는 자들 앞에서'), findsOneWidget);
    });

    testWidgets('본문 절을 눌러도 범위 저장 선택이 시작되지 않는다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: const MaterialApp(home: BibleReaderPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('테스트 본문 1'));
      await tester.pump();

      expect(find.text('끝 절을 선택하세요'), findsNothing);
    });
  });
}

BibleVerse _verse({
  required int bookNo,
  required String bookName,
  required int chapterNo,
  required int verseNo,
  String? text,
}) {
  return BibleVerse(
    translation: 'KRV',
    bookNo: bookNo,
    bookName: bookName,
    chapterNo: chapterNo,
    verseNo: verseNo,
    verseText: text ?? '테스트 본문 $verseNo',
  );
}
