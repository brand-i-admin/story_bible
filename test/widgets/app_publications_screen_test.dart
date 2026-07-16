import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/app_publication.dart';
import 'package:story_bible/screens/app_publications_screen.dart';
import 'package:story_bible/screens/legal_documents_screen.dart';
import 'package:story_bible/state/app_publication_providers.dart';
import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';

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

Widget _wrap(
  List<AppPublication> publications, {
  AppColorPalette palette = AppColorPalette.classic,
}) {
  return ProviderScope(
    overrides: [
      publishedAppPublicationsProvider.overrideWith((ref) async {
        return publications;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light(palette: palette),
      home: const AppPublicationsScreen(),
    ),
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
    final outerCard = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('app-publications-outer-surface')),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = outerCard.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('개인정보 보호 페이지의 본문 외곽선을 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const LegalDocumentsScreen()),
    );
    await tester.pump();

    final panel = tester.widget<Container>(
      find.byKey(const ValueKey('legal-documents-outer-surface')),
    );
    final decoration = panel.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets('개인정보 처리방침은 Firebase 분석·진단과 작성 내용 제외를 안내한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const LegalDocumentsScreen()),
    );
    await tester.pump();

    await tester.tap(find.text('개인정보 처리방침'));
    await tester.pumpAndSettle();

    expect(find.textContaining('감정 메모, 신앙 다이어리 제목·본문, 기도제목'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Google Firebase Analytics 및 Crashlytics'),
      findsOneWidget,
    );
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

  testWidgets('블랙 팔레트에서는 공지 리스트 카드가 어두운 표면을 사용한다', (tester) async {
    await tester.pumpWidget(
      _wrap([_publication()], palette: AppColorPalette.blackMap),
    );
    await tester.pump();

    final cardInk = tester.widget<Ink>(
      find
          .ancestor(of: find.text('가이드 및 튜토리얼'), matching: find.byType(Ink))
          .first,
    );
    final decoration = cardInk.decoration as BoxDecoration;
    final title = tester.widget<Text>(find.text('가이드 및 튜토리얼'));

    expect(decoration.color, AppColorPalette.blackMap.cardSurface);
    expect(title.style?.color, AppColorPalette.blackMap.text);
  });

  testWidgets('블랙 팔레트에서는 법적 안내 화면도 어두운 표면을 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(palette: AppColorPalette.blackMap),
        home: const LegalDocumentsScreen(),
      ),
    );
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final title = tester.widget<Text>(find.text('법적 안내'));
    final cardInk = tester.widget<Ink>(
      find
          .ancestor(of: find.text('서비스 이용약관'), matching: find.byType(Ink))
          .first,
    );
    final decoration = cardInk.decoration as BoxDecoration;

    expect(scaffold.backgroundColor, AppColorPalette.blackMap.pageBottom);
    expect(title.style?.color, AppColorPalette.blackMap.text);
    expect(decoration.color, AppColorPalette.blackMap.cardSurface);
  });
}
