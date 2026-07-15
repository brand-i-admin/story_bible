import 'package:flutter/material.dart';

import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/bible_book_meta.dart';
import '../widgets/parchment_page_scaffold.dart';
import '../widgets/story_home_styles.dart';

typedef BibleProgressChapterOpenCallback =
    Future<void> Function({required int bookNo, required int chapterNo});

class BibleProgressScreen extends StatefulWidget {
  const BibleProgressScreen({
    super.key,
    required this.completedChapterKeys,
    required this.initialBookNo,
    required this.onOpenChapter,
  });

  final Set<String> completedChapterKeys;
  final int initialBookNo;
  final BibleProgressChapterOpenCallback onOpenChapter;

  @override
  State<BibleProgressScreen> createState() => _BibleProgressScreenState();
}

class _BibleProgressScreenState extends State<BibleProgressScreen> {
  late int _selectedBookNo;
  late String _selectedTestament;

  @override
  void initState() {
    super.initState();
    _selectedBookNo = widget.initialBookNo.clamp(1, bibleBooks.length).toInt();
    _selectedTestament = isNewTestamentBook(_selectedBookNo) ? 'new' : 'old';
  }

  @override
  Widget build(BuildContext context) {
    final bookNumbers = _bookNumbersForTestament(_selectedTestament);
    if (!bookNumbers.contains(_selectedBookNo)) {
      _selectedBookNo = bookNumbers.first;
    }
    final book = bibleBooks[_selectedBookNo - 1];
    final completedChapters = {
      for (var chapter = 1; chapter <= book.chapters; chapter += 1)
        if (widget.completedChapterKeys.contains(
          bibleChapterProgressKey(bookNo: _selectedBookNo, chapterNo: chapter),
        ))
          chapter,
    };
    final fraction = book.chapters == 0
        ? 0.0
        : (completedChapters.length / book.chapters).clamp(0.0, 1.0).toDouble();
    return ParchmentListPageScaffold(
      title: '통독 진행률',
      bodyPadding: const EdgeInsets.fromLTRB(
        AppSpacing.x5,
        62,
        AppSpacing.x5,
        AppSpacing.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BibleProgressPickerRow(
            selectedTestament: _selectedTestament,
            selectedBookNo: _selectedBookNo,
            bookNumbers: bookNumbers,
            onTestamentChanged: (testament) {
              setState(() {
                _selectedTestament = testament;
                _selectedBookNo = _bookNumbersForTestament(testament).first;
              });
            },
            onBookChanged: (bookNo) {
              setState(() => _selectedBookNo = bookNo);
            },
          ),
          const SizedBox(height: AppSpacing.x5),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BibleChapterProgressGrid(
                    chapterCount: book.chapters,
                    completedChapters: completedChapters,
                    onChapterTap: _openChapter,
                  ),
                  const SizedBox(height: AppSpacing.x5),
                  _BibleBookProgressFooter(
                    bookName: book.name,
                    completed: completedChapters.length,
                    total: book.chapters,
                    fraction: fraction,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChapter(int chapterNo) async {
    final navigator = Navigator.of(context);
    final bookNo = _selectedBookNo;
    if (navigator.canPop()) {
      navigator.pop();
    }
    await widget.onOpenChapter(bookNo: bookNo, chapterNo: chapterNo);
  }
}

class _BibleProgressPickerRow extends StatelessWidget {
  const _BibleProgressPickerRow({
    required this.selectedTestament,
    required this.selectedBookNo,
    required this.bookNumbers,
    required this.onTestamentChanged,
    required this.onBookChanged,
  });

  final String selectedTestament;
  final int selectedBookNo;
  final List<int> bookNumbers;
  final ValueChanged<String> onTestamentChanged;
  final ValueChanged<int> onBookChanged;

  @override
  Widget build(BuildContext context) {
    final safeBookNo = bookNumbers.contains(selectedBookNo)
        ? selectedBookNo
        : bookNumbers.first;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return ParchmentCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: bibleDropdownFrame<String>(
              value: selectedTestament,
              items: const [
                DropdownMenuItem(value: 'old', child: Text('구약')),
                DropdownMenuItem(value: 'new', child: Text('신약')),
              ],
              onChanged: (value) {
                if (value != null) {
                  onTestamentChanged(value);
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: bibleDropdownFrame<int>(
              value: safeBookNo,
              items: [
                for (final bookNo in bookNumbers)
                  DropdownMenuItem<int>(
                    value: bookNo,
                    child: Text(
                      bibleBooks[bookNo - 1].name,
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onBookChanged(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BibleChapterProgressGrid extends StatelessWidget {
  const _BibleChapterProgressGrid({
    required this.chapterCount,
    required this.completedChapters,
    required this.onChapterTap,
  });

  final int chapterCount;
  final Set<int> completedChapters;
  final ValueChanged<int> onChapterTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 10
            : (constraints.maxWidth >= 460 ? 8 : 6);
        final rowCount = (chapterCount / columns).ceil();
        final palette = AppPaletteTheme.of(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.softSurface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: palette.subtleBorder),
            ),
            child: Column(
              children: [
                for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) ...[
                  if (rowIndex > 0) const _BibleChapterHorizontalDivider(),
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        for (
                          var columnIndex = 0;
                          columnIndex < columns;
                          columnIndex += 1
                        ) ...[
                          Expanded(
                            child: _BibleChapterGridCell(
                              chapter: rowIndex * columns + columnIndex + 1,
                              chapterCount: chapterCount,
                              completedChapters: completedChapters,
                              onTap: onChapterTap,
                            ),
                          ),
                          if (columnIndex < columns - 1)
                            const _BibleChapterVerticalDivider(),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BibleChapterGridCell extends StatelessWidget {
  const _BibleChapterGridCell({
    required this.chapter,
    required this.chapterCount,
    required this.completedChapters,
    required this.onTap,
  });

  final int chapter;
  final int chapterCount;
  final Set<int> completedChapters;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (chapter > chapterCount) {
      return const SizedBox.shrink();
    }
    final palette = AppPaletteTheme.of(context);
    final completed = completedChapters.contains(chapter);
    return Semantics(
      button: true,
      label: '$chapter장 성경 열기',
      child: InkWell(
        key: ValueKey('bible-progress-chapter-$chapter'),
        onTap: () => onTap(chapter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          color: completed ? palette.successFill : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$chapter',
                  style: TextStyle(
                    color: completed
                        ? palette.successBottom
                        : palette.mutedText,
                    fontSize: AppFontSizes.body,
                    fontWeight: completed ? FontWeight.w900 : FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (completed) ...[
                  const SizedBox(width: AppSpacing.x2),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: palette.successBottom,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BibleBookProgressFooter extends StatelessWidget {
  const _BibleBookProgressFooter({
    required this.bookName,
    required this.completed,
    required this.total,
    required this.fraction,
  });

  final String bookName;
  final int completed;
  final int total;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x5),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: palette.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$bookName 통독',
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: AppTextStyles.sectionTitle.copyWith(
                  color: palette.successBottom,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: fraction.clamp(0.0, 1.0).toDouble(),
              backgroundColor: palette.successFill,
              color: palette.successBottom,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '$completed / $total장',
            textAlign: TextAlign.right,
            style: AppTextStyles.counter.copyWith(color: palette.mutedText),
          ),
        ],
      ),
    );
  }
}

class _BibleChapterHorizontalDivider extends StatelessWidget {
  const _BibleChapterHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: palette.subtleBorder),
    );
  }
}

class _BibleChapterVerticalDivider extends StatelessWidget {
  const _BibleChapterVerticalDivider();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        color: palette.subtleBorder,
      ),
    );
  }
}

List<int> _bookNumbersForTestament(String testament) {
  final firstBookNo = testament == 'new'
      ? newTestamentFirstBookNo
      : oldTestamentFirstBookNo;
  final lastBookNo = testament == 'new'
      ? newTestamentLastBookNo
      : oldTestamentLastBookNo;
  return List<int>.generate(
    lastBookNo - firstBookNo + 1,
    (index) => firstBookNo + index,
  );
}
