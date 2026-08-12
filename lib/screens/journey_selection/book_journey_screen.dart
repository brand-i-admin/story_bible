import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/journey_selection.dart';
import '../../state/journey_selection_providers.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/bible_book_meta.dart';
import '../../utils/story_visibility.dart';
import '../../widgets/journey/journey_filter_controls.dart';
import '../../widgets/sub_page_scaffold.dart';
import 'target_journey_scope_screen.dart';

class BookJourneyScreen extends ConsumerStatefulWidget {
  const BookJourneyScreen({
    super.key,
    required this.catalog,
    required this.engravedEventIds,
  });

  final JourneyCatalogData catalog;
  final Set<String> engravedEventIds;

  @override
  ConsumerState<BookJourneyScreen> createState() => _BookJourneyScreenState();
}

class _BookJourneyScreenState extends ConsumerState<BookJourneyScreen> {
  String _testament = 'old';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final current = ref.read(journeySelectionProvider);
    final selectedBook = current.bookName;
    if (current.source == JourneySource.book && selectedBook != null) {
      final bookNo =
          bibleBooks.indexWhere((book) => book.name == selectedBook) + 1;
      if (bookNo >= newTestamentFirstBookNo) {
        _testament = 'new';
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(journeySelectionProvider);
    final counts = _bookEventCounts();
    final firstIndex = _testament == 'old'
        ? oldTestamentFirstBookNo - 1
        : newTestamentFirstBookNo - 1;
    final lastIndex = _testament == 'old'
        ? oldTestamentLastBookNo - 1
        : newTestamentLastBookNo - 1;
    final query = _searchQuery.trim();
    final candidateBooks = query.isEmpty
        ? bibleBooks.sublist(firstIndex, lastIndex + 1)
        : bibleBooks;
    final books = candidateBooks
        .where((book) => query.isEmpty || book.name.contains(query))
        .toList(growable: false);
    return SubPageScaffold(
      title: '성경책에서 시작하기',
      plainHeader: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x10,
        ),
        children: [
          JourneySearchField(
            controlKey: const ValueKey('journey-book-search'),
            controller: _searchController,
            hintText: '성경책 이름을 검색해 보세요',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              Expanded(
                child: JourneySegmentButton(
                  controlKey: const ValueKey('journey-book-testament-old'),
                  label: '구약',
                  selected: _testament == 'old',
                  onTap: () => setState(() => _testament = 'old'),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: JourneySegmentButton(
                  controlKey: const ValueKey('journey-book-testament-new'),
                  label: '신약',
                  selected: _testament == 'new',
                  onTap: () => setState(() => _testament = 'new'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x5),
          if (books.isEmpty)
            const JourneySearchEmptyState()
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: AppSpacing.x3,
                mainAxisSpacing: AppSpacing.x3,
                childAspectRatio: 1.55,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                final count = counts[book.name] ?? 0;
                return _BookButton(
                  bookName: book.name,
                  eventCount: count,
                  selected:
                      current.source == JourneySource.book &&
                      current.bookName == book.name,
                  onTap: count == 0 ? null : () => _openBook(book.name),
                );
              },
            ),
        ],
      ),
    );
  }

  Map<String, int> _bookEventCounts() {
    final counts = <String, int>{};
    for (final event in visibleStoryEvents(
      events: widget.catalog.events,
      eras: widget.catalog.eras,
    )) {
      final names = canonicalBibleBookNames(
        event.bibleRefs.map((reference) => reference.book),
      );
      for (final name in names.toSet()) {
        counts.update(name, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  Future<void> _openBook(String bookName) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TargetJourneyScopeScreen.book(
          bookName: bookName,
          catalog: widget.catalog,
          engravedEventIds: widget.engravedEventIds,
        ),
      ),
    );
  }
}

class _BookButton extends StatelessWidget {
  const _BookButton({
    required this.bookName,
    required this.eventCount,
    required this.selected,
    required this.onTap,
  });

  final String bookName;
  final int eventCount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final enabled = onTap != null;
    return Material(
      key: ValueKey('journey-book-$bookName'),
      color: selected
          ? palette.utilitySelectedBackground
          : enabled
          ? palette.cardSurface
          : palette.disabledSurface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected
                  ? palette.selectedBorder
                  : enabled
                  ? palette.subtleBorder
                  : palette.disabledBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    bookName,
                    maxLines: 2,
                    softWrap: true,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? palette.activeTextOnAccent
                          : enabled
                          ? palette.text
                          : palette.disabledText,
                      fontSize: AppFontSizes.sm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    '$eventCount개',
                    style: TextStyle(
                      color: selected
                          ? palette.activeTextOnAccent.withValues(alpha: 0.88)
                          : enabled
                          ? palette.mutedText
                          : palette.disabledText,
                      fontSize: AppFontSizes.xs,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: palette.activeTextOnAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
