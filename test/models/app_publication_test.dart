import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/app_publication.dart';

void main() {
  group('AppPublication.fromMap', () {
    test('게시 문서 row를 파싱한다', () {
      final publication = AppPublication.fromMap({
        'id': 'notice_1',
        'slug': 'guide-and-tutorial',
        'category': 'guide',
        'title': '가이드 및 튜토리얼',
        'body': '환영합니다.',
        'link_url': 'https://brand-i-admin.github.io/story-bible-pages/',
        'link_label': '가이드 페이지 열기',
        'display_order': 1,
        'published_at': '2026-06-29T00:00:00Z',
        'created_at': '2026-06-28T00:00:00Z',
      });

      expect(publication.id, 'notice_1');
      expect(publication.slug, 'guide-and-tutorial');
      expect(publication.category, AppPublicationCategory.guide);
      expect(publication.title, '가이드 및 튜토리얼');
      expect(
        publication.linkUrl,
        'https://brand-i-admin.github.io/story-bible-pages/',
      );
      expect(publication.displayOrder, 1);
      expect(publication.displayDate.year, 2026);
      expect(publication.displayDate.month, 6);
      expect(publication.displayDate.day, 29);
    });

    test('빈 링크와 알 수 없는 category는 안전하게 정리한다', () {
      final publication = AppPublication.fromMap({
        'id': 'notice_2',
        'slug': 'notice-2',
        'category': 'unknown',
        'title': '공지',
        'body': '본문',
        'link_url': '   ',
        'created_at': '2026-06-29T00:00:00Z',
      });

      expect(publication.category, AppPublicationCategory.notice);
      expect(publication.linkUrl, isNull);
      expect(publication.linkLabel, isNull);
      expect(publication.displayDate, publication.createdAt);
    });
  });
}
