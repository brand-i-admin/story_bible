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
import 'package:story_bible/utils/bible_book_meta.dart';
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

    setUpAll(() {
      registerFallbackValue(
        _verse(bookNo: 1, bookName: '창세기', chapterNo: 1, verseNo: 1),
      );
    });

    setUp(() {
      storyRepository = _MockStoryRepository();
      userRepository = _MockUserRepository();

      when(
        () => userRepository.fetchSavedVerseMap('user-1'),
      ).thenAnswer((_) async => const <String, SavedBibleVerse>{});
      when(
        () => userRepository.saveBibleVerse(
          userId: 'user-1',
          verse: any(named: 'verse'),
          comment: any(named: 'comment'),
        ),
      ).thenAnswer((invocation) async {
        final verse = invocation.namedArguments[#verse] as BibleVerse;
        final comment = invocation.namedArguments[#comment] as String;
        return SavedBibleVerse(
          id: 'saved-${verse.verseNo}',
          userId: 'user-1',
          translation: verse.translation,
          bookNo: verse.bookNo,
          bookName: verse.bookName,
          chapterNo: verse.chapterNo,
          verseNo: verse.verseNo,
          verseText: verse.verseText,
          comment: comment,
          createdAt: DateTime.parse('2026-05-26T00:00:00Z'),
        );
      });
      when(
        () => userRepository.deleteSavedVerse(any()),
      ).thenAnswer((_) async {});
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
        () => storyRepository.fetchBibleVersesByChapter(
          translation: 'KRV',
          bookNo: 1,
          chapterNo: 2,
        ),
      ).thenAnswer(
        (_) async => List.generate(
          30,
          (index) => _verse(
            bookNo: 1,
            bookName: '창세기',
            chapterNo: 2,
            verseNo: index + 1,
            text:
                '테스트 본문 ${index + 1} 긴 본문이 이어져 실제 성경 리더처럼 '
                '여러 줄 높이를 가진 절입니다. 자동 포커스가 화면 밖의 절도 '
                '찾아야 합니다.',
          ),
        ),
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
              comment: '',
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

    testWidgets('비로그인 상태에서는 별표와 저장 목록 버튼이 로그인 유도를 요청한다', (tester) async {
      var loginPromptCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(null),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: MaterialApp(
            home: BibleReaderPage(
              onLoginRequired: (_) {
                loginPromptCount += 1;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border_rounded));
      await tester.pump();
      expect(loginPromptCount, 1);

      await tester.tap(find.byIcon(Icons.menu_book_rounded));
      await tester.pump();
      expect(loginPromptCount, 2);
      expect(find.text('저장한 말씀'), findsNothing);
    });

    testWidgets('별표로 저장할 때 묵상 코멘트를 입력해 함께 저장한다', (tester) async {
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

      await tester.tap(find.byIcon(Icons.star_border_rounded));
      await tester.pumpAndSettle();

      expect(find.text('말씀을 저장할까요?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '오늘 붙잡고 싶은 약속입니다.');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      verify(
        () => userRepository.saveBibleVerse(
          userId: 'user-1',
          verse: any(named: 'verse'),
          comment: '오늘 붙잡고 싶은 약속입니다.',
        ),
      ).called(1);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('저장되었어요.'), findsOneWidget);
    });

    testWidgets('저장 코멘트가 없으면 확인 팝업 없이 바로 저장 취소한다', (tester) async {
      final saved = SavedBibleVerse(
        id: 'saved-1',
        userId: 'user-1',
        translation: 'KRV',
        bookNo: 1,
        bookName: '창세기',
        chapterNo: 1,
        verseNo: 1,
        verseText: '테스트 본문 1',
        createdAt: DateTime.parse('2026-05-26T00:00:00Z'),
      );
      when(
        () => userRepository.fetchSavedVerseMap('user-1'),
      ).thenAnswer((_) async => {saved.key: saved});

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

      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      verify(() => userRepository.deleteSavedVerse('saved-1')).called(1);
      expect(find.text('말씀 저장을 취소할까요?'), findsNothing);
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
      expect(find.text('저장된 코멘트가 없어서 바로 구절 저장을 취소했어요.'), findsOneWidget);
    });

    testWidgets('저장 코멘트가 있으면 저장 취소 전 확인 팝업을 띄운다', (tester) async {
      final saved = SavedBibleVerse(
        id: 'saved-1',
        userId: 'user-1',
        translation: 'KRV',
        bookNo: 1,
        bookName: '창세기',
        chapterNo: 1,
        verseNo: 1,
        verseText: '테스트 본문 1',
        comment: '힘들 때 다시 읽고 싶어서',
        createdAt: DateTime.parse('2026-05-26T00:00:00Z'),
      );
      when(
        () => userRepository.fetchSavedVerseMap('user-1'),
      ).thenAnswer((_) async => {saved.key: saved});

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

      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      expect(find.text('말씀 저장을 취소할까요?'), findsOneWidget);
      expect(find.textContaining("'힘들 때 다시 읽고 싶어서' 코멘트가 있는데"), findsOneWidget);

      await tester.tap(find.text('저장 취소'));
      await tester.pumpAndSettle();

      verify(() => userRepository.deleteSavedVerse('saved-1')).called(1);
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    });

    testWidgets('초기 절 번호가 있으면 해당 절을 본문 목록 상단으로 올린다', (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: const MaterialApp(
            home: BibleReaderPage(
              initialBookNo: 1,
              initialChapterNo: 2,
              initialVerseNo: 16,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listTop = tester.getTopLeft(find.byType(ListView)).dy;
      final verseTop = tester.getTopLeft(find.textContaining('테스트 본문 16')).dy;

      expect(find.text('창세기 2장'), findsOneWidget);
      expect(verseTop, lessThanOrEqualTo(listTop + 40));
    });

    testWidgets('사건 읽기 모드는 지정된 본문 범위만 보여준다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: MaterialApp(
            home: BibleReaderPage(
              readingTargets: [parseBibleNavigationTarget('창 2:3-4')!],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('창세기 2:3-4'), findsOneWidget);
      expect(find.textContaining('테스트 본문 3 긴 본문'), findsOneWidget);
      expect(find.textContaining('테스트 본문 4 긴 본문'), findsOneWidget);
      expect(find.textContaining('테스트 본문 2 긴 본문'), findsNothing);
      expect(find.textContaining('테스트 본문 5 긴 본문'), findsNothing);
      expect(find.text('읽기 완료'), findsOneWidget);
      expect(find.text('다음 장'), findsNothing);
    });

    testWidgets('여러 사건 본문은 다음으로 넘긴 뒤 마지막에서 읽기 완료를 보여준다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: MaterialApp(
            home: BibleReaderPage(
              readingTargets: [
                parseBibleNavigationTarget('창 2:3')!,
                parseBibleNavigationTarget('창 45:1')!,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/2 · 창세기 2:3'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('읽기 완료'), findsNothing);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(find.text('2/2 · 창세기 45:1'), findsOneWidget);
      expect(find.textContaining('요셉이 시종하는 자들 앞에서'), findsOneWidget);
      expect(find.text('읽기 완료'), findsOneWidget);
    });

    testWidgets('읽기 완료로 닫을 때만 완료 결과를 반환한다', (tester) async {
      bool? completed;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInUserProvider.overrideWithValue(user),
            storyRepositoryProvider.overrideWithValue(storyRepository),
            userRepositoryProvider.overrideWithValue(userRepository),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    completed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => BibleReaderPage(
                          readingTargets: [
                            parseBibleNavigationTarget('창 2:3')!,
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();

      expect(completed, isNull);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('읽기 완료'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
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
