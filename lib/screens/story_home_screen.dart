import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/era.dart';
import '../models/bible_verse.dart';
import '../models/story_event.dart';
import '../models/quiz_question.dart';
import '../state/story_controller.dart';
import '../widgets/era_selector.dart';
import '../widgets/game_ui_skin.dart';
import '../widgets/person_panel.dart';
import '../widgets/story_list_panel.dart';
import '../widgets/story_map_panel.dart';

class StoryHomeScreen extends ConsumerStatefulWidget {
  const StoryHomeScreen({super.key});

  @override
  ConsumerState<StoryHomeScreen> createState() => _StoryHomeScreenState();
}

class _StoryHomeScreenState extends ConsumerState<StoryHomeScreen> {
  final StoryMapPanelController _mapPanelController = StoryMapPanelController();
  PersonSortMode _personSortMode = PersonSortMode.eraOrder;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(storyControllerProvider.notifier).initialize();
    });
  }

  Future<void> _openSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5E9D6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(storyControllerProvider);
            final controller = ref.read(storyControllerProvider.notifier);
            final results = controller.searchResults();

            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                14,
                12,
                MediaQuery.of(context).viewInsets.bottom + 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: ValueKey(state.searchQuery),
                    initialValue: state.searchQuery,
                    autofocus: true,
                    onChanged: controller.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: '단어/문장 검색...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (state.isSearching)
                    const SizedBox(
                      height: 28,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  SizedBox(
                    height: 240,
                    child: results.isEmpty
                        ? const Center(child: Text('검색 결과가 없습니다.'))
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final event = results[index];
                              return ListTile(
                                dense: true,
                                title: Text(event.title),
                                subtitle: Text(event.placeName ?? '-'),
                                onTap: () async {
                                  await controller.selectSearchResult(event);
                                  if (!context.mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  _handleEventSelect(event.id);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleEventSelect(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    if (state.selectedEventId == event.id) {
      controller.selectEvent(null);
      return;
    }
    controller.selectEvent(event.id);
  }

  void _openEventDetail(String eventId) {
    final state = ref.read(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }
    controller.selectEvent(event.id);
    _showEventDetailPopup(event);
  }

  Future<void> _showEventDetailPopup(StoryEvent event) async {
    final shortStoryText = (event.shortStory ?? '').trim();
    final fallbackText = (event.story ?? event.shortText ?? event.summary ?? '')
        .trim();
    final storyText = shortStoryText.isNotEmpty ? shortStoryText : fallbackText;
    final refs = event.bibleRefs.join(' / ');
    final moveTarget = _parseBibleNavigationTarget(event.bibleRefs.firstOrNull);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 420),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final tilt = (1 - curved.value) * 0.14;
        final scale = 0.9 + (curved.value * 0.1);
        return FadeTransition(
          opacity: curved,
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(tilt)
              ..scale(scale),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.of(context).size.height * 0.94,
              minWidth: 300,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: scrollPopupDecoration().copyWith(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            // Keep text further inside the parchment edges, while
                            // using almost all of the inner area after margins.
                            final cTop = (h * 0.09)
                                .clamp(34.0, 56.0)
                                .toDouble();
                            final cBottom = (h * 0.07)
                                .clamp(26.0, 44.0)
                                .toDouble();
                            final cLeft = (w * 0.07)
                                .clamp(28.0, 56.0)
                                .toDouble();

                            // Close button: half size and top-right.
                            const closeSize = 36.0;
                            final closeRight = (w * 0.04)
                                .clamp(18.0, 32.0)
                                .toDouble();
                            final closeTop = (h * 0.05)
                                .clamp(16.0, 30.0)
                                .toDouble();
                            final baseRight = (w * 0.07)
                                .clamp(28.0, 56.0)
                                .toDouble();
                            final closeReservedRight =
                                closeRight + closeSize + 10.0;
                            final cRight = baseRight < closeReservedRight
                                ? closeReservedRight
                                : baseRight;

                            return Stack(
                              children: [
                                // Content scrolls inside the inner parchment area
                                Positioned(
                                  top: cTop,
                                  bottom: cBottom,
                                  left: cLeft,
                                  right: cRight,
                                  child: ClipRect(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: DefaultTextStyle(
                                        style: const TextStyle(
                                          color: Color(0xFF3B2A16),
                                          fontFamily: 'Times New Roman',
                                          height: 1.55,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              height: 8,
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xB39A7A4A),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                            Text(
                                              event.title,
                                              style: const TextStyle(
                                                fontSize: 22,
                                                height: 1.3,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF3A2B15),
                                                letterSpacing: 0.1,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${event.placeName ?? '-'} · ${event.startYear ?? '-'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF6A522E),
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            if (storyText.isNotEmpty)
                                              _storySection(
                                                title: '요약 이야기',
                                                content: storyText,
                                              ),
                                            if (refs.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              _storySection(
                                                title: '관련 본문',
                                                content: refs,
                                                action: moveTarget == null
                                                    ? null
                                                    : _bibleMoveButton(
                                                        onTap: () {
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                          Future.microtask(() {
                                                            if (!mounted) {
                                                              return;
                                                            }
                                                            _openBibleReaderPopup(
                                                              initialBookNo:
                                                                  moveTarget
                                                                      .bookNo,
                                                              initialChapterNo:
                                                                  moveTarget
                                                                      .chapterNo,
                                                              initialVerseNo:
                                                                  moveTarget
                                                                      .verseNo,
                                                            );
                                                          });
                                                        },
                                                      ),
                                              ),
                                            ],
                                            if (storyText.isEmpty)
                                              const Text('요약 정보가 없습니다.'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Close button in upper-right corner of parchment
                                Positioned(
                                  right: closeRight,
                                  top: closeTop,
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    behavior: HitTestBehavior.translucent,
                                    child: SizedBox(
                                      width: closeSize,
                                      height: closeSize,
                                      child: Image.asset(
                                        kScrollCloseAsset,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBibleReaderPopup({
    int? initialBookNo,
    int? initialChapterNo,
    int? initialVerseNo,
  }) async {
    final repo = ref.read(storyRepositoryProvider);
    var selectedBookNo = (initialBookNo ?? 1).clamp(1, _kBibleBooks.length);
    var selectedTestament = selectedBookNo >= 40 ? 'new' : 'old';
    var selectedChapter = initialChapterNo ?? 1;
    var pendingFocusVerse = (initialVerseNo ?? 0) > 0 ? initialVerseNo : null;
    final chapterCache = <String, Future<List<BibleVerse>>>{};

    List<MapEntry<int, _BibleBookMeta>> booksForTestament(String testament) {
      return _kBibleBooks
          .asMap()
          .entries
          .where((entry) {
            final bookNo = entry.key + 1;
            return testament == 'new' ? bookNo >= 40 : bookNo <= 39;
          })
          .toList(growable: false);
    }

    Future<List<BibleVerse>> loadVerses({
      required int bookNo,
      required int chapterNo,
    }) {
      final cacheKey = 'KRV:$bookNo:$chapterNo';
      return chapterCache.putIfAbsent(
        cacheKey,
        () => repo.fetchBibleVersesByChapter(
          translation: 'KRV',
          bookNo: bookNo,
          chapterNo: chapterNo,
        ),
      );
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close_bible_reader',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final testamentBooks = booksForTestament(selectedTestament);
            final selectedEntry =
                testamentBooks
                    .where((entry) => (entry.key + 1) == selectedBookNo)
                    .firstOrNull ??
                testamentBooks.first;
            final selectedBook = selectedEntry.value;
            final selectedBookNoSafe = selectedEntry.key + 1;
            final chapterCount = selectedBook.chapters;
            final chapterItems = List<int>.generate(chapterCount, (i) => i + 1);
            final selectedChapterSafe = selectedChapter.clamp(1, chapterCount);
            final versesFuture = loadVerses(
              bookNo: selectedBookNoSafe,
              chapterNo: selectedChapterSafe,
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: scrollPopupDecoration().copyWith(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.38),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        final cTop = (h * 0.09).clamp(34.0, 56.0).toDouble();
                        final cBottom = (h * 0.07).clamp(24.0, 42.0).toDouble();
                        final cLeft = (w * 0.07).clamp(26.0, 56.0).toDouble();
                        const closeSize = 36.0;
                        final closeRight = (w * 0.04)
                            .clamp(18.0, 32.0)
                            .toDouble();
                        final closeTop = (h * 0.05)
                            .clamp(16.0, 30.0)
                            .toDouble();
                        final baseRight = (w * 0.07)
                            .clamp(26.0, 56.0)
                            .toDouble();
                        final closeReservedRight =
                            closeRight + closeSize + 10.0;
                        final cRight = baseRight < closeReservedRight
                            ? closeReservedRight
                            : baseRight;

                        return Stack(
                          children: [
                            Positioned(
                              top: cTop,
                              bottom: cBottom,
                              left: cLeft,
                              right: cRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 88,
                                          child: _bibleDropdownFrame<String>(
                                            value: selectedTestament,
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'old',
                                                child: Text('구약'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'new',
                                                child: Text('신약'),
                                              ),
                                            ],
                                            onChanged: (testament) {
                                              if (testament == null) {
                                                return;
                                              }
                                              setDialogState(() {
                                                selectedTestament = testament;
                                                final nextBooks =
                                                    booksForTestament(
                                                      selectedTestament,
                                                    );
                                                if (nextBooks.isEmpty) {
                                                  return;
                                                }
                                                final inSameTestament =
                                                    selectedTestament == 'new'
                                                    ? selectedBookNo >= 40
                                                    : selectedBookNo <= 39;
                                                if (!inSameTestament) {
                                                  selectedBookNo =
                                                      nextBooks.first.key + 1;
                                                }
                                                final maxChapter =
                                                    _kBibleBooks[selectedBookNo -
                                                            1]
                                                        .chapters;
                                                if (selectedChapter >
                                                    maxChapter) {
                                                  selectedChapter = maxChapter;
                                                }
                                                pendingFocusVerse = null;
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 172,
                                          child: _bibleDropdownFrame<int>(
                                            value: selectedBookNoSafe,
                                            items: testamentBooks
                                                .map(
                                                  (entry) =>
                                                      DropdownMenuItem<int>(
                                                        value: entry.key + 1,
                                                        child: Text(
                                                          entry.value.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                )
                                                .toList(growable: false),
                                            onChanged: (bookNo) {
                                              if (bookNo == null) {
                                                return;
                                              }
                                              setDialogState(() {
                                                selectedBookNo = bookNo;
                                                final maxChapter =
                                                    _kBibleBooks[bookNo - 1]
                                                        .chapters;
                                                if (selectedChapter >
                                                    maxChapter) {
                                                  selectedChapter = maxChapter;
                                                }
                                                pendingFocusVerse = null;
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 96,
                                          child: _bibleDropdownFrame<int>(
                                            value: selectedChapterSafe,
                                            items: chapterItems
                                                .map(
                                                  (chapter) =>
                                                      DropdownMenuItem<int>(
                                                        value: chapter,
                                                        child: Text(
                                                          '$chapter장',
                                                        ),
                                                      ),
                                                )
                                                .toList(growable: false),
                                            onChanged: (chapter) {
                                              if (chapter == null) {
                                                return;
                                              }
                                              setDialogState(() {
                                                selectedChapter = chapter;
                                                pendingFocusVerse = null;
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xBF9A7A4A),
                                          width: 1.2,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        color: const Color(0xF4EFE3CC),
                                      ),
                                      padding: const EdgeInsets.all(14),
                                      child: FutureBuilder<List<BibleVerse>>(
                                        future: versesFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                    ),
                                              ),
                                            );
                                          }

                                          if (snapshot.hasError) {
                                            return SingleChildScrollView(
                                              child: Text(
                                                '본문을 불러오지 못했습니다.\n${snapshot.error}',
                                                style: const TextStyle(
                                                  color: Color(0xFFA63F2D),
                                                  fontSize: 14,
                                                  height: 1.5,
                                                ),
                                              ),
                                            );
                                          }

                                          final verses =
                                              snapshot.data ??
                                              const <BibleVerse>[];
                                          final focusVerseNo =
                                              pendingFocusVerse;
                                          final focusVerseKey = GlobalKey();
                                          if (verses.isEmpty) {
                                            return const Center(
                                              child: Text(
                                                '선택한 장의 본문 데이터가 없습니다.',
                                                style: TextStyle(
                                                  color: Color(0xFF6A5440),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            );
                                          }

                                          if (focusVerseNo != null) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  final targetContext =
                                                      focusVerseKey
                                                          .currentContext;
                                                  if (targetContext != null) {
                                                    Scrollable.ensureVisible(
                                                      targetContext,
                                                      duration: const Duration(
                                                        milliseconds: 280,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                      alignment: 0.12,
                                                    );
                                                  }
                                                  pendingFocusVerse = null;
                                                });
                                          }

                                          return SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${selectedBook.name} $selectedChapterSafe장',
                                                  style: const TextStyle(
                                                    color: Color(0xFF3B2A17),
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                ...verses.map((verse) {
                                                  return Padding(
                                                    key:
                                                        focusVerseNo != null &&
                                                            verse.verseNo ==
                                                                focusVerseNo
                                                        ? focusVerseKey
                                                        : null,
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 8,
                                                        ),
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF3B2A17,
                                                          ),
                                                          fontSize: 15,
                                                          height: 1.6,
                                                        ),
                                                        children: [
                                                          TextSpan(
                                                            text:
                                                                '${verse.verseNo} ',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                          TextSpan(
                                                            text:
                                                                verse.verseText,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: closeRight,
                              top: closeTop,
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                behavior: HitTestBehavior.translucent,
                                child: SizedBox(
                                  width: closeSize,
                                  height: closeSize,
                                  child: Image.asset(
                                    kScrollCloseAsset,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _storySection({
    required String title,
    required String content,
    Widget? action,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xF4EFE3CC),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4D381F),
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              content,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF3B2A17),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bibleMoveButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 78,
        height: 30,
        child: DecoratedBox(
          decoration: actionButtonDecoration(selected: true),
          child: const Center(
            child: Text(
              '이동',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFFDF8EE),
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _eraTestament(Era era) {
    final raw = era.testament.trim().toLowerCase();
    if (raw == 'new' || raw == 'nt' || raw == 'new_testament') {
      return 'new';
    }
    if (era.code.startsWith('era_nt_')) {
      return 'new';
    }
    return 'old';
  }

  Future<void> _startQuiz(String eventId) async {
    final state = ref.read(storyControllerProvider);
    final repo = ref.read(storyRepositoryProvider);
    final event = state.events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return;
    }

    List<QuizQuestion> questions;
    try {
      questions = await repo.fetchQuizQuestions(eventId);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFFF6EAD8),
            title: Text(event.title),
            content: Text('퀴즈를 불러오지 못했습니다. 다시 시도해 주세요.\n$error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      );
      return;
    }
    if (!mounted) {
      return;
    }

    if (questions.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFFF6EAD8),
            title: Text(event.title),
            content: const Text('해당 사건의 퀴즈가 아직 준비되지 않았습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      );
      return;
    }

    final selectedAnswers = List<int?>.filled(questions.length, null);
    int currentIndex = 0;
    int score = 0;
    bool didPass = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final question = questions[currentIndex];
            final isLast = currentIndex == questions.length - 1;
            final canMoveNext = selectedAnswers[currentIndex] != null;

            return Dialog(
              backgroundColor: const Color(0xFFF6EAD8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.title} - 퀴즈',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${currentIndex + 1} / ${questions.length}'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question.question,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...question.choices.asMap().entries.map((entry) {
                                final index = entry.key;
                                final choice = entry.value;
                                return RadioListTile<int>(
                                  dense: true,
                                  value: index,
                                  groupValue: selectedAnswers[currentIndex],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(() {
                                      selectedAnswers[currentIndex] = value;
                                    });
                                  },
                                  title: Text(
                                    choice,
                                    style: const TextStyle(
                                      color: Color(0xFF332A1D),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (currentIndex > 0)
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  currentIndex -= 1;
                                });
                              },
                              child: const Text('이전'),
                            ),
                          FilledButton(
                            onPressed: !canMoveNext
                                ? null
                                : () async {
                                    if (!isLast) {
                                      setDialogState(() {
                                        currentIndex += 1;
                                      });
                                      return;
                                    }

                                    score = 0;
                                    for (var i = 0; i < questions.length; i++) {
                                      if (selectedAnswers[i] ==
                                          questions[i].answerIndex) {
                                        score += 1;
                                      }
                                    }
                                    didPass = score == questions.length;

                                    await showDialog<void>(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          backgroundColor: const Color(
                                            0xFFF6EAD8,
                                          ),
                                          title: const Text('제출 결과'),
                                          content: Text(
                                            didPass
                                                ? '총 ${questions.length}문제 중 $score문제를 맞췄습니다.\n모든 문제 정답입니다.'
                                                : '총 ${questions.length}문제 중 $score문제를 맞췄습니다.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: const Text('확인'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.of(context).pop();
                                  },
                            child: Text(isLast ? '제출' : '다음'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!didPass) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final timeline = controller.mergedTimeline();
    final testamentEras =
        state.eras
            .where((era) => _eraTestament(era) == state.selectedTestament)
            .toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final selectedEra = state.eras
        .where((era) => era.id == state.selectedEraId)
        .firstOrNull;
    final selectedPersonCodes = state.persons
        .where((person) => state.selectedPersonIds.contains(person.id))
        .map((person) => person.code)
        .toSet();
    final avatarByPersonId = <String, String>{
      for (final person in state.persons) person.id: person.avatarAssetPath,
    };
    final showPaulJourneySelector =
        selectedEra?.code == 'era_nt_apostolic' &&
        selectedPersonCodes.contains('paul');
    final listEmptyMessage =
        showPaulJourneySelector && state.selectedPaulJourney == null
        ? '바울의 여정(1차/2차/3차/로마)을 먼저 선택해 주세요.'
        : '선택된 인물의 사건이 없습니다.';

    final mapCenter =
        selectedEra?.mapCenterLat != null && selectedEra?.mapCenterLng != null
        ? LatLng(selectedEra!.mapCenterLat!, selectedEra.mapCenterLng!)
        : null;

    final mapZoom = selectedEra?.mapZoom;
    final topInset = MediaQuery.of(context).padding.top;
    const outerMargin = 20.0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: StoryMapPanel(
              events: timeline,
              selectedEventId: state.selectedEventId,
              onSelectEvent: _handleEventSelect,
              onOpenDetail: _openEventDetail,
              colorForPerson: controller.colorForPerson,
              avatarAssetForPerson: (personId) =>
                  avatarByPersonId[personId] ?? '',
              selectedPersonIds: state.selectedPersonIds,
              controller: _mapPanelController,
              initialCenter: mapCenter,
              initialZoom: mapZoom,
              decorate: false,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final usableWidth = constraints.maxWidth - outerMargin * 2;
              final leftPanelWidth = (usableWidth * 0.235).clamp(176.0, 252.0);
              final rightPanelWidth = (usableWidth * 0.225).clamp(176.0, 252.0);
              const eraHeight = 60.0;
              final sideTop = topInset + 12;
              const sideBottom = 8.0;
              final showLeftPanel = state.selectedEraId != null;
              final showRightPanel = state.selectedPersonIds.isNotEmpty;
              const selectorGap = 4.0;
              final selectorLeftInset =
                  outerMargin +
                  (showLeftPanel ? leftPanelWidth + selectorGap : 0);
              final selectorRightInset =
                  outerMargin +
                  (showRightPanel ? rightPanelWidth + selectorGap : 0);
              final selectorAvailableWidth =
                  constraints.maxWidth - selectorLeftInset - selectorRightInset;
              final useInsetsForSelector = selectorAvailableWidth >= 220;
              final selectorLeft = useInsetsForSelector
                  ? selectorLeftInset
                  : outerMargin;
              final selectorRight = useInsetsForSelector
                  ? selectorRightInset
                  : outerMargin;
              final rightPanelLeft = showRightPanel
                  ? constraints.maxWidth - outerMargin - rightPanelWidth
                  : constraints.maxWidth - outerMargin;
              final controlsLeft = ((rightPanelLeft - 52).clamp(
                outerMargin + 4,
                rightPanelLeft,
              )).toDouble();

              return Stack(
                children: [
                  if (showLeftPanel)
                    Positioned(
                      left: outerMargin,
                      top: sideTop,
                      bottom: sideBottom,
                      width: leftPanelWidth,
                      child: PersonPanel(
                        persons: state.persons,
                        selectedPersonIds: state.selectedPersonIds,
                        onToggle: controller.togglePerson,
                        colorForPerson: controller.colorForPerson,
                        sortMode: _personSortMode,
                        onSortModeChanged: (mode) {
                          setState(() {
                            _personSortMode = mode;
                          });
                        },
                      ),
                    ),
                  if (showLeftPanel && showPaulJourneySelector)
                    Positioned(
                      left: outerMargin + leftPanelWidth + 8,
                      top: sideTop + 2,
                      width: 128,
                      child: _PaulJourneySelector(
                        selectedJourneyKey: state.selectedPaulJourney,
                        onSelect: (journeyKey) {
                          if (state.selectedPaulJourney == journeyKey) {
                            controller.selectPaulJourney(null);
                            return;
                          }
                          controller.selectPaulJourney(journeyKey);
                        },
                      ),
                    ),
                  if (showRightPanel)
                    Positioned(
                      right: outerMargin,
                      top: sideTop,
                      bottom: sideBottom,
                      width: rightPanelWidth,
                      child: StoryListPanel(
                        events: timeline,
                        selectedEventId: state.selectedEventId,
                        completedEventIds: state.completedEventIds,
                        onSelectEvent: _handleEventSelect,
                        onStartQuiz: _startQuiz,
                        colorForPerson: controller.colorForPerson,
                        selectedPersonIds: state.selectedPersonIds,
                        emptyMessage: listEmptyMessage,
                      ),
                    ),
                  Positioned(
                    left: controlsLeft,
                    top: sideTop,
                    child: Column(
                      children: [
                        _mapControlButton(
                          icon: Icons.search,
                          tooltip: '검색',
                          onTap: _openSearchSheet,
                        ),
                        const SizedBox(height: 8),
                        _mapControlButton(
                          icon: Icons.add,
                          tooltip: '줌 인',
                          onTap: _mapPanelController.zoomIn,
                        ),
                        const SizedBox(height: 6),
                        _mapControlButton(
                          icon: Icons.remove,
                          tooltip: '줌 아웃',
                          onTap: _mapPanelController.zoomOut,
                        ),
                        const SizedBox(height: 6),
                        _mapControlButton(
                          icon: Icons.fast_forward,
                          tooltip: 'Skip',
                          onTap: _mapPanelController.skipAnimation,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: selectorLeft,
                    right: selectorRight,
                    bottom: 20,
                    child: Align(
                      alignment: Alignment.center,
                      child: (!showLeftPanel && !showRightPanel)
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IntrinsicWidth(
                                  child: SizedBox(
                                    height: eraHeight,
                                    child: EraSelector(
                                      eras: testamentEras,
                                      selectedEraId: state.selectedEraId,
                                      onSelect: (eraId) {
                                        controller.toggleEra(eraId);
                                      },
                                      selectedTestament:
                                          state.selectedTestament,
                                      onSelectTestament:
                                          controller.selectTestament,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: _utilityImageButton(
                                    assetPath: kBookButtonAsset,
                                    size: eraHeight,
                                    visualScale: 0.85,
                                    onTap: _openBibleReaderPopup,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: _utilityImageButton(
                                    assetPath: kProfileButtonAsset,
                                    size: eraHeight,
                                    visualScale: 0.85,
                                  ),
                                ),
                              ],
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: eraHeight,
                              child: EraSelector(
                                eras: testamentEras,
                                selectedEraId: state.selectedEraId,
                                onSelect: (eraId) {
                                  controller.toggleEra(eraId);
                                },
                                selectedTestament: state.selectedTestament,
                                onSelectTestament: controller.selectTestament,
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (state.error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 86,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xAA000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          if (state.loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaulJourneySelector extends StatelessWidget {
  const _PaulJourneySelector({
    required this.selectedJourneyKey,
    required this.onSelect,
  });

  final String? selectedJourneyKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <(String, String)>[
      ('j1', '1차 여행'),
      ('j2', '2차 여행'),
      ('j3', '3차 여행'),
      ('rome', '로마 여정'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9D6BA).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9F7A4C), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '바울 여정',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFDF8EE),
              shadows: [
                Shadow(
                  color: Color(0xAA000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((entry) {
            final key = entry.$1;
            final label = entry.$2;
            final selected = selectedJourneyKey == key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => onSelect(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFE08A1E)
                        : const Color(0xFF5E4934),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFE6BF)
                          : const Color(0xFFD2B084),
                      width: selected ? 2 : 1.1,
                    ),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFDF8EE),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      shadows: [
                        Shadow(
                          color: Color(0xAA000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

Widget _mapControlButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
}) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xCC2A2118),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD8BF99)),
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFFF8EED9), size: 20),
    ),
  );
}

Widget _utilityImageButton({
  required String assetPath,
  double size = 44,
  double visualScale = 1.14,
  VoidCallback? onTap,
}) {
  final image = Transform.scale(
    scale: visualScale,
    alignment: Alignment.center,
    child: Image.asset(assetPath, fit: BoxFit.contain),
  );

  return SizedBox(
    width: size,
    height: size,
    child: onTap == null
        ? image
        : GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.translucent,
            child: image,
          ),
  );
}

Widget _bibleDropdownFrame<T>({
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return SizedBox(
    height: 38,
    child: DecoratedBox(
      decoration: statesButtonDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            iconSize: 12,
            borderRadius: BorderRadius.circular(10),
            dropdownColor: const Color(0xFF4E3A26),
            iconEnabledColor: const Color(0xFFFDF8EE),
            style: const TextStyle(
              color: Color(0xFFFDF8EE),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              shadows: [
                Shadow(
                  color: Color(0xAA000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

class _BibleBookMeta {
  const _BibleBookMeta({required this.name, required this.chapters});

  final String name;
  final int chapters;
}

class _BibleNavigationTarget {
  const _BibleNavigationTarget({
    required this.bookNo,
    required this.chapterNo,
    required this.verseNo,
  });

  final int bookNo;
  final int chapterNo;
  final int verseNo;
}

String _normalizeBibleBookKey(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
}

final Map<String, int> _kBibleRefBookLookup = () {
  final map = <String, int>{};
  for (var i = 0; i < _kBibleBooks.length; i++) {
    map[_normalizeBibleBookKey(_kBibleBooks[i].name)] = i + 1;
  }
  map.addAll(_kBibleRefAliasBookLookup);
  return map;
}();

const Map<String, int> _kBibleRefAliasBookLookup = {
  '창': 1,
  '출': 2,
  '레': 3,
  '민': 4,
  '신': 5,
  '수': 6,
  '삿': 7,
  '룻': 8,
  '삼상': 9,
  '삼하': 10,
  '왕상': 11,
  '왕하': 12,
  '대상': 13,
  '대하': 14,
  '스': 15,
  '느': 16,
  '에': 17,
  '욥': 18,
  '시': 19,
  '잠': 20,
  '전': 21,
  '아': 22,
  '사': 23,
  '렘': 24,
  '애': 25,
  '겔': 26,
  '단': 27,
  '호': 28,
  '욜': 29,
  '암': 30,
  '옵': 31,
  '욘': 32,
  '미': 33,
  '나': 34,
  '합': 35,
  '습': 36,
  '학': 37,
  '슥': 38,
  '말': 39,
  '마': 40,
  '막': 41,
  '눅': 42,
  '요': 43,
  '행': 44,
  '롬': 45,
  '고전': 46,
  '고후': 47,
  '갈': 48,
  '엡': 49,
  '빌': 50,
  '골': 51,
  '살전': 52,
  '살후': 53,
  '딤전': 54,
  '딤후': 55,
  '딛': 56,
  '몬': 57,
  '히': 58,
  '약': 59,
  '벧전': 60,
  '벧후': 61,
  '요일': 62,
  '요이': 63,
  '요삼': 64,
  '유': 65,
  '계': 66,
};

_BibleNavigationTarget? _parseBibleNavigationTarget(String? rawRef) {
  if (rawRef == null) {
    return null;
  }
  final normalized = rawRef
      .replaceAll('：', ':')
      .replaceAll('∼', '-')
      .replaceAll('~', '-')
      .trim();
  if (normalized.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^([가-힣]+)\s*(\d+)\s*[:장]\s*(\d+)',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final rawBook = match.group(1) ?? '';
  final bookNo = _kBibleRefBookLookup[_normalizeBibleBookKey(rawBook)];
  if (bookNo == null) {
    return null;
  }

  final chapterNo = int.tryParse(match.group(2) ?? '');
  final verseNo = int.tryParse(match.group(3) ?? '');
  if (chapterNo == null || chapterNo <= 0 || verseNo == null || verseNo <= 0) {
    return null;
  }

  final maxChapter = _kBibleBooks[bookNo - 1].chapters;
  final safeChapter = chapterNo > maxChapter ? maxChapter : chapterNo;
  return _BibleNavigationTarget(
    bookNo: bookNo,
    chapterNo: safeChapter,
    verseNo: verseNo,
  );
}

const List<_BibleBookMeta> _kBibleBooks = [
  _BibleBookMeta(name: '창세기', chapters: 50),
  _BibleBookMeta(name: '출애굽기', chapters: 40),
  _BibleBookMeta(name: '레위기', chapters: 27),
  _BibleBookMeta(name: '민수기', chapters: 36),
  _BibleBookMeta(name: '신명기', chapters: 34),
  _BibleBookMeta(name: '여호수아', chapters: 24),
  _BibleBookMeta(name: '사사기', chapters: 21),
  _BibleBookMeta(name: '룻기', chapters: 4),
  _BibleBookMeta(name: '사무엘상', chapters: 31),
  _BibleBookMeta(name: '사무엘하', chapters: 24),
  _BibleBookMeta(name: '열왕기상', chapters: 22),
  _BibleBookMeta(name: '열왕기하', chapters: 25),
  _BibleBookMeta(name: '역대상', chapters: 29),
  _BibleBookMeta(name: '역대하', chapters: 36),
  _BibleBookMeta(name: '에스라', chapters: 10),
  _BibleBookMeta(name: '느헤미야', chapters: 13),
  _BibleBookMeta(name: '에스더', chapters: 10),
  _BibleBookMeta(name: '욥기', chapters: 42),
  _BibleBookMeta(name: '시편', chapters: 150),
  _BibleBookMeta(name: '잠언', chapters: 31),
  _BibleBookMeta(name: '전도서', chapters: 12),
  _BibleBookMeta(name: '아가', chapters: 8),
  _BibleBookMeta(name: '이사야', chapters: 66),
  _BibleBookMeta(name: '예레미야', chapters: 52),
  _BibleBookMeta(name: '예레미야애가', chapters: 5),
  _BibleBookMeta(name: '에스겔', chapters: 48),
  _BibleBookMeta(name: '다니엘', chapters: 12),
  _BibleBookMeta(name: '호세아', chapters: 14),
  _BibleBookMeta(name: '요엘', chapters: 3),
  _BibleBookMeta(name: '아모스', chapters: 9),
  _BibleBookMeta(name: '오바댜', chapters: 1),
  _BibleBookMeta(name: '요나', chapters: 4),
  _BibleBookMeta(name: '미가', chapters: 7),
  _BibleBookMeta(name: '나훔', chapters: 3),
  _BibleBookMeta(name: '하박국', chapters: 3),
  _BibleBookMeta(name: '스바냐', chapters: 3),
  _BibleBookMeta(name: '학개', chapters: 2),
  _BibleBookMeta(name: '스가랴', chapters: 14),
  _BibleBookMeta(name: '말라기', chapters: 4),
  _BibleBookMeta(name: '마태복음', chapters: 28),
  _BibleBookMeta(name: '마가복음', chapters: 16),
  _BibleBookMeta(name: '누가복음', chapters: 24),
  _BibleBookMeta(name: '요한복음', chapters: 21),
  _BibleBookMeta(name: '사도행전', chapters: 28),
  _BibleBookMeta(name: '로마서', chapters: 16),
  _BibleBookMeta(name: '고린도전서', chapters: 16),
  _BibleBookMeta(name: '고린도후서', chapters: 13),
  _BibleBookMeta(name: '갈라디아서', chapters: 6),
  _BibleBookMeta(name: '에베소서', chapters: 6),
  _BibleBookMeta(name: '빌립보서', chapters: 4),
  _BibleBookMeta(name: '골로새서', chapters: 4),
  _BibleBookMeta(name: '데살로니가전서', chapters: 5),
  _BibleBookMeta(name: '데살로니가후서', chapters: 3),
  _BibleBookMeta(name: '디모데전서', chapters: 6),
  _BibleBookMeta(name: '디모데후서', chapters: 4),
  _BibleBookMeta(name: '디도서', chapters: 3),
  _BibleBookMeta(name: '빌레몬서', chapters: 1),
  _BibleBookMeta(name: '히브리서', chapters: 13),
  _BibleBookMeta(name: '야고보서', chapters: 5),
  _BibleBookMeta(name: '베드로전서', chapters: 5),
  _BibleBookMeta(name: '베드로후서', chapters: 3),
  _BibleBookMeta(name: '요한일서', chapters: 5),
  _BibleBookMeta(name: '요한이서', chapters: 1),
  _BibleBookMeta(name: '요한삼서', chapters: 1),
  _BibleBookMeta(name: '유다서', chapters: 1),
  _BibleBookMeta(name: '요한계시록', chapters: 22),
];
