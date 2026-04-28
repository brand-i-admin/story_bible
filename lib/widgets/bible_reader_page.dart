import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bible_verse.dart';
import '../models/saved_bible_verse.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../utils/bible_book_meta.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

/// 성경 리더 페이지.
///
/// 구약/신약 토글, 책/장 선택, 구절 표시, 북마크(saved verses) 토글을 제공한다.
///
/// [initialBookNo]/[initialChapterNo]/[initialVerseNo]가 주어지면 해당 구절로
/// 자동 스크롤한다.
class BibleReaderPage extends ConsumerStatefulWidget {
  const BibleReaderPage({
    super.key,
    this.initialBookNo,
    this.initialChapterNo,
    this.initialVerseNo,
  });

  final int? initialBookNo;
  final int? initialChapterNo;
  final int? initialVerseNo;

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

  @override
  void initState() {
    super.initState();
    _selectedBookNo = (widget.initialBookNo ?? 1).clamp(1, bibleBooks.length);
    _selectedTestament = _selectedBookNo >= 40 ? 'new' : 'old';
    _selectedChapter = widget.initialChapterNo ?? 1;
    _pendingFocusVerse = (widget.initialVerseNo ?? 0) > 0
        ? widget.initialVerseNo
        : null;
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

  Future<void> _toggleSavedVerse(BibleVerse verse, String verseKey) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }
    try {
      final didSave = await ref
          .read(userRepositoryProvider)
          .toggleSavedVerse(userId: user.id, verse: verse);
      if (!mounted) {
        return;
      }
      setState(() {
        if (didSave) {
          _savedVerseKeys.add(verseKey);
        } else {
          _savedVerseKeys.remove(verseKey);
        }
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(didSave ? '저장되었어요' : '저장이 삭제되었어요')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 중 오류가 발생했습니다.\n$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(signedInUserProvider);
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: floatingPanelDecoration(
            color: const Color(0xF5F7E9D1),
            shadowOpacity: 0.10,
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: bibleDropdownFrame<String>(
                        value: _selectedTestament,
                        items: const [
                          DropdownMenuItem(value: 'old', child: Text('구약')),
                          DropdownMenuItem(value: 'new', child: Text('신약')),
                        ],
                        onChanged: (testament) {
                          if (testament == null) {
                            return;
                          }
                          setState(() {
                            _selectedTestament = testament;
                            final nextBooks = _booksForTestament(
                              _selectedTestament,
                            );
                            if (nextBooks.isEmpty) {
                              return;
                            }
                            final inSameTestament = _selectedTestament == 'new'
                                ? _selectedBookNo >= 40
                                : _selectedBookNo <= 39;
                            if (!inSameTestament) {
                              _selectedBookNo = nextBooks.first.key + 1;
                            }
                            final maxChapter =
                                bibleBooks[_selectedBookNo - 1].chapters;
                            if (_selectedChapter > maxChapter) {
                              _selectedChapter = maxChapter;
                            }
                            _pendingFocusVerse = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 172,
                      child: bibleDropdownFrame<int>(
                        value: selectedBookNoSafe,
                        items: testamentBooks
                            .map(
                              (entry) => DropdownMenuItem<int>(
                                value: entry.key + 1,
                                child: Text(
                                  entry.value.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (bookNo) {
                          if (bookNo == null) {
                            return;
                          }
                          setState(() {
                            _selectedBookNo = bookNo;
                            final maxChapter = bibleBooks[bookNo - 1].chapters;
                            if (_selectedChapter > maxChapter) {
                              _selectedChapter = maxChapter;
                            }
                            _pendingFocusVerse = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: bibleDropdownFrame<int>(
                        value: selectedChapterSafe,
                        items: chapterItems
                            .map(
                              (chapter) => DropdownMenuItem<int>(
                                value: chapter,
                                child: Text('$chapter장'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (chapter) {
                          if (chapter == null) {
                            return;
                          }
                          setState(() {
                            _selectedChapter = chapter;
                            _pendingFocusVerse = null;
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
                  decoration: floatingPanelDecoration(
                    color: const Color(0xF4EFE3CC),
                    shadowOpacity: 0.06,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: FutureBuilder<List<BibleVerse>>(
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

                      final verses = snapshot.data ?? const <BibleVerse>[];
                      final focusVerseNo = _pendingFocusVerse;
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
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final targetContext = focusVerseKey.currentContext;
                          if (targetContext != null) {
                            Scrollable.ensureVisible(
                              targetContext,
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              alignment: 0.12,
                            );
                          }
                          _pendingFocusVerse = null;
                        });
                      }

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                              final verseKey = SavedBibleVerse.buildVerseKey(
                                translation: verse.translation,
                                bookNo: verse.bookNo,
                                chapterNo: verse.chapterNo,
                                verseNo: verse.verseNo,
                              );
                              final isSaved = _savedVerseKeys.contains(
                                verseKey,
                              );
                              return Padding(
                                key:
                                    focusVerseNo != null &&
                                        verse.verseNo == focusVerseNo
                                    ? focusVerseKey
                                    : null,
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: user == null
                                        ? null
                                        : () => _toggleSavedVerse(
                                            verse,
                                            verseKey,
                                          ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSaved
                                            ? const Color(0x3DE2BE57)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text.rich(
                                        TextSpan(
                                          style: const TextStyle(
                                            color: Color(0xFF3B2A17),
                                            fontSize: 15,
                                            height: 1.25,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: '${verse.verseNo} ',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            TextSpan(text: verse.verseText),
                                          ],
                                        ),
                                      ),
                                    ),
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
      ),
    );
  }
}
