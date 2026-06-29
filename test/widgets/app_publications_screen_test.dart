import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/app_publication.dart';
import 'package:story_bible/screens/app_publications_screen.dart';
import 'package:story_bible/state/app_publication_providers.dart';

AppPublication _publication() {
  return AppPublication(
    id: 'publication_1',
    slug: 'guide-and-tutorial',
    category: AppPublicationCategory.guide,
    title: '가이드 및 튜토리얼',
    body:
        '처음 사용하신다면 홈에서 시대를 고른 뒤 시간 순, 인물과 걷기, 장소로 시작 중 하나를 선택해 보세요.\n'
        '다양한 활용 예시는 아래 가이드 페이지에서 확인하세요.',
    linkUrl: 'https://brand-i-admin.github.io/story-bible-pages/',
    displayOrder: 1,
    publishedAt: DateTime.parse('2026-06-29T00:00:00Z'),
    createdAt: DateTime.parse('2026-06-29T00:00:00Z'),
  );
}

Widget _wrap(List<AppPublication> publications) {
  return ProviderScope(
    overrides: [
      publishedAppPublicationsProvider.overrideWith((ref) async {
        return publications;
      }),
    ],
    child: const MaterialApp(home: AppPublicationsScreen()),
  );
}

void main() {
  testWidgets('공지 목록은 제목과 본문 일부를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap([_publication()]));
    await tester.pump();

    expect(find.text('공지사항과 사용법'), findsOneWidget);
    expect(find.text('가이드 및 튜토리얼'), findsOneWidget);
    expect(find.textContaining('처음 사용하신다면 홈에서 시대를 고른 뒤'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
  });

  testWidgets('공지 항목을 누르면 상세 팝업에서 URL 줄을 자동 링크로 보여준다', (tester) async {
    await tester.pumpWidget(_wrap([_publication()]));
    await tester.pump();

    await tester.tap(find.text('가이드 및 튜토리얼'));
    await tester.pumpAndSettle();

    expect(find.text('공지사항 상세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-publication-open-link-button')),
      findsNothing,
    );
    expect(
      find.text('https://brand-i-admin.github.io/story-bible-pages/'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('app-publication-link-url')),
      findsOneWidget,
    );
  });
}
