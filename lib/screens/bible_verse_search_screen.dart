import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bible_verse.dart';
import '../models/story_event.dart';
import '../state/story_controller.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';
import '../widgets/parchment_texture_layer.dart';
import '../widgets/profile/profile_event_review_grid.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/sub_page_floating_home_button.dart';

const int _oldTestamentFirstBookNo = 1;
const int _oldTestamentLastBookNo = 39;
const int _newTestamentFirstBookNo = 40;
const int _newTestamentLastBookNo = 66;
const Color _verseGridLineColor = Color(0x228E6F48);

class BibleVerseSearchScreen extends ConsumerStatefulWidget {
  const BibleVerseSearchScreen({super.key, required this.onOpenEventDetail});

  final Future<void> Function(StoryEvent event) onOpenEventDetail;

  @override
  ConsumerState<BibleVerseSearchScreen> createState() =>
      _BibleVerseSearchScreenState();
}

class _BibleVerseSearchScreenState
    extends ConsumerState<BibleVerseSearchScreen> {
  static const int _maxFallbackVerse = 176;

  String _selectedTestament = 'old';
  int _selectedBookNo = 1;
  int _selectedChapterNo = 1;
  int _selectedVerseNo = 1;
  List<int> _verseNumbers = const [1];
  Map<int, BibleVerse> _versesByNo = const {};
  bool _loadingVerseNumbers = false;
  String? _verseNumberError;
  Future<List<StoryEvent>>? _resultsFuture;
  int _verseLoadSerial = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadVerseNumbersAndSearch);
  }

  Future<void> _loadVerseNumbersAndSearch() async {
    final serial = ++_verseLoadSerial;
    final bookNo = _selectedBookNo;
    final chapterNo = _selectedChapterNo;
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingVerseNumbers = true;
      _verseNumberError = null;
    });

    try {
      final verses = await ref
          .read(storyRepositoryProvider)
          .fetchBibleVersesByChapter(bookNo: bookNo, chapterNo: chapterNo);
      if (!mounted ||
          serial != _verseLoadSerial ||
          bookNo != _selectedBookNo ||
          chapterNo != _selectedChapterNo) {
        return;
      }
      final numbers =
          verses
              .map((verse) => verse.verseNo)
              .where((verseNo) => verseNo > 0)
              .toSet()
              .toList()
            ..sort();
      final nextNumbers = numbers.isEmpty ? _fallbackVerseNumbers() : numbers;
      setState(() {
        _verseNumbers = nextNumbers;
        _versesByNo = {
          for (final verse in verses)
            if (verse.verseNo > 0) verse.verseNo: verse,
        };
        if (!_verseNumbers.contains(_selectedVerseNo)) {
          _selectedVerseNo = _verseNumbers.first;
        }
        _loadingVerseNumbers = false;
      });
      _refreshResults();
    } catch (_) {
      if (!mounted || serial != _verseLoadSerial) {
        return;
      }
      setState(() {
        _verseNumbers = _fallbackVerseNumbers();
        _versesByNo = const {};
        if (!_verseNumbers.contains(_selectedVerseNo)) {
          _selectedVerseNo = 1;
        }
        _loadingVerseNumbers = false;
        _verseNumberError = '절 목록을 불러오지 못해 기본 범위로 표시합니다.';
      });
      _refreshResults();
    }
  }

  List<int> _fallbackVerseNumbers() {
    return List<int>.generate(_maxFallbackVerse, (index) => index + 1);
  }

  void _refreshResults() {
    final repo = ref.read(storyRepositoryProvider);
    setState(() {
      _resultsFuture = repo.fetchEventsContainingBibleVerse(
        bookNo: _selectedBookNo,
        chapterNo: _selectedChapterNo,
        verseNo: _selectedVerseNo,
      );
    });
  }

  void _selectTestament(String testament) {
    if (testament == _selectedTestament) {
      return;
    }
    final nextBookNo = testament == 'new'
        ? _newTestamentFirstBookNo
        : _oldTestamentFirstBookNo;
    setState(() {
      _selectedTestament = testament;
      _selectedBookNo = nextBookNo;
      _selectedChapterNo = 1;
      _selectedVerseNo = 1;
      _verseNumbers = const [1];
      _versesByNo = const {};
    });
    _loadVerseNumbersAndSearch();
  }

  void _selectBook(int bookNo) {
    final maxChapter = bibleBooks[bookNo - 1].chapters;
    setState(() {
      _selectedTestament = bookNo >= _newTestamentFirstBookNo ? 'new' : 'old';
      _selectedBookNo = bookNo;
      _selectedChapterNo = _selectedChapterNo.clamp(1, maxChapter).toInt();
      _selectedVerseNo = 1;
      _verseNumbers = const [1];
      _versesByNo = const {};
    });
    _loadVerseNumbersAndSearch();
  }

  void _selectChapter(int chapterNo) {
    setState(() {
      _selectedChapterNo = chapterNo;
      _selectedVerseNo = 1;
      _verseNumbers = const [1];
      _versesByNo = const {};
    });
    _loadVerseNumbersAndSearch();
  }

  void _selectVerse(int verseNo) {
    setState(() {
      _selectedVerseNo = verseNo;
    });
    _refreshResults();
  }

  Future<void> _openEvent(StoryEvent event) async {
    await ref.read(storyControllerProvider.notifier).selectSearchResult(event);
    if (!mounted) {
      return;
    }
    await widget.onOpenEventDetail(event);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final charactersByCode = {for (final c in state.characters) c.code: c};

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.parchmentLight,
                    AppColors.parchmentMid,
                    AppColors.parchmentWarm,
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: ParchmentTextureLayer(
                opacity: 0.08,
                tint: AppColors.brownWarm2,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth >= 980
                      ? 4
                      : (constraints.maxWidth >= 560 ? 3 : 2);
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _SearchHeader(
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.x2),
                      ),
                      SliverToBoxAdapter(
                        child: _VersePickerPanel(
                          selectedTestament: _selectedTestament,
                          selectedBookNo: _selectedBookNo,
                          selectedChapterNo: _selectedChapterNo,
                          onTestamentChanged: _selectTestament,
                          onBookChanged: _selectBook,
                          onChapterChanged: _selectChapter,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.x4),
                      ),
                      SliverToBoxAdapter(
                        child: _VerseButtonGrid(
                          selectedVerseNo: _selectedVerseNo,
                          verseNumbers: _verseNumbers,
                          loadingVerseNumbers: _loadingVerseNumbers,
                          verseNumberError: _verseNumberError,
                          onVerseChanged: _selectVerse,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.x3),
                      ),
                      SliverToBoxAdapter(
                        child: _SelectedVersePreview(
                          bookNo: _selectedBookNo,
                          chapterNo: _selectedChapterNo,
                          verseNo: _selectedVerseNo,
                          verse: _versesByNo[_selectedVerseNo],
                          loading: _loadingVerseNumbers,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.x5),
                      ),
                      SliverToBoxAdapter(
                        child: _resultsFuture == null
                            ? const _ResultStatus(
                                message: '구절을 고르면 관련 이야기를 찾아드립니다.',
                              )
                            : FutureBuilder<List<StoryEvent>>(
                                future: _resultsFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const _ResultStatus(
                                      message: '이 구절이 들어간 이야기를 찾고 있습니다.',
                                      loading: true,
                                    );
                                  }
                                  if (snapshot.hasError) {
                                    return _ResultStatus(
                                      message: '검색 중 문제가 생겼습니다.',
                                      actionLabel: '다시 검색',
                                      onAction: _refreshResults,
                                    );
                                  }
                                  final events =
                                      snapshot.data ?? const <StoryEvent>[];
                                  return ProfileEventReviewGrid(
                                    events: events,
                                    eras: state.eras,
                                    charactersByCode: charactersByCode,
                                    completedEventIds: state.completedEventIds,
                                    eventEmotionMarks: state.eventEmotionMarks,
                                    quizAttemptSummaries:
                                        state.quizAttemptSummaries,
                                    onOpenEventDetail: _openEvent,
                                    emptyText: '이 구절을 포함하는 이야기가 아직 없습니다.',
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      0,
                                      2,
                                      28,
                                    ),
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent: 226,
                                    scrollable: false,
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SubPageFloatingHomeButton(onTap: onBack),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 60),
            child: Text(
              '성경 구절로 찾는 이야기',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.ink800,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersePickerPanel extends StatelessWidget {
  const _VersePickerPanel({
    required this.selectedTestament,
    required this.selectedBookNo,
    required this.selectedChapterNo,
    required this.onTestamentChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
  });

  final String selectedTestament;
  final int selectedBookNo;
  final int selectedChapterNo;
  final ValueChanged<String> onTestamentChanged;
  final ValueChanged<int> onBookChanged;
  final ValueChanged<int> onChapterChanged;

  @override
  Widget build(BuildContext context) {
    final bookNumbers = _bookNumbersForTestament(selectedTestament);
    final safeBookNo = bookNumbers.contains(selectedBookNo)
        ? selectedBookNo
        : bookNumbers.first;
    final maxChapter = bibleBooks[safeBookNo - 1].chapters;
    final safeChapter = selectedChapterNo.clamp(1, maxChapter).toInt();
    final chapters = List<int>.generate(maxChapter, (index) => index + 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
                onChanged: (v) => v != null ? onTestamentChanged(v) : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 156,
              child: bibleDropdownFrame<int>(
                value: safeBookNo,
                items: [
                  for (final bookNo in bookNumbers)
                    DropdownMenuItem<int>(
                      value: bookNo,
                      child: Text(
                        bibleBooks[bookNo - 1].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => v != null ? onBookChanged(v) : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: bibleDropdownFrame<int>(
                value: safeChapter,
                items: [
                  for (final chapter in chapters)
                    DropdownMenuItem<int>(
                      value: chapter,
                      child: Text('$chapter장'),
                    ),
                ],
                onChanged: (v) => v != null ? onChapterChanged(v) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseButtonGrid extends StatelessWidget {
  const _VerseButtonGrid({
    required this.selectedVerseNo,
    required this.verseNumbers,
    required this.loadingVerseNumbers,
    required this.verseNumberError,
    required this.onVerseChanged,
  });

  final int selectedVerseNo;
  final List<int> verseNumbers;
  final bool loadingVerseNumbers;
  final String? verseNumberError;
  final ValueChanged<int> onVerseChanged;

  @override
  Widget build(BuildContext context) {
    final numbers = verseNumbers.isEmpty ? const [1] : verseNumbers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720
                ? 12
                : (constraints.maxWidth >= 560
                      ? 10
                      : (constraints.maxWidth >= 430 ? 8 : 6));
            final rowCount = (numbers.length / columns).ceil();
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.parchmentCream.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: _verseGridLineColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) ...[
                      if (rowIndex > 0) const _VerseGridHorizontalDivider(),
                      SizedBox(
                        height: 42,
                        child: Row(
                          children: [
                            for (
                              var colIndex = 0;
                              colIndex < columns;
                              colIndex++
                            ) ...[
                              Expanded(
                                child: _verseAt(
                                  numbers,
                                  columns,
                                  rowIndex,
                                  colIndex,
                                ),
                              ),
                              if (colIndex < columns - 1)
                                const _VerseGridVerticalDivider(),
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
        ),
        if (loadingVerseNumbers) ...[
          const SizedBox(height: AppSpacing.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.greenBorder,
            ),
          ),
        ],
        if (verseNumberError != null) ...[
          const SizedBox(height: AppSpacing.x3),
          Text(
            verseNumberError!,
            style: const TextStyle(
              color: AppColors.ink300,
              fontSize: AppFontSizes.sm,
              fontWeight: FontWeight.w700,
              height: AppLineHeights.normal,
            ),
          ),
        ],
      ],
    );
  }

  Widget _verseAt(List<int> numbers, int columns, int rowIndex, int colIndex) {
    final index = rowIndex * columns + colIndex;
    if (index >= numbers.length) {
      return const SizedBox.shrink();
    }
    final verseNo = numbers[index];
    return _VerseButton(
      verseNo: verseNo,
      selected: verseNo == selectedVerseNo,
      onTap: () => onVerseChanged(verseNo),
    );
  }
}

class _SelectedVersePreview extends StatelessWidget {
  const _SelectedVersePreview({
    required this.bookNo,
    required this.chapterNo,
    required this.verseNo,
    required this.verse,
    required this.loading,
  });

  final int bookNo;
  final int chapterNo;
  final int verseNo;
  final BibleVerse? verse;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reference = '${_shortBibleBookName(bookNo)} $chapterNo:$verseNo';
    final verseText = verse?.verseText.trim();
    final body = verseText != null && verseText.isNotEmpty
        ? verseText
        : (loading ? '본문을 불러오는 중입니다.' : '본문 데이터가 아직 없습니다.');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Container(
          key: ValueKey('$reference-$body'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.floatingSurfaceDefault.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.borderCard, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.greenTint1.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.greenBorder, width: 0.9),
                ),
                child: Text(
                  reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.greenBot,
                    fontSize: AppFontSizes.sm,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(
                  body,
                  style: TextStyle(
                    color: verseText == null || verseText.isEmpty
                        ? AppColors.ink300
                        : AppColors.ink600,
                    fontSize: AppFontSizes.sm,
                    fontWeight: FontWeight.w800,
                    height: AppLineHeights.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseButton extends StatelessWidget {
  const _VerseButton({
    required this.verseNo,
    required this.selected,
    required this.onTap,
  });

  final int verseNo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$verseNo절',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            alignment: Alignment.center,
            color: selected
                ? AppColors.greenTint1.withValues(alpha: 0.86)
                : Colors.transparent,
            child: Text(
              '$verseNo',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: selected ? AppColors.greenBot : AppColors.ink500,
                fontSize: AppFontSizes.body,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerseGridHorizontalDivider extends StatelessWidget {
  const _VerseGridHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 7,
      alignment: Alignment.center,
      child: Container(height: 1, color: _verseGridLineColor),
    );
  }
}

class _VerseGridVerticalDivider extends StatelessWidget {
  const _VerseGridVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      alignment: Alignment.center,
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: _verseGridLineColor,
      ),
    );
  }
}

List<int> _bookNumbersForTestament(String testament) {
  final firstBookNo = testament == 'new'
      ? _newTestamentFirstBookNo
      : _oldTestamentFirstBookNo;
  final lastBookNo = testament == 'new'
      ? _newTestamentLastBookNo
      : _oldTestamentLastBookNo;
  return List<int>.generate(
    lastBookNo - firstBookNo + 1,
    (index) => firstBookNo + index,
  );
}

String _shortBibleBookName(int bookNo) {
  if (bookNo < 1 || bookNo > bibleBooks.length) {
    return '성경';
  }
  for (final entry in bibleRefAliasBookLookup.entries) {
    if (entry.value == bookNo) {
      return entry.key;
    }
  }
  return bibleBooks[bookNo - 1].name;
}

class _ResultStatus extends StatelessWidget {
  const _ResultStatus({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(AppSpacing.x8),
        decoration: floatingPanelDecoration(
          color: AppColors.floatingSurfaceDefault,
          shadowOpacity: 0.06,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(height: AppSpacing.x5),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink400,
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w800,
                height: AppLineHeights.normal,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.x6),
              filledActionButton(
                label: actionLabel!,
                onTap: onAction!,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
