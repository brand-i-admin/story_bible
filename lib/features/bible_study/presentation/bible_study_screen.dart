import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../screens/story_home_screen.dart';
import '../../../shared/widgets/parchment_background.dart';
import '../../../widgets/game_ui_skin.dart';
import '../data/models/bible_event_model.dart';
import '../data/models/verse_page_model.dart';
import '../domain/bible_study_notifier.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/left_panel/book_selector_dropdown.dart';
import 'widgets/left_panel/event_list.dart';
import 'widgets/left_panel/progress_strip.dart';
import 'widgets/left_panel/testament_toggle.dart';
import 'widgets/right_panel/detail_hero.dart';
import 'widgets/right_panel/detail_tags.dart';
import 'widgets/right_panel/detail_title_row.dart';
import 'widgets/right_panel/key_message_box.dart';
import 'widgets/right_panel/verse_full_box.dart';
import 'widgets/top_bar.dart';

class BibleStudyScreen extends ConsumerStatefulWidget {
  const BibleStudyScreen({super.key});

  @override
  ConsumerState<BibleStudyScreen> createState() => _BibleStudyScreenState();
}

class _BibleStudyScreenState extends ConsumerState<BibleStudyScreen>
    with RouteAware {
  late final ScrollController _detailScrollController;
  bool _isMobileListExpanded = false;
  PageRoute<dynamic>? _route;
  bool _isRouteObserverSubscribed = false;

  @override
  void initState() {
    super.initState();
    _detailScrollController = ScrollController();
    _setPortraitOrientation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_isRouteObserverSubscribed) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
      _isRouteObserverSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_isRouteObserverSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _setDefaultOrientations();
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _setPortraitOrientation();
  }

  @override
  void didPopNext() {
    _setPortraitOrientation();
  }

  Future<void> _setPortraitOrientation() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _setDefaultOrientations() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _openStoryMapScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StoryHomeScreen()));
  }

  void _openBibleFullscreen() {
    final event = ref.read(bibleStudyNotifierProvider).selectedEvent;
    if (event == null || event.versePages.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BibleFullscreenScreen(
          title: event.title,
          pages: event.versePages,
          initialPage: ref.read(bibleStudyNotifierProvider).currentVersePage,
        ),
      ),
    );
  }

  Future<void> _handleSelectEvent(
    BibleStudyNotifier notifier,
    int index, {
    required bool collapseList,
  }) async {
    await notifier.selectEvent(index);
    if (!mounted) {
      return;
    }
    if (collapseList && _isMobileListExpanded) {
      setState(() => _isMobileListExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bibleStudyNotifierProvider.select((s) => s.selectedEventIdx), (
      _,
      __,
    ) {
      if (_detailScrollController.hasClients) {
        _detailScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final state = ref.watch(bibleStudyNotifierProvider);
    final notifier = ref.read(bibleStudyNotifierProvider.notifier);
    final selectedEvent = state.selectedEvent;
    final media = MediaQuery.of(context);
    final isPhoneLayout = media.size.shortestSide < 600;
    final isPhoneLandscape =
        isPhoneLayout && media.orientation == Orientation.landscape;
    final textScale = isPhoneLayout ? 1.1 : 1.0;
    final topBarHeight = isPhoneLayout ? 52.0 : 46.0;
    final bottomNavHeight = isPhoneLayout ? 50.0 : 44.0;
    final mobilePanelWidth = isPhoneLandscape
        ? (media.size.width * 0.50).clamp(240.0, 360.0)
        : (media.size.width * 0.84).clamp(240.0, 360.0);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: AppColors.woodDark,
        body: SafeArea(
          child: Column(
            children: [
              TopBar(
                height: topBarHeight,
                onListMenuTap: isPhoneLayout
                    ? () {
                        setState(
                          () => _isMobileListExpanded = !_isMobileListExpanded,
                        );
                      }
                    : null,
              ),
              Expanded(
                child: isPhoneLayout
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: ParchmentBackground(
                              child: _RightPanel(
                                state: state,
                                selectedEvent: selectedEvent,
                                onPrevEvent: () => notifier.moveEvent(-1),
                                onNextEvent: () => notifier.moveEvent(1),
                                onPrevVerse: notifier.prevVersePage,
                                onNextVerse: notifier.nextVersePage,
                                onOpenBibleFullscreen: _openBibleFullscreen,
                                onToggleComplete: notifier.toggleComplete,
                                onOpenMap: _openStoryMapScreen,
                                detailScrollController: _detailScrollController,
                              ),
                            ),
                          ),
                          if (_isMobileListExpanded)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _isMobileListExpanded = false,
                                ),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            top: 0,
                            bottom: 0,
                            left: _isMobileListExpanded
                                ? 0
                                : -mobilePanelWidth - 16,
                            width: mobilePanelWidth,
                            child: Material(
                              elevation: 10,
                              color: Colors.transparent,
                              child: _LeftPanelScaffold(
                                state: state,
                                notifier: notifier,
                                showRightBorder: true,
                                onSelectEvent: (index) => _handleSelectEvent(
                                  notifier,
                                  index,
                                  collapseList: true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 300,
                            child: _LeftPanelScaffold(
                              state: state,
                              notifier: notifier,
                              showRightBorder: true,
                              onSelectEvent: (index) =>
                                  notifier.selectEvent(index),
                            ),
                          ),
                          Expanded(
                            child: ParchmentBackground(
                              child: _RightPanel(
                                state: state,
                                selectedEvent: selectedEvent,
                                onPrevEvent: () => notifier.moveEvent(-1),
                                onNextEvent: () => notifier.moveEvent(1),
                                onPrevVerse: notifier.prevVersePage,
                                onNextVerse: notifier.nextVersePage,
                                onOpenBibleFullscreen: _openBibleFullscreen,
                                onToggleComplete: notifier.toggleComplete,
                                onOpenMap: _openStoryMapScreen,
                                detailScrollController: _detailScrollController,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              BottomNav(onMapTap: _openStoryMapScreen, height: bottomNavHeight),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeftPanelScaffold extends StatelessWidget {
  const _LeftPanelScaffold({
    required this.state,
    required this.notifier,
    required this.onSelectEvent,
    required this.showRightBorder,
  });

  final BibleStudyState state;
  final BibleStudyNotifier notifier;
  final ValueChanged<int> onSelectEvent;
  final bool showRightBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: panelFrameDecoration().copyWith(
        color: const Color(0xFF1E0E04),
        border: showRightBorder
            ? const Border(
                right: BorderSide(color: AppColors.woodDark, width: 2),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 28, 8, 14),
        child: Column(
          children: [
            TestamentToggle(
              value: state.testament,
              onChanged: (value) => notifier.selectTestament(value),
            ),
            BookSelectorDropdown(
              books: state.books,
              selectedBook: state.selectedBook,
              onBookSelected: notifier.selectBook,
            ),
            ProgressStrip(
              total: state.events.length,
              completed: state.events.where((e) => e.isCompleted).length,
              currentIndex: state.selectedEventIdx,
              onDotTap: onSelectEvent,
              isDone: (index) => state.events[index].isCompleted,
            ),
            EventList(
              events: state.events,
              selectedIndex: state.selectedEventIdx,
              onSelect: onSelectEvent,
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.state,
    required this.selectedEvent,
    required this.onPrevEvent,
    required this.onNextEvent,
    required this.onPrevVerse,
    required this.onNextVerse,
    required this.onOpenBibleFullscreen,
    required this.onToggleComplete,
    required this.onOpenMap,
    required this.detailScrollController,
  });

  final BibleStudyState state;
  final BibleEvent? selectedEvent;
  final VoidCallback onPrevEvent;
  final VoidCallback onNextEvent;
  final VoidCallback onPrevVerse;
  final VoidCallback onNextVerse;
  final VoidCallback onOpenBibleFullscreen;
  final VoidCallback onToggleComplete;
  final VoidCallback onOpenMap;
  final ScrollController detailScrollController;

  @override
  Widget build(BuildContext context) {
    final event = selectedEvent;
    if (state.isLoading && event == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.woodMid),
      );
    }
    if (event == null) {
      return Center(
        child: Text(
          state.error ?? '표시할 사건이 없습니다.',
          style: GoogleFonts.notoSerifKr(fontSize: 14, color: AppColors.inkMid),
        ),
      );
    }

    return SingleChildScrollView(
      controller: detailScrollController,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailTitleRow(
            event: event,
            canMovePrev: state.selectedEventIdx > 0,
            canMoveNext: state.selectedEventIdx < state.events.length - 1,
            onMovePrev: onPrevEvent,
            onMoveNext: onNextEvent,
          ),
          if (state.isDetailLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 6),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.woodMid,
                backgroundColor: Color(0x339B7444),
              ),
            ),
          DetailHero(emoji: event.emoji),
          DetailTags(places: event.places, persons: event.persons),
          VerseFullBox(
            pages: event.versePages,
            currentPage: state.currentVersePage,
            onPrev: onPrevVerse,
            onNext: onNextVerse,
            onOpenFullscreen: onOpenBibleFullscreen,
          ),
          if (event.summary.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: Color(0x1FE8C56A),
                border: Border(
                  left: BorderSide(color: Color(0xFFC9942A), width: 3),
                ),
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(6),
                ),
              ),
              child: Text(
                event.summary,
                style: GoogleFonts.notoSerifKr(
                  fontSize: 12,
                  color: const Color(0xFF3D1F08),
                  height: 1.6,
                ),
              ),
            ),
          KeyMessageBox(title: event.boxTitle, points: event.points),
          _ActionRow(
            isCompleted: event.isCompleted,
            onToggleComplete: onToggleComplete,
            onOpenMap: onOpenMap,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isCompleted,
    required this.onToggleComplete,
    required this.onOpenMap,
  });

  final bool isCompleted;
  final VoidCallback onToggleComplete;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggleComplete,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            decoration: statesButtonDecoration(),
            child: Center(
              child: Text(
                isCompleted ? '✓ 학습 완료됨' : '○ 학습 완료 표시',
                style: GoogleFonts.nanumMyeongjo(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isCompleted
                      ? const Color(0xFFEAF9D8)
                      : const Color(0xFFFDF8EE),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: _QuickCard(icon: '❓', label: '묵상 퀴즈'),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _QuickCard(
                icon: '🗺',
                label: '지도 보기',
                onTap: onOpenMap,
                highlighted: true,
              ),
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: _QuickCard(icon: '👤', label: '인물 보기'),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 58,
        child: DecoratedBox(
          decoration: tabItemDecoration(selected: highlighted),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.notoSerifKr(
                  fontSize: 8.5,
                  color: highlighted
                      ? const Color(0xFFFDF8EE)
                      : AppColors.goldDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BibleFullscreenScreen extends StatefulWidget {
  const _BibleFullscreenScreen({
    required this.title,
    required this.pages,
    required this.initialPage,
  });

  final String title;
  final List<VersePage> pages;
  final int initialPage;

  @override
  State<_BibleFullscreenScreen> createState() => _BibleFullscreenScreenState();
}

class _BibleFullscreenScreenState extends State<_BibleFullscreenScreen> {
  late final List<_FullscreenVerseItem> _items;
  final GlobalKey _initialItemKey = GlobalKey();
  int? _initialItemIndex;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _items = _buildFullscreenVerseItems(widget.pages);
    if (_items.isNotEmpty) {
      final safeInitial = widget.initialPage.clamp(0, widget.pages.length - 1);
      _initialItemIndex = _items.indexWhere(
        (item) => item.sourcePageIndex == safeInitial,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToInitialVerse(),
    );
  }

  Future<void> _scrollToInitialVerse() async {
    if (_didInitialScroll || !mounted) {
      return;
    }
    _didInitialScroll = true;
    final context = _initialItemKey.currentContext;
    if (context == null) {
      return;
    }
    await Scrollable.ensureVisible(
      context,
      alignment: 0.08,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.woodDark,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: tabBarDecoration().copyWith(
                color: const Color(0xFF3A1E06),
                border: const Border(
                  bottom: BorderSide(color: AppColors.woodDark, width: 2.5),
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Icon(Icons.close, color: Color(0xFFFDF8EE)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.title} 본문',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nanumMyeongjo(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF5E4A8),
                      ),
                    ),
                  ),
                  Text(
                    '${_items.where((e) => e.type == _FullscreenVerseItemType.verse).length}절',
                    style: GoogleFonts.notoSerifKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD9BE7A),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ParchmentBackground(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          '표시할 본문이 없습니다.',
                          style: GoogleFonts.notoSerifKr(
                            fontSize: 14,
                            color: AppColors.inkMid,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                        children: [
                          for (var index = 0; index < _items.length; index++)
                            _buildFullscreenItem(
                              index: index,
                              item: _items[index],
                              isInitialTarget: index == _initialItemIndex,
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenItem({
    required int index,
    required _FullscreenVerseItem item,
    required bool isInitialTarget,
  }) {
    switch (item.type) {
      case _FullscreenVerseItemType.chapterHeader:
        final parsed = item.parsedRef!;
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12, bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x18A96A1B),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x52A96A1B)),
            ),
            child: Text(
              '${parsed.book} ${parsed.chapter}장',
              style: GoogleFonts.nanumMyeongjo(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF5B2F0E),
              ),
            ),
          ),
        );
      case _FullscreenVerseItemType.verse:
        final parsed = item.parsedRef!;
        final verseRow = Padding(
          key: isInitialTarget ? _initialItemKey : null,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${parsed.verse}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.nanumMyeongjo(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.text,
                  style: GoogleFonts.notoSerifKr(
                    fontSize: 16,
                    height: 1.9,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        );
        return verseRow;
      case _FullscreenVerseItemType.fallback:
        final fallbackCard = Padding(
          key: isInitialTarget ? _initialItemKey : null,
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0x14A96A1B),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x35A96A1B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.ref.isNotEmpty) ...[
                  Text(
                    item.ref,
                    style: GoogleFonts.nanumMyeongjo(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF5B2F0E),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  item.text,
                  style: GoogleFonts.notoSerifKr(
                    fontSize: 15,
                    height: 1.8,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        );
        return fallbackCard;
    }
  }
}

List<_FullscreenVerseItem> _buildFullscreenVerseItems(List<VersePage> pages) {
  final items = <_FullscreenVerseItem>[];
  String? lastBook;
  int? lastChapter;

  for (var index = 0; index < pages.length; index++) {
    final page = pages[index];
    final parsedRef = _parseVerseRef(page.ref);
    if (parsedRef == null) {
      items.add(
        _FullscreenVerseItem.fallback(
          ref: page.ref,
          text: page.text.trim(),
          sourcePageIndex: index,
        ),
      );
      continue;
    }

    if (parsedRef.book != lastBook || parsedRef.chapter != lastChapter) {
      items.add(_FullscreenVerseItem.chapterHeader(parsedRef));
      lastBook = parsedRef.book;
      lastChapter = parsedRef.chapter;
    }
    items.add(
      _FullscreenVerseItem.verse(
        parsedRef: parsedRef,
        text: page.text.trim(),
        sourcePageIndex: index,
      ),
    );
  }

  return items;
}

_ParsedVerseRef? _parseVerseRef(String rawRef) {
  final normalized = rawRef.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return null;
  }

  final match = RegExp(r'^(.+?)\s+(\d+):(\d+)$').firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final book = (match.group(1) ?? '').trim();
  final chapter = int.tryParse(match.group(2) ?? '');
  final verse = int.tryParse(match.group(3) ?? '');
  if (book.isEmpty || chapter == null || verse == null) {
    return null;
  }

  return _ParsedVerseRef(book: book, chapter: chapter, verse: verse);
}

class _ParsedVerseRef {
  const _ParsedVerseRef({
    required this.book,
    required this.chapter,
    required this.verse,
  });

  final String book;
  final int chapter;
  final int verse;
}

enum _FullscreenVerseItemType { chapterHeader, verse, fallback }

class _FullscreenVerseItem {
  const _FullscreenVerseItem._({
    required this.type,
    required this.text,
    required this.ref,
    required this.sourcePageIndex,
    this.parsedRef,
  });

  final _FullscreenVerseItemType type;
  final _ParsedVerseRef? parsedRef;
  final String ref;
  final String text;
  final int? sourcePageIndex;

  factory _FullscreenVerseItem.chapterHeader(_ParsedVerseRef parsedRef) {
    return _FullscreenVerseItem._(
      type: _FullscreenVerseItemType.chapterHeader,
      parsedRef: parsedRef,
      ref: '',
      text: '',
      sourcePageIndex: null,
    );
  }

  factory _FullscreenVerseItem.verse({
    required _ParsedVerseRef parsedRef,
    required String text,
    required int sourcePageIndex,
  }) {
    return _FullscreenVerseItem._(
      type: _FullscreenVerseItemType.verse,
      parsedRef: parsedRef,
      ref: '',
      text: text,
      sourcePageIndex: sourcePageIndex,
    );
  }

  factory _FullscreenVerseItem.fallback({
    required String ref,
    required String text,
    required int sourcePageIndex,
  }) {
    return _FullscreenVerseItem._(
      type: _FullscreenVerseItemType.fallback,
      ref: ref,
      text: text,
      sourcePageIndex: sourcePageIndex,
    );
  }
}
