import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bible_verse.dart';
import '../models/saved_bible_verse.dart';
import '../screens/saved_verses_screen.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

/// 성경 리더 페이지 (2026-05-10 리디자인).
///
/// 상단 타이틀(책 + 장) + 책/장 칩 드롭다운, 번호 원 + 타임라인 레일을 가진
/// 구절 목록, 그리고 이전/읽기/듣기/다음 장 액션 바를 제공한다. 히어로 카드는
/// 의도적으로 비워두고, 추후 era/메타 정보가 들어오면 다시 추가할 예정이다.
///
/// **저장 모델**: 별표 토글 대신 **구역(범위) 저장**이다. 사용자가 구절 하나를
/// 탭하면 펜딩 시작 점이 잡히고, 두 번째 구절을 탭하면 그 사이 범위 전체가
/// 펜딩 하이라이트된다. 하단 시트에서 "저장"을 누르면 범위 내 모든 구절이
/// `user_saved_verses` 에 일괄 insert 된다. 이미 저장된 구절을 탭하면 단일 절
/// 저장 해제 시트가 뜬다.
///
/// [initialBookNo]/[initialChapterNo]/[initialVerseNo]가 주어지면 해당 구절로
/// 자동 스크롤한다. [highlightTarget]이 있으면 해당 이야기의 읽을 본문 범위를
/// 저장 상태와 별개인 임시 하이라이트로 표시한다.
class BibleReaderPage extends ConsumerStatefulWidget {
  const BibleReaderPage({
    super.key,
    this.initialBookNo,
    this.initialChapterNo,
    this.initialVerseNo,
    this.highlightTarget,
  });

  final int? initialBookNo;
  final int? initialChapterNo;
  final int? initialVerseNo;
  final BibleNavigationTarget? highlightTarget;

  @override
  ConsumerState<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends ConsumerState<BibleReaderPage> {
  late int _selectedBookNo;
  late String _selectedTestament;
  late int _selectedChapter;
  int? _pendingFocusVerse;
  final Map<String, Future<List<BibleVerse>>> _chapterCache = {};
  Set<String> _savedVerseKeys = <String>{};

  // 범위 저장 펜딩 상태. 시작 점만 있고 끝 점 미정인 단계와 둘 다 정해진 단계
  // 둘 다 표현한다. _pendingEnd 가 null 이면 "끝 절을 선택하세요" 상태.
  int? _pendingStartVerseNo;
  int? _pendingEndVerseNo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialBookNo =
        widget.initialBookNo ?? widget.highlightTarget?.bookNo ?? 1;
    _selectedBookNo = initialBookNo.clamp(1, bibleBooks.length).toInt();
    _selectedTestament = _selectedBookNo >= 40 ? 'new' : 'old';
    final maxChapter = bibleBooks[_selectedBookNo - 1].chapters;
    final initialChapter =
        widget.initialChapterNo ?? widget.highlightTarget?.chapterNo ?? 1;
    _selectedChapter = initialChapter.clamp(1, maxChapter).toInt();
    final initialVerse =
        widget.initialVerseNo ?? widget.highlightTarget?.verseNo;
    _pendingFocusVerse = (initialVerse ?? 0) > 0 ? initialVerse : null;
    _loadSavedVerseKeys();
  }

  Future<void> _loadSavedVerseKeys() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }
    try {
      final keys = await ref
          .read(userRepositoryProvider)
          .fetchSavedVerseKeys(user.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedVerseKeys = keys;
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

  void _resetPending() {
    if (_pendingStartVerseNo == null && _pendingEndVerseNo == null) return;
    setState(() {
      _pendingStartVerseNo = null;
      _pendingEndVerseNo = null;
    });
  }

  void _onTapVerse(BibleVerse verse) {
    final key = SavedBibleVerse.buildVerseKey(
      translation: verse.translation,
      bookNo: verse.bookNo,
      chapterNo: verse.chapterNo,
      verseNo: verse.verseNo,
    );
    final isSaved = _savedVerseKeys.contains(key);

    // 펜딩 중이 아닐 때 저장된 구절 탭 → 해제 시트.
    if (_pendingStartVerseNo == null && isSaved) {
      _showUnsaveSheet(verse, key);
      return;
    }

    // 시작 점 미정 → 시작 점 잡기.
    if (_pendingStartVerseNo == null) {
      setState(() {
        _pendingStartVerseNo = verse.verseNo;
        _pendingEndVerseNo = null;
      });
      return;
    }

    // 시작 점 동일 → 단일 절 저장으로 확정 (A→A 탭).
    // 다른 점 → 범위 끝 점 확정.
    setState(() {
      _pendingEndVerseNo = verse.verseNo;
    });
  }

  /// 우측 별 아이콘 탭 — 단일 절 저장/해제 토글. 범위 선택 흐름과 독립이다.
  /// 펜딩 상태가 있어도 영향 주지 않고 단일 절만 즉시 토글한다.
  Future<void> _onTapStar(BibleVerse verse) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }
    final key = SavedBibleVerse.buildVerseKey(
      translation: verse.translation,
      bookNo: verse.bookNo,
      chapterNo: verse.chapterNo,
      verseNo: verse.verseNo,
    );
    try {
      final didSave = await ref
          .read(userRepositoryProvider)
          .toggleSavedVerse(userId: user.id, verse: verse);
      if (!mounted) return;
      setState(() {
        if (didSave) {
          _savedVerseKeys.add(key);
        } else {
          _savedVerseKeys.remove(key);
        }
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(didSave ? '저장되었어요' : '저장이 해제되었어요')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다.\n$error')));
    }
  }

  Future<void> _confirmSaveRange(List<BibleVerse> versesInChapter) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }
    final start = _pendingStartVerseNo;
    final end = _pendingEndVerseNo ?? _pendingStartVerseNo;
    if (start == null || end == null) return;
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    final selected = versesInChapter
        .where((v) => v.verseNo >= lo && v.verseNo <= hi)
        .toList(growable: false);

    setState(() => _saving = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .saveVerseRange(userId: user.id, verses: selected);
      if (!mounted) return;
      setState(() {
        for (final v in selected) {
          _savedVerseKeys.add(
            SavedBibleVerse.buildVerseKey(
              translation: v.translation,
              bookNo: v.bookNo,
              chapterNo: v.chapterNo,
              verseNo: v.verseNo,
            ),
          );
        }
        _pendingStartVerseNo = null;
        _pendingEndVerseNo = null;
        _saving = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('${selected.length}개 구절을 저장했어요')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다.\n$error')));
    }
  }

  Future<void> _showUnsaveSheet(BibleVerse verse, String verseKey) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                '${verse.bookName} ${verse.chapterNo}:${verse.verseNo}',
                style: const TextStyle(
                  color: AppColors.ink800,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                verse.verseText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink600,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SheetTextButton(
                      label: '취소',
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetPrimaryButton(
                      label: '저장 해제',
                      tone: _SheetTone.danger,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(userRepositoryProvider)
          .unsaveVerse(userId: user.id, verse: verse);
      if (!mounted) return;
      setState(() {
        _savedVerseKeys.remove(verseKey);
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('저장이 해제되었어요')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('해제 중 오류가 발생했습니다.\n$error')));
    }
  }

  void _goToChapter(int delta) {
    final maxChapter = bibleBooks[_selectedBookNo - 1].chapters;
    final next = _selectedChapter + delta;
    if (next < 1 || next > maxChapter) return;
    setState(() {
      _selectedChapter = next;
      _pendingFocusVerse = null;
      _pendingStartVerseNo = null;
      _pendingEndVerseNo = null;
    });
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
      _pendingStartVerseNo = null;
      _pendingEndVerseNo = null;
    });
  }

  Future<void> _openSavedVerses() async {
    if (!mounted) return;
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
    // 저장 페이지에서 변경 가능 — 돌아오면 키 셋 새로 고침.
    await _loadSavedVerseKeys();
  }

  @override
  Widget build(BuildContext context) {
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
    final versesFuture = _loadVerses(
      bookNo: selectedBookNoSafe,
      chapterNo: selectedChapterSafe,
    );

    return SubPageScaffold(
      title: '성경',
      compactBackOnly: true,
      child: Column(
        children: [
          _BibleReaderHeader(
            title: '${selectedBook.name} $selectedChapterSafe장',
            onTapSavedVerses: _openSavedVerses,
          ),
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
                _pendingStartVerseNo = null;
                _pendingEndVerseNo = null;
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
                _pendingStartVerseNo = null;
                _pendingEndVerseNo = null;
              });
            },
            onChapterChanged: (chapter) {
              setState(() {
                _selectedChapter = chapter;
                _pendingFocusVerse = null;
                _pendingStartVerseNo = null;
                _pendingEndVerseNo = null;
              });
            },
          ),
          Expanded(
            child: _BibleVersesArea(
              versesFuture: versesFuture,
              pendingStart: _pendingStartVerseNo,
              pendingEnd: _pendingEndVerseNo,
              focusVerseNo: _pendingFocusVerse,
              highlightTarget: widget.highlightTarget,
              onConsumedFocus: () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _pendingFocusVerse = null;
                });
              },
              savedVerseKeys: _savedVerseKeys,
              onTapVerse: _onTapVerse,
              onTapStar: _onTapStar,
            ),
          ),
          _BibleBottomBar(
            canPrev: selectedChapterSafe > 1,
            canNext: selectedChapterSafe < chapterCount,
            onPrev: () => _goToChapter(-1),
            onNext: () => _goToChapter(1),
            onListen: () {
              final messenger = ScaffoldMessenger.of(context);
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                const SnackBar(content: Text('듣기 기능은 준비 중이에요')),
              );
            },
          ),
          if (_pendingStartVerseNo != null)
            _PendingActionBar(
              start: _pendingStartVerseNo!,
              end: _pendingEndVerseNo,
              saving: _saving,
              onCancel: _resetPending,
              onSave: () async {
                final verses = await versesFuture;
                if (!mounted) return;
                await _confirmSaveRange(verses);
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 헤더 (타이틀 + 우측 책 아이콘) — 백 버튼은 SubPageScaffold 의 floating 버튼.
// ─────────────────────────────────────────────────────────────────────────

class _BibleReaderHeader extends StatelessWidget {
  const _BibleReaderHeader({
    required this.title,
    required this.onTapSavedVerses,
  });

  final String title;
  final VoidCallback onTapSavedVerses;

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
          _CircleIconButton(
            icon: Icons.menu_book_rounded,
            tooltip: '저장한 구절',
            onTap: onTapSavedVerses,
          ),
        ],
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
              width: 156,
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
    required this.pendingStart,
    required this.pendingEnd,
    required this.focusVerseNo,
    required this.highlightTarget,
    required this.onConsumedFocus,
    required this.savedVerseKeys,
    required this.onTapVerse,
    required this.onTapStar,
  });

  final Future<List<BibleVerse>> versesFuture;
  final int? pendingStart;
  final int? pendingEnd;
  final int? focusVerseNo;
  final BibleNavigationTarget? highlightTarget;
  final VoidCallback onConsumedFocus;
  final Set<String> savedVerseKeys;
  final void Function(BibleVerse) onTapVerse;
  final void Function(BibleVerse) onTapStar;

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
            void scrollToFocusedVerse({
              required Duration duration,
              double alignment = 0.18,
            }) {
              final ctx = focusKey.currentContext;
              if (ctx == null || !ctx.mounted) {
                return;
              }
              Scrollable.ensureVisible(
                ctx,
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: alignment,
              );
            }

            scrollToFocusedVerse(duration: const Duration(milliseconds: 320));
            Future<void>.delayed(const Duration(milliseconds: 140), () {
              scrollToFocusedVerse(
                duration: const Duration(milliseconds: 220),
                alignment: 0.16,
              );
              onConsumedFocus();
            });
          });
        }
        final pendingLo = pendingStart == null
            ? null
            : (pendingEnd == null
                  ? pendingStart!
                  : (pendingStart! <= pendingEnd!
                        ? pendingStart!
                        : pendingEnd!));
        final pendingHi = pendingStart == null
            ? null
            : (pendingEnd == null
                  ? pendingStart!
                  : (pendingStart! <= pendingEnd!
                        ? pendingEnd!
                        : pendingStart!));

        return ListView(
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
                final inPending =
                    pendingLo != null &&
                    pendingHi != null &&
                    v.verseNo >= pendingLo &&
                    v.verseNo <= pendingHi;
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
                  isInPending: inPending,
                  isPendingStart:
                      pendingStart != null && v.verseNo == pendingStart,
                  isInReadRange: isInReadRange,
                  isReadRangeBoundary: isReadRangeBoundary,
                  joinAbove: prevSaved && isSaved,
                  joinBelow: nextSaved && isSaved,
                  isFirst: i == 0,
                  isLast: i == verses.length - 1,
                  onTap: () => onTapVerse(v),
                  onTapStar: () => onTapStar(v),
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
    required this.isInPending,
    required this.isPendingStart,
    required this.isInReadRange,
    required this.isReadRangeBoundary,
    required this.joinAbove,
    required this.joinBelow,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onTapStar,
  });

  final BibleVerse verse;
  final bool isSaved;
  final bool isInPending;
  final bool isPendingStart;
  final bool isInReadRange;
  final bool isReadRangeBoundary;
  final bool joinAbove;
  final bool joinBelow;
  final bool isFirst;
  final bool isLast;

  /// 행 본문(번호 + 텍스트) 탭. 범위 저장 시작/끝 토글.
  final VoidCallback onTap;

  /// 우측 별 아이콘 탭. 단일 절 저장/해제 토글. 범위 저장 흐름과 독립.
  final VoidCallback onTapStar;

  @override
  Widget build(BuildContext context) {
    final highlight = isInPending
        ? const Color(0x55E2BE57)
        : isInReadRange
        ? const Color(0x44E2BE57)
        : isSaved
        ? const Color(0x33E2BE57)
        : Colors.transparent;
    final leadingBorder = isInReadRange && !isInPending
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
                  accent: isInPending || isPendingStart || isReadRangeBoundary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onTap,
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
              ),
              _VerseStarButton(saved: isSaved, onTap: onTapStar),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구절 우측의 즐겨찾기 별 아이콘. 저장 여부에 따라 채워짐/외곽선이 바뀐다.
/// 범위 저장 UX와 독립 — 탭하면 그 구절 하나만 user_saved_verses 에 토글된다.
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
// 하단 액션 바 (이전/읽기/듣기/다음).
// ─────────────────────────────────────────────────────────────────────────

class _BibleBottomBar extends StatelessWidget {
  const _BibleBottomBar({
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onListen,
  });

  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onListen;

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
                label: '읽기',
                icon: Icons.play_arrow_rounded,
                enabled: true,
                emphasized: true,
                onTap: () {},
              ),
            ),
            _Divider(),
            Expanded(
              child: _BarButton(
                label: '듣기',
                icon: Icons.headphones_rounded,
                enabled: true,
                onTap: onListen,
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
    this.emphasized = false,
    this.trailingIcon = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool emphasized;
  final bool trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = enabled
        ? (emphasized ? Colors.white : const Color(0xFF6A4F2A))
        : const Color(0x77745D3F);
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
          decoration: BoxDecoration(
            gradient: emphasized
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.greenBtnTop, AppColors.greenBtnBot],
                  )
                : null,
            borderRadius: BorderRadius.circular(22),
          ),
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

// ─────────────────────────────────────────────────────────────────────────
// 펜딩 액션 바 — 시작 점만 잡힌 상태와 끝 점까지 잡힌 상태 둘 다 표현.
// ─────────────────────────────────────────────────────────────────────────

class _PendingActionBar extends StatelessWidget {
  const _PendingActionBar({
    required this.start,
    required this.end,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final int start;
  final int? end;
  final bool saving;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final hasEnd = end != null;
    final lo = hasEnd ? (start <= end! ? start : end!) : start;
    final hi = hasEnd ? (start <= end! ? end! : start) : start;
    final label = hasEnd
        ? (lo == hi ? '$lo절 저장' : '$lo–$hi절 저장')
        : '끝 절을 선택하세요';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFAF7E9D1),
        border: Border(top: BorderSide(color: Color(0x44A89364), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink800,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _SheetTextButton(label: '취소', onTap: saving ? () {} : onCancel),
            const SizedBox(width: 8),
            _SheetPrimaryButton(
              label: saving ? '저장 중...' : '저장',
              tone: hasEnd ? _SheetTone.primary : _SheetTone.disabled,
              onTap: !hasEnd || saving ? () {} : () => onSave(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 시트 공용 버튼/컨테이너.
// ─────────────────────────────────────────────────────────────────────────

class _BottomSheetContainer extends StatelessWidget {
  const _BottomSheetContainer({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFAF7E9D1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

enum _SheetTone { primary, danger, disabled }

class _SheetTextButton extends StatelessWidget {
  const _SheetTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1E2C6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x88B89A66), width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6A4F2A),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetPrimaryButton extends StatelessWidget {
  const _SheetPrimaryButton({
    required this.label,
    required this.onTap,
    required this.tone,
  });
  final String label;
  final VoidCallback onTap;
  final _SheetTone tone;
  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      _SheetTone.primary => const [
        AppColors.greenBtnTop,
        AppColors.greenBtnBot,
      ],
      _SheetTone.danger => const [Color(0xFFC25448), Color(0xFF8C3A30)],
      _SheetTone.disabled => const [Color(0xFFD9C7A4), Color(0xFFB99B6E)],
    };
    final fg = tone == _SheetTone.disabled
        ? const Color(0xCCFFFFFF)
        : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
