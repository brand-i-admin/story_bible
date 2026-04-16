import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/person.dart';
import '../models/story_event.dart';
import '../models/weekly_study_data.dart';
import '../state/auth_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import 'story_home_styles.dart';
import 'story_map_panel.dart';
import 'sub_page_scaffold.dart';

/// 금주 인물 학습 탭 페이지.
///
/// 1. 랜덤 또는 지정된 인물의 그 주 이야기 목록 표시
/// 2. 지도에 관련 사건 핀 표시
/// 3. 각 사건 카드에 체크박스 + 퀴즈 버튼
/// 4. 사건 선택 시 상세 팝업
///
/// 외부 콜백:
/// - [onStartQuiz]: 퀴즈 시작 (eventId)
/// - [onOpenEventDetail]: 사건 상세 페이지 열기
class WeeklyTabPage extends ConsumerStatefulWidget {
  const WeeklyTabPage({
    super.key,
    required this.onStartQuiz,
    required this.onOpenEventDetail,
  });

  final void Function(String eventId) onStartQuiz;
  final void Function(StoryEvent event) onOpenEventDetail;

  @override
  ConsumerState<WeeklyTabPage> createState() => _WeeklyTabPageState();
}

class _WeeklyTabPageState extends ConsumerState<WeeklyTabPage> {
  static const Map<String, String> _forcedWeeklyPersonCodeByWeekKey = {
    // Monday, February 23, 2026 week
    '2026-2-23': 'abraham',
  };

  WeeklyStudyData? _weeklyStudyData;
  String? _weeklySelectedEventId;
  final Set<String> _weeklyCheckedEventIds = <String>{};
  bool _weeklyLoading = true;
  String? _weeklyError;
  bool _weeklyShowShortPopup = false;

  @override
  void initState() {
    super.initState();
    _loadWeeklyData();
  }

  StoryEvent? get _weeklySelectedEvent {
    final data = _weeklyStudyData;
    if (data == null || _weeklySelectedEventId == null) {
      return null;
    }
    return data.events
        .where((event) => event.id == _weeklySelectedEventId)
        .firstOrNull;
  }

  DateTime _weekStartMonday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _weeklyKeyFor(DateTime monday) {
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  int _seedFromKey(String key) {
    return key.codeUnits.fold<int>(
      0,
      (acc, value) => ((acc * 31) + value) & 0x7fffffff,
    );
  }

  Future<void> _loadWeeklyData() async {
    final monday = _weekStartMonday(DateTime.now());
    final weekKey = _weeklyKeyFor(monday);
    setState(() {
      _weeklyLoading = true;
      _weeklyError = null;
    });

    try {
      var state = ref.read(storyControllerProvider);
      if (state.eras.isEmpty) {
        await ref.read(storyControllerProvider.notifier).initialize();
        state = ref.read(storyControllerProvider);
      }

      if (state.eras.isEmpty) {
        throw StateError('시대 데이터를 불러오지 못했습니다.');
      }

      final repo = ref.read(storyRepositoryProvider);
      final eraBundles = await Future.wait(
        state.eras.map((era) async {
          final responses = await Future.wait([
            repo.fetchPersonsByEra(era.id),
            repo.fetchEventsByEra(era.id),
          ]);
          return (
            persons: responses[0] as List<Person>,
            events: responses[1] as List<StoryEvent>,
          );
        }),
      );

      final personById = <String, Person>{};
      final eventsByPersonId = <String, List<StoryEvent>>{};
      for (final bundle in eraBundles) {
        for (final person in bundle.persons) {
          personById.putIfAbsent(person.id, () => person);
        }
        for (final event in bundle.events) {
          for (final personId in event.personIds) {
            eventsByPersonId
                .putIfAbsent(personId, () => <StoryEvent>[])
                .add(event);
          }
        }
      }

      final candidates =
          personById.values
              .where(
                (person) =>
                    (eventsByPersonId[person.id] ?? const <StoryEvent>[])
                        .isNotEmpty,
              )
              .toList()
            ..sort((a, b) {
              final order = a.displayOrder.compareTo(b.displayOrder);
              if (order != 0) {
                return order;
              }
              return a.name.compareTo(b.name);
            });
      if (candidates.isEmpty) {
        throw StateError('주간 추천 인물을 찾지 못했습니다.');
      }

      final forcedCode = _forcedWeeklyPersonCodeByWeekKey[weekKey];
      final forcedPerson = forcedCode == null
          ? null
          : candidates.where((person) => person.code == forcedCode).firstOrNull;
      final weeklyPerson =
          forcedPerson ?? candidates[_seedFromKey(weekKey) % candidates.length];
      final weeklyEvents =
          [...(eventsByPersonId[weeklyPerson.id] ?? const <StoryEvent>[])]
            ..sort((a, b) {
              final cmp = a.timeSortKey.compareTo(b.timeSortKey);
              if (cmp != 0) {
                return cmp;
              }
              return a.id.compareTo(b.id);
            });
      final selectedEventId = weeklyEvents.isNotEmpty
          ? weeklyEvents.first.id
          : null;

      if (!mounted) {
        return;
      }
      setState(() {
        _weeklyStudyData = WeeklyStudyData(
          person: weeklyPerson,
          events: weeklyEvents,
          weekStartMonday: monday,
        );
        _weeklySelectedEventId = selectedEventId;
        _weeklyCheckedEventIds.clear();
        _weeklyShowShortPopup = false;
        _weeklyLoading = false;
        _weeklyError = weeklyEvents.isEmpty ? '추천 인물의 이야기가 아직 없습니다.' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weeklyLoading = false;
        _weeklyError = '주간 탭 데이터를 불러오지 못했습니다: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final isAuthenticated = ref.watch(signedInUserProvider) != null;
    final selectedEvent = _weeklySelectedEvent;

    return SubPageScaffold(
      title: '금주 인물',
      compactBackOnly: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: _buildWeeklyBody(
                state: state,
                controller: controller,
                isAuthenticated: isAuthenticated,
                onSelectEvent: (eventId) {
                  setState(() {
                    _weeklySelectedEventId = eventId;
                    _weeklyShowShortPopup = true;
                  });
                },
                onToggleChecked: (eventId) {
                  setState(() {
                    if (_weeklyCheckedEventIds.contains(eventId)) {
                      _weeklyCheckedEventIds.remove(eventId);
                    } else {
                      _weeklyCheckedEventIds.add(eventId);
                    }
                  });
                },
                onStartQuiz: widget.onStartQuiz,
              ),
            ),
          ),
          if (selectedEvent != null && _weeklyShowShortPopup)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 320,
                  child: _weeklyShortPopup(
                    event: selectedEvent,
                    maxHeight: 232,
                    onClose: () {
                      setState(() {
                        _weeklyShowShortPopup = false;
                      });
                    },
                    onOpenDetail: () {
                      setState(() {
                        _weeklyShowShortPopup = false;
                      });
                      widget.onOpenEventDetail(selectedEvent);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBody({
    required StoryState state,
    required StoryController controller,
    required bool isAuthenticated,
    required ValueChanged<String> onSelectEvent,
    required ValueChanged<String> onToggleChecked,
    required ValueChanged<String> onStartQuiz,
  }) {
    final weekly = _weeklyStudyData;
    if (_weeklyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_weeklyError != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _weeklyError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFDF8EE)),
          ),
        ),
      );
    }
    if (weekly == null) {
      return const SizedBox.shrink();
    }

    final completedEventIds = state.completedEventIds;
    final totalStories = weekly.events.length;
    final completedStories = weekly.events
        .where((event) => completedEventIds.contains(event.id))
        .length;
    final weeklyProgress = totalStories == 0
        ? 0.0
        : completedStories / totalStories;
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final todayKst = DateTime(nowKst.year, nowKst.month, nowKst.day);
    final weekStartKst = _weekStartMonday(todayKst);
    final weekEndKst = weekStartKst.add(const Duration(days: 6));
    final daysRemainingKst = math.max(
      0,
      weekEndKst.difference(todayKst).inDays,
    );

    final coordinatePoints = weekly.events
        .where((event) => event.hasCoordinate)
        .map((event) => event.latLng)
        .toList(growable: false);
    LatLng? initialMapCenter;
    if (coordinatePoints.isNotEmpty) {
      var minLat = coordinatePoints.first.latitude;
      var maxLat = coordinatePoints.first.latitude;
      var minLng = coordinatePoints.first.longitude;
      var maxLng = coordinatePoints.first.longitude;
      for (final point in coordinatePoints.skip(1)) {
        if (point.latitude < minLat) {
          minLat = point.latitude;
        }
        if (point.latitude > maxLat) {
          maxLat = point.latitude;
        }
        if (point.longitude < minLng) {
          minLng = point.longitude;
        }
        if (point.longitude > maxLng) {
          maxLng = point.longitude;
        }
      }
      initialMapCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final orientation = MediaQuery.orientationOf(context);
        final useSplitLayout = orientation == Orientation.landscape || w >= 900;
        final contentGap = (w * 0.011).clamp(8.0, 14.0).toDouble();
        final progressHeight = (h * 0.084).clamp(44.0, 58.0).toDouble();
        final mapHeightOnNarrow = (h * 0.44).clamp(220.0, 360.0).toDouble();

        String avatarAssetForPerson(String personId) {
          if (personId == weekly.person.id) {
            return weekly.person.avatarAssetPath;
          }
          final person = state.persons
              .where((p) => p.id == personId)
              .firstOrNull;
          return person?.avatarAssetPath ?? weekly.person.avatarAssetPath;
        }

        final mapPanel = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: StoryMapPanel(
            events: weekly.events,
            selectedEventId: _weeklySelectedEventId,
            onSelectEvent: onSelectEvent,
            colorForPerson: controller.colorForPerson,
            avatarAssetForPerson: avatarAssetForPerson,
            selectedPersonIds: {weekly.person.id},
            decorate: false,
            showSelectedCallout: false,
            animateReveal: false,
            centerSelectedOnReady: false,
            fitAllEventsOnReady: true,
            fitAllZoomAdjust: -0.18,
            pinScale: 1.0,
            initialCenter: initialMapCenter,
            initialZoom: 5.4,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: progressHeight,
              child: _weeklyProgressRow(
                daysRemainingKst: daysRemainingKst,
                completedCount: completedStories,
                totalCount: totalStories,
                progress: weeklyProgress,
              ),
            ),
            if (!isAuthenticated) ...[
              SizedBox(height: contentGap * 0.72),
              _weeklyGuestNoticeBanner(),
            ],
            SizedBox(height: contentGap),
            Expanded(
              child: useSplitLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: mapPanel),
                        SizedBox(width: contentGap),
                        Expanded(
                          flex: 9,
                          child: _buildWeeklyListPanel(
                            weekly: weekly,
                            completedEventIds: completedEventIds,
                            colorForPerson: controller.colorForPerson,
                            onSelectEvent: onSelectEvent,
                            onToggleChecked: onToggleChecked,
                            onStartQuiz: onStartQuiz,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: mapHeightOnNarrow, child: mapPanel),
                        SizedBox(height: contentGap),
                        Expanded(
                          child: _buildWeeklyListPanel(
                            weekly: weekly,
                            completedEventIds: completedEventIds,
                            colorForPerson: controller.colorForPerson,
                            onSelectEvent: onSelectEvent,
                            onToggleChecked: onToggleChecked,
                            onStartQuiz: onStartQuiz,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _weeklyGuestNoticeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E5BE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xD7D3A051), width: 1),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8B632E)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '비로그인 상태예요. 금주 인물과 퀴즈는 사용할 수 있지만 진행 상황은 저장되지 않아요.',
              style: TextStyle(
                color: Color(0xFF6A4A23),
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyProgressRow({
    required int daysRemainingKst,
    required int completedCount,
    required int totalCount,
    required double progress,
  }) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentText = '${(clampedProgress * 100).round()}%';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;
        final summaryStyle = TextStyle(
          color: const Color(0xFFFDF8EE),
          fontSize: compact ? 12.6 : 14.2,
          fontWeight: FontWeight.w800,
          height: compact ? 1.25 : 1.1,
          shadows: const [
            Shadow(
              color: Color(0xAA000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        );
        final percentStyle = TextStyle(
          color: const Color(0xFFFFE5A8),
          fontSize: compact ? 12.8 : 14.2,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(
              color: Color(0xAA000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        );
        final progressBar = ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: compact ? 10 : 12,
            value: clampedProgress,
            backgroundColor: const Color(0x664E3A26),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC6922D)),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xAA2A2118),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x99DDB883), width: 1),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 8 : 10,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '이번주 남은 $daysRemainingKst일 · 이야기 $completedCount/$totalCount 달성',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: summaryStyle,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: progressBar),
                          const SizedBox(width: 8),
                          Text(percentText, maxLines: 1, style: percentStyle),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 9,
                        child: Text(
                          '이번주 남은 $daysRemainingKst일 · 이야기 $completedCount/$totalCount 달성',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: summaryStyle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 7, child: progressBar),
                      const SizedBox(width: 8),
                      Text(percentText, maxLines: 1, style: percentStyle),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyListPanel({
    required WeeklyStudyData weekly,
    required Set<String> completedEventIds,
    required Color Function(String personId) colorForPerson,
    required ValueChanged<String> onSelectEvent,
    required ValueChanged<String> onToggleChecked,
    required ValueChanged<String> onStartQuiz,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: floatingPanelDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _weeklyPersonTitleBadge(
              text: '금주 인물: ${weekly.person.name}',
              person: weekly.person,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: weekly.events.isEmpty
                  ? const Center(
                      child: Text(
                        '선택된 인물의 사건이 없습니다.',
                        style: TextStyle(
                          color: Color(0xFF5A4327),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: weekly.events.length,
                      itemBuilder: (context, index) {
                        final event = weekly.events[index];
                        final selected = event.id == _weeklySelectedEventId;
                        final isCompleted = completedEventIds.contains(
                          event.id,
                        );
                        final isChecked = _weeklyCheckedEventIds.contains(
                          event.id,
                        );
                        final shortText =
                            (event.shortStory ??
                                    event.story ??
                                    event.summary ??
                                    '')
                                .trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            onTap: () => onSelectEvent(event.id),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              decoration: interactiveCardDecoration(
                                selected: selected,
                                completed: isCompleted,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isCompactCard =
                                      constraints.maxWidth < 340;
                                  final titleFontSize = isCompactCard
                                      ? 13.2
                                      : 14.8;
                                  final bodyFontSize = isCompactCard
                                      ? 11.2
                                      : 12.2;
                                  final checkboxSize = isCompactCard
                                      ? 26.0
                                      : 29.0;
                                  final checkboxIconSize = isCompactCard
                                      ? 15.0
                                      : 17.0;
                                  return Container(
                                    constraints: BoxConstraints(
                                      minHeight: isCompactCard ? 64 : 74,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompactCard ? 10 : 12,
                                      vertical: isCompactCard ? 9 : 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: isCompactCard ? 11 : 12,
                                          height: isCompactCard ? 11 : 12,
                                          margin: EdgeInsets.only(
                                            right: isCompactCard ? 8 : 10,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: colorForPerson(
                                              weekly.person.id,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${index + 1}. ${event.title}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: titleFontSize,
                                                  fontWeight: FontWeight.w800,
                                                  color: selected
                                                      ? const Color(0xFFFDF8EE)
                                                      : isCompleted
                                                      ? const Color(0xFF2D5A39)
                                                      : const Color(0xFF4A331D),
                                                  height: 1.18,
                                                ),
                                              ),
                                              if (shortText.isNotEmpty) ...[
                                                SizedBox(
                                                  height: isCompactCard ? 3 : 4,
                                                ),
                                                Text(
                                                  shortText,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: bodyFontSize,
                                                    fontWeight: FontWeight.w600,
                                                    color: selected
                                                        ? const Color(
                                                            0xEAFDF8EE,
                                                          )
                                                        : isCompleted
                                                        ? const Color(
                                                            0xCC44624B,
                                                          )
                                                        : const Color(
                                                            0xCC5A4327,
                                                          ),
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: isCompactCard ? 6 : 8),
                                        GestureDetector(
                                          onTap: () =>
                                              onToggleChecked(event.id),
                                          behavior: HitTestBehavior.opaque,
                                          child: Container(
                                            width: checkboxSize,
                                            height: checkboxSize,
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? const Color(0xFF2D7C55)
                                                  : const Color(0xFFF8F1E4),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isChecked
                                                    ? const Color(0xFF2D7C55)
                                                    : const Color(0xFFB58E63),
                                              ),
                                            ),
                                            child: Icon(
                                              isChecked
                                                  ? Icons.check_rounded
                                                  : Icons.circle_outlined,
                                              size: checkboxIconSize,
                                              color: isChecked
                                                  ? const Color(0xFFFDF8EE)
                                                  : const Color(0xFF8E6F48),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _weeklyInlineQuizButton(
                                          completed: isCompleted,
                                          onTap: () => onStartQuiz(event.id),
                                          roomy: !isCompactCard,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weeklyInlineQuizButton({
    required bool completed,
    required VoidCallback onTap,
    bool roomy = false,
  }) {
    return filledActionButton(
      label: '퀴즈',
      onTap: onTap,
      completed: completed,
      compact: true,
      minWidth: roomy ? 60 : 52,
      minHeight: roomy ? 40 : 36,
      fontSize: roomy ? 13.8 : 12.8,
      horizontalPadding: roomy ? 14 : 12,
    );
  }

  Widget _weeklyPersonTitleBadge({
    required String text,
    required Person person,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: headerChipDecoration(),
      child: Row(
        children: [
          _weeklyPersonAvatar(person: person, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.2,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A331D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyPersonAvatar({required Person person, double size = 32}) {
    final avatarPath = person.avatarAssetPath.trim();
    final fallbackText = person.name.trim().isEmpty
        ? '?'
        : person.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF3E7CC), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _weeklyAvatarFallback(fallbackText, fontSize: fallbackFontSize)
            : ColoredBox(
                color: Colors.white,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size,
                    height: size * 2,
                    child: Image.asset(
                      avatarPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => _weeklyAvatarFallback(
                        fallbackText,
                        fontSize: fallbackFontSize,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _weeklyAvatarFallback(String text, {double fontSize = 11}) {
    return Container(
      color: const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFFF3EAD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _weeklyShortPopup({
    required StoryEvent event,
    double maxHeight = 232,
    required VoidCallback onClose,
    required VoidCallback onOpenDetail,
  }) {
    final shortText = (event.shortStory ?? event.story ?? event.summary ?? '')
        .trim();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: floatingPanelDecoration(
          color: const Color(0xFFF9F1E4),
          shadowOpacity: 0.28,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 48, 14),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3D2D18),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (shortText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        shortText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4C3A21),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onOpenDetail,
                        behavior: HitTestBehavior.translucent,
                        child: filledActionButton(
                          label: '자세히 보기',
                          onTap: onOpenDetail,
                          compact: true,
                          minWidth: 96,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 8,
              child: modalCloseButton(size: 24, onTap: onClose),
            ),
          ],
        ),
      ),
    );
  }
}
