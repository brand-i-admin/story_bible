import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/character.dart';
import '../models/era.dart';
import '../models/landmark.dart';
import '../models/story_event.dart';
import '../models/weekly_study_data.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import '../utils/region_membership.dart';
import '../utils/weekly_selection.dart';
import 'event_timeline_row.dart';
import 'story_home_styles.dart';
import 'story_map_panel.dart';
import 'sub_page_scaffold.dart';

// 주간 화면 빌더 메소드를 도메인별 part 파일로 분리.
part 'weekly/weekly_avatar.dart';

/// 주간 탐험 탭 페이지.
///
/// 1. 랜덤 또는 지정된 인물의 그 주 이야기 목록 표시
/// 2. 지도에 관련 사건 핀 표시
/// 3. 사건 카드 탭 시 기존 사건 상세의 읽기/퀴즈/감정 새김 흐름으로 진행
/// 4. 사건 선택 시 상세 팝업
///
/// 외부 콜백:
/// - [onOpenEventDetail]: 사건 상세 페이지 열기
class WeeklyTabPage extends ConsumerStatefulWidget {
  const WeeklyTabPage({
    super.key,
    required this.onOpenEventDetail,
    this.embedded = false,
  });

  final ValueChanged<StoryEvent> onOpenEventDetail;

  /// `true` 면 SubPageScaffold 를 생략하고 본문만 반환 — QuizTabPage 같은 부모
  /// scaffold 안에 그대로 넣을 수 있게 한다.
  final bool embedded;

  @override
  ConsumerState<WeeklyTabPage> createState() => _WeeklyTabPageState();
}

class _WeeklyTabPageState extends ConsumerState<WeeklyTabPage> {
  static const Map<String, String> _forcedWeeklyCharacterCodeByWeekKey = {
    // Monday, February 23, 2026 week
    '2026-2-23': 'abraham',
  };

  WeeklyStudyData? _weeklyStudyData;
  String? _weeklySelectedEventId;
  bool _weeklyLoading = true;
  String? _weeklyError;

  @override
  void initState() {
    super.initState();
    _loadWeeklyData();
  }

  /// region 모드 시드 기반 후보 선택. 사건 보유 region 이 있는 era 풀에서
  /// 시드 모듈로 era 1개 → 그 era 의 사건 보유 region 1개를 결정적으로 선택.
  /// 후보가 비어 있으면 null 반환 → 호출자가 character 모드로 fallback.
  ({Era era, Landmark region, List<StoryEvent> events})? _pickWeeklyRegion({
    required int seed,
    required StoryState state,
  }) {
    if (state.eras.isEmpty || state.landmarks.isEmpty || state.events.isEmpty) {
      return null;
    }
    final landmarkById = {for (final l in state.landmarks) l.id: l};
    // era 별로 사건 보유 region 모음. 사건 → landmark.parentLandmarkId 또는
    // landmark 자체(kind=region) 로 region 추적.
    final regionsWithEventsByEra = <String, Map<String, List<StoryEvent>>>{};
    for (final ev in state.events) {
      final lm = landmarkById[ev.landmarkId];
      if (lm == null) continue;
      Landmark? region;
      if (lm.kind == 'region' && lm.polygon.length >= 3) {
        region = lm;
      } else if (lm.parentLandmarkId != null) {
        final parent = landmarkById[lm.parentLandmarkId];
        if (parent != null &&
            parent.kind == 'region' &&
            parent.polygon.length >= 3) {
          region = parent;
        }
      }
      // Fallback: point-in-polygon over all regions.
      if (region == null && ev.lat != null && ev.lng != null) {
        final p = LatLng(ev.lat!, ev.lng!);
        for (final r in state.landmarks) {
          if (r.kind == 'region' &&
              r.polygon.length >= 3 &&
              isPointInPolygon(p, r.polygon)) {
            region = r;
            break;
          }
        }
      }
      if (region == null) continue;

      final byRegion = regionsWithEventsByEra.putIfAbsent(
        ev.eraId,
        () => <String, List<StoryEvent>>{},
      );
      byRegion.putIfAbsent(region.id, () => <StoryEvent>[]).add(ev);
    }

    final eraIds = regionsWithEventsByEra.keys.toList()..sort();
    if (eraIds.isEmpty) return null;
    final eraId = eraIds[seed % eraIds.length];
    final era = state.eras.where((e) => e.id == eraId).firstOrNull;
    if (era == null) return null;

    final regionMap = regionsWithEventsByEra[eraId]!;
    final regionIds = regionMap.keys.toList()..sort();
    if (regionIds.isEmpty) return null;
    // 시드를 era 선택 후 한 번 더 변형해 region 인덱스 분산.
    final regionId =
        regionIds[(seed ~/ math.max(1, eraIds.length)) % regionIds.length];
    final region = landmarkById[regionId];
    if (region == null) return null;

    final events = [...regionMap[regionId]!]
      ..sort((a, b) {
        final cmp = a.globalRank.compareTo(b.globalRank);
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });
    return (era: era, region: region, events: events);
  }

  // 순수 함수는 lib/utils/weekly_selection.dart로 추출:
  // - weekStartMonday, weeklyKeyFor, seedFromKey

  Future<void> _loadWeeklyData() async {
    final monday = weekStartMonday(DateTime.now());
    final weekKey = weeklyKeyFor(monday);
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
            repo.fetchCharactersByEra(era.id),
            repo.fetchEventsByEra(era.id),
          ]);
          return (
            characters: responses[0] as List<Character>,
            events: responses[1] as List<StoryEvent>,
          );
        }),
      );

      final characterByCode = <String, Character>{};
      final eventsByCharacterCode = <String, List<StoryEvent>>{};
      for (final bundle in eraBundles) {
        for (final character in bundle.characters) {
          characterByCode.putIfAbsent(character.code, () => character);
        }
        for (final event in bundle.events) {
          for (final code in event.characterCodes) {
            eventsByCharacterCode
                .putIfAbsent(code, () => <StoryEvent>[])
                .add(event);
          }
        }
      }

      final candidates =
          characterByCode.values
              .where(
                (character) =>
                    (eventsByCharacterCode[character.code] ??
                            const <StoryEvent>[])
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

      final seed = seedFromKey(weekKey);
      final forcedCode = _forcedWeeklyCharacterCodeByWeekKey[weekKey];
      // forced 인물이 있으면 character 모드 강제, 아니면 시드 기반 모드 결정.
      final mode = forcedCode != null
          ? WeeklyMode.character
          : weeklyModeForSeed(seed);

      final pick = mode == WeeklyMode.region
          ? _pickWeeklyRegion(seed: seed, state: state)
          : null;

      final WeeklyStudyData weeklyData;
      if (pick != null) {
        weeklyData = WeeklyStudyData.region(
          era: pick.era,
          region: pick.region,
          events: pick.events,
          weekStartMonday: monday,
        );
      } else {
        // character 모드 (또는 region fallback).
        final forcedCharacter = forcedCode == null
            ? null
            : candidates
                  .where((character) => character.code == forcedCode)
                  .firstOrNull;
        final weeklyCharacter =
            forcedCharacter ?? candidates[seed % candidates.length];
        final weeklyEvents =
            [
              ...(eventsByCharacterCode[weeklyCharacter.code] ??
                  const <StoryEvent>[]),
            ]..sort((a, b) {
              final cmp = a.globalRank.compareTo(b.globalRank);
              if (cmp != 0) {
                return cmp;
              }
              return a.id.compareTo(b.id);
            });
        weeklyData = WeeklyStudyData.character(
          character: weeklyCharacter,
          events: weeklyEvents,
          weekStartMonday: monday,
        );
      }

      final selectedEventId = weeklyData.events.isNotEmpty
          ? weeklyData.events.first.id
          : null;

      if (!mounted) {
        return;
      }
      setState(() {
        _weeklyStudyData = weeklyData;
        _weeklySelectedEventId = selectedEventId;
        _weeklyLoading = false;
        _weeklyError = weeklyData.events.isEmpty
            ? (weeklyData.mode == WeeklyMode.region
                  ? '이번 주 지역의 사건이 아직 없습니다.'
                  : '추천 인물의 이야기가 아직 없습니다.')
            : null;
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

    // 핀 탭 = 카드 포커스 (popup 없음, 직접 상세는 카드 탭으로).
    void onSelectEvent(String eventId) {
      setState(() => _weeklySelectedEventId = eventId);
    }

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: _buildWeeklyBody(
        state: state,
        controller: controller,
        onSelectEvent: onSelectEvent,
      ),
    );

    if (widget.embedded) {
      return body;
    }
    return SubPageScaffold(title: '주간 탐험', compactBackOnly: true, child: body);
  }

  Widget _buildWeeklyBody({
    required StoryState state,
    required StoryController controller,
    required ValueChanged<String> onSelectEvent,
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
            style: const TextStyle(color: AppColors.parchmentCream),
          ),
        ),
      );
    }
    if (weekly == null) {
      return const SizedBox.shrink();
    }

    final exploredEventIds = {
      ...state.completedEventIds,
      ...state.quizCompletedEventIds,
      ...state.eventEmotionMarks.keys,
    };
    final totalStories = weekly.events.length;
    final completedStories = weekly.events
        .where((event) => exploredEventIds.contains(event.id))
        .length;
    final weeklyProgress = totalStories == 0
        ? 0.0
        : completedStories / totalStories;
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final todayKst = DateTime(nowKst.year, nowKst.month, nowKst.day);
    final weekStartKst = weekStartMonday(todayKst);
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
        final contentGap = (w * 0.011).clamp(8.0, 14.0).toDouble();
        // compact 모드에서 본문(요약 텍스트 + gap + bar)이 약 50px 필요 + 컨테이너
        // padding 16 = 66 minimum. 하한을 넉넉히.
        final progressHeight = (h * 0.10).clamp(66.0, 78.0).toDouble();

        final isRegionMode = weekly.mode == WeeklyMode.region;
        final mapPanel = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: StoryMapPanel(
            events: weekly.events,
            selectedEventId: _weeklySelectedEventId,
            onSelectEvent: onSelectEvent,
            colorForCharacter: controller.colorForCharacter,
            // selectedCharacterCodes 는 path polyline 색 결정용. 인물 모드면
            // 그 인물 코드 1개 전달 → 갈색 점선 + ▶ 화살촉이 그 인물 색.
            selectedCharacterCodes: weekly.character == null
                ? const <String>{}
                : {weekly.character!.code},
            showCharacterLegend: false,
            eventEmotionMarks: state.eventEmotionMarks,
            // region 모드면 그 region 폴리곤 한 개를 강조.
            eraRegionLandmarks: isRegionMode && weekly.region != null
                ? [weekly.region!]
                : const <Landmark>[],
            // 시간순 숫자 핀 + 점선 + 화살촉 모드 활성 — 홈 step3 와 동일.
            // revealEventsKey 가 set 되면 _orderedEventsActive=true → numbered
            // pin 빌더 사용. revealInstantly:true 라 0.3초 stagger 건너뛰고 즉시.
            revealEventsKey:
                'weekly:${weekly.mode.name}:${weekly.weekStartMonday.toIso8601String()}',
            revealInstantly: true,
            decorate: false,
            showSelectedCallout: false,
            animateReveal: false,
            centerSelectedOnReady: false,
            fitAllEventsOnReady: true,
            fitAllZoomAdjust: -0.18,
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
            // 헤더 — 모드별 타이틀.
            _weeklyHeaderBadge(weekly),
            SizedBox(height: contentGap),
            // 지도 — 홈과 같은 StoryMapPanel (decorate=false). 핀 = 시간순 숫자.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: mapPanel),
                  SizedBox(height: contentGap),
                  // 사건 카드 row — 홈과 같은 EventTimelineRow.
                  // 카드 탭 → 사건 상세, 핀 탭은 onSelectEvent 로 카드 포커스.
                  Container(
                    // 카드 자연 높이(~210) + 패딩 + ‘현재 이야기' 라벨 overflow
                    // 여유를 위해 250 이상 — 아주큰 글자에서는 조금 더 확보.
                    height: eventTimelineRowHeightFor(context, base: 250),
                    decoration: floatingPanelDecoration(),
                    child: EventTimelineRow(
                      events: weekly.events,
                      allEras: state.eras,
                      charactersByCode: {
                        for (final c in state.characters) c.code: c,
                      },
                      selectedEventId: _weeklySelectedEventId,
                      completedEventIds: exploredEventIds,
                      eventEmotionMarks: state.eventEmotionMarks,
                      quizAttemptSummaries: state.quizAttemptSummaries,
                      quizReviewEventIds: state.quizAttemptSummaries.values
                          .where((attempt) => attempt.needsReview)
                          .map((attempt) => attempt.eventId)
                          .toSet(),
                      quizConfusedEventIds: state.quizAttemptSummaries.values
                          .where((attempt) => attempt.confusedCount > 0)
                          .map((attempt) => attempt.eventId)
                          .toSet(),
                      onTapEvent: (event) {
                        widget.onOpenEventDetail(event);
                      },
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

  /// 모드별 헤더 — 인물 모드는 아바타 + "금주 인물: xxx", 지역 모드는 깃발
  /// 아이콘 + "금주 지역: 시대명 · 지역명".
  Widget _weeklyHeaderBadge(WeeklyStudyData weekly) {
    if (weekly.mode == WeeklyMode.character && weekly.character != null) {
      return _weeklyCharacterTitleBadge(
        text: '금주 인물: ${weekly.character!.name}',
        character: weekly.character!,
      );
    }
    if (weekly.mode == WeeklyMode.region &&
        weekly.era != null &&
        weekly.region != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: headerChipDecoration(),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB07220),
                border: Border.all(color: const Color(0xFFF3E7CC), width: 1.4),
              ),
              child: const Icon(
                Icons.flag_rounded,
                size: 18,
                color: Color(0xFFFFF6E2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '금주 지역: ${weekly.era!.name} · ${weekly.region!.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _weeklyCharacterTitleBadge({
    required String text,
    required Character character,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: headerChipDecoration(),
      child: Row(
        children: [
          _weeklyCharacterAvatar(character: character, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.2,
                fontWeight: FontWeight.w800,
                color: AppColors.ink500,
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
          color: AppColors.parchmentCream,
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
}
