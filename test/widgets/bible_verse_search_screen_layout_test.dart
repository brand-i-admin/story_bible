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
    });
  });
}
