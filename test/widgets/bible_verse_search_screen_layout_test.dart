import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BibleVerseSearchScreen layout', () {
    test('verse grid draws vertical dividers over full-width cells', () {
      final source = File(
        'lib/screens/bible_verse_search_screen.dart',
      ).readAsStringSync();

      expect(source, contains('class _VerseGridVerticalDividers'));
      expect(source, contains('Positioned.fill('));
      expect(source, contains('IgnorePointer('));
      expect(source, contains('alignment: Alignment.centerRight'));
      expect(source, isNot(contains('const _VerseGridVerticalDivider()')));
      expect(source, contains('const EdgeInsets.only(left: 3, top: 3)'));
      expect(
        source,
        contains("ValueKey('verse-search-selection-fill-\$verseNo')"),
      );
      expect(source, contains('ProfileEventReviewGrid('));
      expect(source, isNot(contains('mainAxisExtent: 188')));
    });
  });
}
