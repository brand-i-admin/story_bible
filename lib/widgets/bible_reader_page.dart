import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bible_verse.dart';
import '../models/saved_bible_verse.dart';
import '../screens/saved_verses_screen.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';
import 'saved_verse_actions.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

/// 성경 리더 페이지 (2026-05-10 리디자인).
///
/// 상단 타이틀(책 + 장) + 책/장 칩 드롭다운, 번호 원 + 타임라인 레일을 가진
/// 구절 목록, 그리고 이전/다음 장 액션 바를 제공한다. 히어로 카드는
/// 의도적으로 비워두고, 추후 era/메타 정보가 들어오면 다시 추가할 예정이다.
///
/// **저장 모델**: 우측 별 아이콘으로 단일 구절을 저장/해제한다. 새 저장은
/// optional 묵상 코멘트를 함께 받고, 구절 본문을 탭해도 선택 상태는 만들지 않는다.
///
/// [initialBookNo]/[initialChapterNo]/[initialVerseNo]가 주어지면 해당 구절로
/// 자동 스크롤한다. [highlightTarget]이 있으면 해당 이야기의 읽을 본문 범위를
/// 저장 상태와 별개인 임시 하이라이트로 표시한다. [readingTargets]가 있으면
/// 사건 읽기 모드로 전환해 지정된 절만 보여 주고 마지막 본문에서 완료 결과를
/// 반환한다.
class BibleReaderPage extends ConsumerStatefulWidget {
  const BibleReaderPage({
    super.key,
    this.initialBookNo,
    this.initialChapterNo,
    this.initialVerseNo,
    this.highlightTarget,
    this.readingTargets = const <BibleNavigationTarget>[],
    this.onLoginRequired,
  });

  final int? initialBookNo;
  final int? initialChapterNo;
  final int? initialVerseNo;
  final BibleNavigationTarget? highlightTarget;
  final List<BibleNavigationTarget> readingTargets;
  final void Function(String message)? onLoginRequired;

  @override
  ConsumerState<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends ConsumerState<BibleReaderPage> {
  late int _selectedBookNo;
  late String _selectedTestament;
  late int _selectedChapter;
  late final List<BibleNavigationTarget> _readingTargets;
  int _readingTargetIndex = 0;
  int? _pendingFocusVerse;
  final ScrollController _verseScrollController = ScrollController();
  final Map<String, Future<List<BibleVerse>>> _chapterCache = {};
  Map<String, SavedBibleVerse> _savedVersesByKey =
      const <String, SavedBibleVerse>{};

  @override
  void initState() {
    super.initState();
    _readingTargets = widget.readingTargets;
    final firstReadingTarget = _readingTargets.firstOrNull;
    final initialBookNo =
        firstReadingTarget?.bookNo ??
        widget.initialBookNo ??
        widget.highlightTarget?.bookNo ??
        1;
    _selectedBookNo = initialBookNo.clamp(1, bibleBooks.length).toInt();
    _selectedTestament = _selectedBookNo >= 40 ? 'new' : 'old';
    final maxChapter = bibleBooks[_selectedBookNo - 1].chapters;
    final initialChapter =
        firstReadingTarget?.chapterNo ??
        widget.initialChapterNo ??
        widget.highlightTarget?.chapterNo ??
        1;
    _selectedChapter = initialChapter.clamp(1, maxChapter).toInt();
    final initialVerse =
        firstReadingTarget?.verseNo ??
        widget.initialVerseNo ??
        widget.highlightTarget?.verseNo;
    _pendingFocusVerse = _readingTargets.isEmpty && (initialVerse ?? 0) > 0
        ? initialVerse
        : null;
    _loadSavedVerses();
  }

  @override
  void dispose() {
    _verseScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedVerses() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }
    try {
      final versesByKey = await ref
          .read(userRepositoryProvider)
          .fetchSavedVerseMap(user.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedVersesByKey = versesByKey;
      });
    } catch (_) {
      // 저장 구절을 못 가져와도 리더는 계속 사용 가능
    }
  }

  List<MapEntry<int, BibleBookMeta>> _booksForTestament(String testament) {
    return bibleBooks
        .asMap()
        .entries
        .where((entry) {
          final bookNo = entry.key + 1;
          return testament == 'new' ? bookNo >= 40 : bookNo <= 39;
        })
        .toList(growable: false);
  }

  Future<List<BibleVerse>> _loadVerses({
    required int bookNo,
    required int chapterNo,
  }) {
    final cacheKey = 'KRV:$bookNo:$chapterNo';
    return _chapterCache.putIfAbsent(
      cacheKey,
      () => ref
          .read(storyRepositoryProvider)
          .fetchBibleVersesByChapter(
            translation: 'KRV',
            bookNo: bookNo,
            chapterNo: chapterNo,
          ),
    );
  }

  Future<List<BibleVerse>> _loadVersesForReadingTarget(
    BibleNavigationTarget target,
  ) async {
    final endChapter = target.endChapterNo ?? target.chapterNo;
    final firstChapter = target.chapterNo <= endChapter
        ? target.chapterNo
        : endChapter;
    final lastChapter = target.chapterNo <= endChapter
        ? endChapter
        : target.chapterNo;
    final verses = <BibleVerse>[];
    for (var chapter = firstChapter; chapter <= lastChapter; chapter += 1) {
      final chapterVerses = await _loadVerses(
        bookNo: target.bookNo,
        chapterNo: chapter,
      );
      verses.addAll(
        chapterVerses.where(
          (verse) => target.containsVerse(
            bookNo: verse.bookNo,
            chapterNo: verse.chapterNo,
            verseNo: verse.verseNo,
          ),
        ),
      );
    }
    return verses;
  }

  void _requestLogin(String message) {
    final onLoginRequired = widget.onLoginRequired;
    if (onLoginRequired != null) {
      onLoginRequired(message);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// 우측 별 아이콘 탭 - 단일 절 저장/해제 토글.
  Future<void> _onTapStar(BibleVerse verse) async {
    final verseKey = SavedBibleVerse.buildVerseKey(
      translation: verse.translation,
      bookNo: verse.bookNo,
      chapterNo: verse.chapterNo,
      verseNo: verse.verseNo,
    );
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      _requestLogin('말씀을 저장하려면 로그인이 필요해요.');
      return;
    }

    try {
      final savedVerse = _savedVersesByKey[verseKey];
      if (savedVerse != null) {
        final decision = await confirmSavedVerseDelete(
          context: context,
          verse: savedVerse,
        );
        if (!mounted || !decision.shouldDelete) return;
        await ref.read(userRepositoryProvider).deleteSavedVerse(savedVerse.id);
        if (!mounted) return;
        setState(() {
          _savedVersesByKey = {
            for (final entry in _savedVersesByKey.entries)
              if (entry.key != verseKey) entry.key: entry.value,
          };
        });
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              savedVerseDeleteSuccessMessage(hadComment: decision.hadComment),
            ),
          ),
        );
        return;
      }

      final comment = await showSavedVerseCommentDialog(context);
      if (!mounted) return;
      final nextSavedVerse = await ref
          .read(userRepositoryProvider)
          .saveBibleVerse(userId: user.id, verse: verse, comment: comment);
      if (!mounted) return;
      setState(() {
        _savedVersesByKey = {
          ..._savedVersesByKey,
          nextSavedVerse.key: nextSavedVerse,
        };
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('저장되었어요.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다.\n$error')));
    }
  }

  void _goToChapter(int delta) {
    final maxChapter = bibleBooks[_selectedBookNo - 1].chapters;
    final next = _selectedChapter + delta;
    if (next < 1 || next > maxChapter) return;
    setState(() {
      _selectedChapter = next;
      _pendingFocusVerse = null;
    });
  }

  void _showReadingTarget(BibleNavigationTarget target) {
    final bookNo = target.bookNo.clamp(1, bibleBooks.length).toInt();
    final maxChapter = bibleBooks[bookNo - 1].chapters;
    final chapterNo = target.chapterNo.clamp(1, maxChapter).toInt();
    setState(() {
      _selectedBookNo = bookNo;
      _selectedTestament = bookNo >= 40 ? 'new' : 'old';
      _selectedChapter = chapterNo;
      _pendingFocusVerse = null;
    });
  }

  void _goToNextReadingTarget() {
    if (_readingTargetIndex >= _readingTargets.length - 1) {
      return;
    }
    final nextIndex = _readingTargetIndex + 1;
    _readingTargetIndex = nextIndex;
    _showReadingTarget(_readingTargets[nextIndex]);
  }

  void _completeGuidedReading() {
    Navigator.of(context).pop(true);
  }

  void _focusSavedVerse(SavedBibleVerse verse) {
    final bookNo = verse.bookNo.clamp(1, bibleBooks.length).toInt();
    final maxChapter = bibleBooks[bookNo - 1].chapters;
    final chapterNo = verse.chapterNo.clamp(1, maxChapter).toInt();
    setState(() {
      _selectedBookNo = bookNo;
      _selectedTestament = bookNo >= 40 ? 'new' : 'old';
      _selectedChapter = chapterNo;
      _pendingFocusVerse = verse.verseNo > 0 ? verse.verseNo : null;
    });
  }

  Future<void> _openSavedVerses() async {
    if (!mounted) return;
    if (ref.read(signedInUserProvider) == null) {
      _requestLogin('저장한 말씀을 보려면 로그인이 필요해요.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedVersesScreen(
          onOpenVerse: (verse) async {
            if (!mounted) return;
            _focusSavedVerse(verse);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    // 저장 페이지에서 변경 가능 — 돌아오면 저장 map 새로 고침.
    await _loadSavedVerses();
  }

  @override
  Widget build(BuildContext context) {
    final readingTarget = _readingTargetIndex < _readingTargets.length
        ? _readingTargets[_readingTargetIndex]
        : null;
    final isGuidedReading = readingTarget != null;
    final testamentBooks = _booksForTestament(_selectedTestament);
    final selectedEntry =
        testamentBooks
            .where((entry) => (entry.key + 1) == _selectedBookNo)
            .firstOrNull ??
        testamentBooks.first;
    final selectedBook = selectedEntry.value;
    final selectedBookNoSafe = selectedEntry.key + 1;
    final chapterCount = selectedBook.chapters;
    final chapterItems = List<int>.generate(chapterCount, (i) => i + 1);
    final selectedChapterSafe = _selectedChapter.clamp(1, chapterCount);
    final versesFuture = isGuidedReading
        ? _loadVersesForReadingTarget(readingTarget)
        : _loadVerses(
            bookNo: selectedBookNoSafe,
            chapterNo: selectedChapterSafe,
          );
    final highlightedTarget = readingTarget ?? widget.highlightTarget;

    return SubPageScaffold(
      title: '성경',
      compactBackOnly: true,
      child: Column(
        children: [
          _BibleReaderHeader(
            title: isGuidedReading
                ? _readingTitle(readingTarget)
                : '${selectedBook.name} $selectedChapterSafe장',
            onTapSavedVerses: _openSavedVerses,
            showSavedVerses: !isGuidedReading,
          ),
          if (isGuidedReading)
            _ReadingProgressRow(
              currentIndex: _readingTargetIndex,
              totalCount: _readingTargets.length,
            )
          else
            _BibleChipsRow(
              testament: _selectedTestament,
              bookNo: selectedBookNoSafe,
              chapter: selectedChapterSafe,
              books: testamentBooks,
              chapters: chapterItems,
              onTestamentChanged: (t) {
                setState(() {
                  _selectedTestament = t;
                  final next = _booksForTestament(t);
                  if (next.isEmpty) return;
                  final inSame = t == 'new'
                      ? _selectedBookNo >= 40
                      : _selectedBookNo <= 39;
                  if (!inSame) {
                    _selectedBookNo = next.first.key + 1;
                  }
                  final maxChapter = bibleBooks[_selectedBookNo - 1].chapters;
                  if (_selectedChapter > maxChapter) {
                    _selectedChapter = maxChapter;
                  }
                  _pendingFocusVerse = null;
                });
              },
              onBookChanged: (bookNo) {
                setState(() {
                  _selectedBookNo = bookNo;
                  final maxChapter = bibleBooks[bookNo - 1].chapters;
                  if (_selectedChapter > maxChapter) {
                    _selectedChapter = maxChapter;
                  }
                  _pendingFocusVerse = null;
                });
              },
              onChapterChanged: (chapter) {
                setState(() {
                  _selectedChapter = chapter;
                  _pendingFocusVerse = null;
                });
              },
            ),
          Expanded(
            child: _BibleVersesArea(
              versesFuture: versesFuture,
              scrollController: _verseScrollController,
              focusVerseNo: _pendingFocusVerse,
              highlightTarget: highlightedTarget,
              onConsumedFocus: () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _pendingFocusVerse = null;
                });
              },
              savedVerseKeys: _savedVersesByKey.keys.toSet(),
              onTapStar: _onTapStar,
              showStars: !isGuidedReading,
            ),
          ),
          if (isGuidedReading)
            _GuidedReadingBottomBar(
              isLast: _readingTargetIndex == _readingTargets.length - 1,
              onNext: _goToNextReadingTarget,
              onComplete: _completeGuidedReading,
            )
          else
            _BibleBottomBar(
              canPrev: selectedChapterSafe > 1,
              canNext: selectedChapterSafe < chapterCount,
              onPrev: () => _goToChapter(-1),
              onNext: () => _goToChapter(1),
            ),
        ],
      ),
    );
  }

  String _readingTitle(BibleNavigationTarget target) {
    final reference = _targetReferenceText(target);
    if (_readingTargets.length == 1) {
      return reference;
    }
    return '${_readingTargetIndex + 1}/${_readingTargets.length} · $reference';
  }

  String _targetReferenceText(BibleNavigationTarget target) {
    final book = bibleBooks[target.bookNo - 1].name;
    final endChapter = target.endChapterNo;
    final endVerse = target.endVerseNo;
    final start = '${target.chapterNo}:${target.verseNo}';
    if (endVerse == null) {
      return '$book $start';
    }
    final end = endChapter == null || endChapter == target.chapterNo
        ? '$endVerse'
        : '$endChapter:$endVerse';
    return '$book $start-$end';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 헤더 (타이틀 + 우측 책 아이콘) — 백 버튼은 SubPageScaffold 의 floating 버튼.
// ─────────────────────────────────────────────────────────────────────────

class _BibleReaderHeader extends StatelessWidget {
  const _BibleReaderHeader({
    required this.title,
    required this.onTapSavedVerses,
    required this.showSavedVerses,
  });

  final String title;
  final VoidCallback onTapSavedVerses;
  final bool showSavedVerses;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink800,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (showSavedVerses)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BibleTranslationLabel(label: 'KRV'),
                const SizedBox(width: 8),
                _CircleIconButton(
                  icon: Icons.menu_book_rounded,
                  tooltip: '저장한 구절',
                  onTap: onTapSavedVerses,
                ),
              ],
            )
          else
            const SizedBox(width: 38, height: 38),
        ],
      ),
    );
  }
}

class _ReadingProgressRow extends StatelessWidget {
  const _ReadingProgressRow({
    required this.currentIndex,
    required this.totalCount,
  });

  final int currentIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 1) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        children: List.generate(totalCount, (index) {
          final active = index == currentIndex;
          final done = index < currentIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(right: index == totalCount - 1 ? 0 : 6),
              height: 6,
              decoration: BoxDecoration(
                color: done || active
                    ? AppColors.greenTop
                    : const Color(0x44B89A66),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BibleTranslationLabel extends StatelessWidget {
  const _BibleTranslationLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('bible-reader-translation-label'),
      height: 26,
      constraints: const BoxConstraints(minWidth: 42),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AppColors.greenTop.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.greenTop.withAlpha(120)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.ink500,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xEEF7E9D1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xBC9A7A4C), width: 1),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF6A4F2A)),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 칩 드롭다운 3개 (구약/책/장).
// ─────────────────────────────────────────────────────────────────────────

const double _bibleBookDropdownWidth = 124;

class _BibleChipsRow extends StatelessWidget {
  const _BibleChipsRow({
    required this.testament,
    required this.bookNo,
    required this.chapter,
    required this.books,
    required this.chapters,
    required this.onTestamentChanged,
    required this.onBookChanged,
    required this.onChapterChanged,
  });

  final String testament;
  final int bookNo;
  final int chapter;
  final List<MapEntry<int, BibleBookMeta>> books;
  final List<int> chapters;
  final ValueChanged<String> onTestamentChanged;
  final ValueChanged<int> onBookChanged;
  final ValueChanged<int> onChapterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: bibleDropdownFrame<String>(
                value: testament,
                items: const [
                  DropdownMenuItem(value: 'old', child: Text('구약')),
                  DropdownMenuItem(value: 'new', child: Text('신약')),
                ],
                onChanged: (v) => v != null ? onTestamentChanged(v) : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: _bibleBookDropdownWidth,
              child: bibleDropdownFrame<int>(
                value: bookNo,
                items: books
                    .map(
                      (e) => DropdownMenuItem<int>(
                        value: e.key + 1,
                        child: Text(
                          e.value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (v) => v != null ? onBookChanged(v) : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: bibleDropdownFrame<int>(
                value: chapter,
                items: chapters
                    .map(
                      (c) =>
                          DropdownMenuItem<int>(value: c, child: Text('$c장')),
                    )
                    .toList(growable: false),
                onChanged: (v) => v != null ? onChapterChanged(v) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 히어로 카드 + 구절 목록.
// ─────────────────────────────────────────────────────────────────────────

class _BibleVersesArea extends StatelessWidget {
  const _BibleVersesArea({
    required this.versesFuture,
    required this.scrollController,
    required this.focusVerseNo,
    required this.highlightTarget,
    required this.onConsumedFocus,
    required this.savedVerseKeys,
    required this.onTapStar,
    required this.showStars,
  });

  final Future<List<BibleVerse>> versesFuture;
  final ScrollController scrollController;
  final int? focusVerseNo;
  final BibleNavigationTarget? highlightTarget;
  final VoidCallback onConsumedFocus;
  final Set<String> savedVerseKeys;
  final void Function(BibleVerse) onTapStar;
  final bool showStars;

  static const double _estimatedVerseRowExtent = 82;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BibleVerse>>(
      future: versesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SingleChildScrollView(
              child: Text(
                '본문을 불러오지 못했습니다.\n${snapshot.error}',
                style: const TextStyle(
                  color: Color(0xFFA63F2D),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          );
        }
        final verses = snapshot.data ?? const <BibleVerse>[];
        final focusKey = GlobalKey();
        final focus = focusVerseNo;
        if (focus != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            bool scrollToFocusedVerse({
              required Duration duration,
              double alignment = 0.0,
            }) {
              final ctx = focusKey.currentContext;
              if (ctx == null || !ctx.mounted) {
                return false;
              }
              Scrollable.ensureVisible(
                ctx,
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: alignment,
              );
              return true;
            }

            if (!context.mounted) {
              return;
            }
            final didFindFocusedVerse = scrollToFocusedVerse(
              duration: const Duration(milliseconds: 320),
            );
            if (!didFindFocusedVerse && scrollController.hasClients) {
              final focusIndex = verses.indexWhere((v) => v.verseNo == focus);
              if (focusIndex >= 0) {
                final position = scrollController.position;
                final offset = (focusIndex * _estimatedVerseRowExtent).clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                );
                scrollController.animateTo(
                  offset,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                );
              }
            }
            Future<void>.delayed(const Duration(milliseconds: 340), () {
              scrollToFocusedVerse(
                duration: const Duration(milliseconds: 220),
                alignment: 0.0,
              );
              onConsumedFocus();
            });
          });
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          children: [
            if (verses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '선택한 장의 본문 데이터가 없습니다.',
                    style: TextStyle(
                      color: Color(0xFF6A5440),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              ...List.generate(verses.length, (i) {
                final v = verses[i];
                final key = SavedBibleVerse.buildVerseKey(
                  translation: v.translation,
                  bookNo: v.bookNo,
                  chapterNo: v.chapterNo,
                  verseNo: v.verseNo,
                );
                final isSaved = savedVerseKeys.contains(key);
                final isInReadRange =
                    highlightTarget?.containsVerse(
                      bookNo: v.bookNo,
                      chapterNo: v.chapterNo,
                      verseNo: v.verseNo,
                    ) ??
                    false;
                final isReadRangeBoundary =
                    highlightTarget?.isBoundaryVerse(
                      bookNo: v.bookNo,
                      chapterNo: v.chapterNo,
                      verseNo: v.verseNo,
                    ) ??
                    false;
                final prevSaved =
                    i > 0 &&
                    savedVerseKeys.contains(
                      SavedBibleVerse.buildVerseKey(
                        translation: verses[i - 1].translation,
                        bookNo: verses[i - 1].bookNo,
                        chapterNo: verses[i - 1].chapterNo,
                        verseNo: verses[i - 1].verseNo,
                      ),
                    );
                final nextSaved =
                    i < verses.length - 1 &&
                    savedVerseKeys.contains(
                      SavedBibleVerse.buildVerseKey(
                        translation: verses[i + 1].translation,
                        bookNo: verses[i + 1].bookNo,
                        chapterNo: verses[i + 1].chapterNo,
                        verseNo: verses[i + 1].verseNo,
                      ),
                    );
                return _VerseRow(
                  key: focus != null && v.verseNo == focus ? focusKey : null,
                  verse: v,
                  isSaved: isSaved,
                  isInReadRange: isInReadRange,
                  isReadRangeBoundary: isReadRangeBoundary,
                  joinAbove: prevSaved && isSaved,
                  joinBelow: nextSaved && isSaved,
                  isFirst: i == 0,
                  isLast: i == verses.length - 1,
                  onTapStar: () => onTapStar(v),
                  showStar: showStars,
                );
              }),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    super.key,
    required this.verse,
    required this.isSaved,
    required this.isInReadRange,
    required this.isReadRangeBoundary,
    required this.joinAbove,
    required this.joinBelow,
    required this.isFirst,
    required this.isLast,
    required this.onTapStar,
    required this.showStar,
  });

  final BibleVerse verse;
  final bool isSaved;
  final bool isInReadRange;
  final bool isReadRangeBoundary;
  final bool joinAbove;
  final bool joinBelow;
  final bool isFirst;
  final bool isLast;
  final bool showStar;

  /// 우측 별 아이콘 탭. 단일 절 저장/해제 토글.
  final VoidCallback onTapStar;

  @override
  Widget build(BuildContext context) {
    final highlight = isInReadRange
        ? const Color(0x44E2BE57)
        : isSaved
        ? const Color(0x33E2BE57)
        : Colors.transparent;
    final leadingBorder = isInReadRange
        ? Border(
            left: BorderSide(
              color: const Color(0xFFE2A93D),
              width: isReadRangeBoundary ? 4 : 2,
            ),
          )
        : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(color: highlight, border: leadingBorder),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Material(
        color: Colors.transparent,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: _VerseRail(
                  number: verse.verseNo,
                  isFirst: isFirst,
                  isLast: isLast,
                  accent: isReadRangeBoundary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                  child: Text(
                    verse.verseText,
                    style: const TextStyle(
                      color: AppColors.ink800,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
              if (showStar)
                _VerseStarButton(saved: isSaved, onTap: onTapStar)
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구절 우측의 즐겨찾기 별 아이콘. 저장 여부에 따라 채워짐/외곽선이 바뀐다.
/// 탭하면 그 구절 하나만 user_saved_verses 에 토글된다.
class _VerseStarButton extends StatelessWidget {
  const _VerseStarButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Icon(
          saved ? Icons.star_rounded : Icons.star_border_rounded,
          size: 22,
          color: saved ? const Color(0xFFE2A93D) : const Color(0xFFB89A66),
          semanticLabel: saved ? '저장 해제' : '저장',
        ),
      ),
    );
  }
}

class _GuidedReadingBottomBar extends StatelessWidget {
  const _GuidedReadingBottomBar({
    required this.isLast,
    required this.onNext,
    required this.onComplete,
  });

  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isLast ? onComplete : onNext,
          icon: Icon(
            isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
          ),
          label: Text(isLast ? '읽기 완료' : '다음'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.greenBtnBot,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerseRail extends StatelessWidget {
  const _VerseRail({
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.accent,
  });

  final int number;
  final bool isFirst;
  final bool isLast;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    const lineColor = Color(0x55B89A66);
    final circleColor = accent
        ? const Color(0xFF2F6B4A)
        : const Color(0xFF407758);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // 위/아래 라인 — 첫 행/마지막 행은 한쪽만.
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Center(
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isFirst ? Colors.transparent : lineColor,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : lineColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF6EEDC), width: 2),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 하단 액션 바 (이전/다음 장).
// ─────────────────────────────────────────────────────────────────────────

class _BibleBottomBar extends StatelessWidget {
  const _BibleBottomBar({
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xEEF7E9D1),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xBC9A7A4C), width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: _BarButton(
                label: '이전 장',
                icon: Icons.chevron_left_rounded,
                enabled: canPrev,
                onTap: onPrev,
              ),
            ),
            _Divider(),
            Expanded(
              child: _BarButton(
                label: '다음 장',
                icon: Icons.chevron_right_rounded,
                enabled: canNext,
                trailingIcon: true,
                onTap: onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.trailingIcon = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? const Color(0xFF6A4F2A) : const Color(0x77745D3F);
    final iconWidget = Icon(icon, size: 18, color: fg);
    final textWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
    final children = trailingIcon
        ? [textWidget, iconWidget]
        : [iconWidget, textWidget];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 18, color: const Color(0x33745D3F));
  }
}
