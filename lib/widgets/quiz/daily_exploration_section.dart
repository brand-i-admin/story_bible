import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/era.dart';
import '../../models/landmark.dart';
import '../../models/story_event.dart';
import '../../state/auth_providers.dart';
import '../../state/story_controller.dart';
import '../../state/story_state.dart';
import '../../theme/tokens.dart';
import '../../utils/daily_exploration_prompt.dart';
import '../../utils/daily_exploration_selection.dart';
import '../character_avatar.dart';
import '../event_timeline_row.dart';
import '../story_map_panel.dart';

class DailyExplorationSection extends ConsumerStatefulWidget {
  const DailyExplorationSection({
    super.key,
    required this.onOpenEventDetail,
    this.onCompletedChanged,
  });

  final ValueChanged<StoryEvent> onOpenEventDetail;
  final ValueChanged<bool>? onCompletedChanged;

  @override
  ConsumerState<DailyExplorationSection> createState() =>
      _DailyExplorationSectionState();
}

class _DailyExplorationSectionState
    extends ConsumerState<DailyExplorationSection> {
  Future<_DailyExplorationData>? _future;
  String? _selectedEventId;
  String? _reportedEventId;
  bool? _reportedCompleted;
  _DailyExplorationViewMode _viewMode = _DailyExplorationViewMode.todayEvent;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DailyExplorationData> _load() async {
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
          era: era,
          characters: responses[0] as List<Character>,
          events: responses[1] as List<StoryEvent>,
        );
      }),
    );

    final eras = <Era>[];
    final events = <StoryEvent>[];
    final characterByCode = <String, Character>{};
    for (final bundle in eraBundles) {
      eras.add(bundle.era);
      events.addAll(bundle.events);
      for (final character in bundle.characters) {
        characterByCode.putIfAbsent(character.code, () => character);
      }
    }

    final dayKey = dailyExplorationKeyForKst(DateTime.now());
    final event = pickDailyExplorationEvent(events: events, dayKey: dayKey);
    if (event == null) {
      throw StateError('오늘의 탐험 사건을 찾지 못했습니다.');
    }

    final era = eras.where((candidate) => candidate.id == event.eraId).first;
    final character = _pickCharacter(event, characterByCode);
    final latestState = ref.read(storyControllerProvider);
    final eraEvents = _sortedEvents(
      events.where((candidate) => candidate.eraId == event.eraId),
    );
    final region = _regionForEvent(event, latestState.landmarks);
    return _DailyExplorationData(
      dayKey: dayKey,
      era: era,
      event: event,
      character: character,
      allEras: eras,
      charactersByCode: characterByCode,
      region: region,
      locationName: _locationNameFor(event, latestState.landmarks),
      characterRouteEvents: _characterRouteEvents(
        event: event,
        character: character,
        eraEvents: eraEvents,
      ),
      placeEvents: _placeEventsForEvent(
        event: event,
        region: region,
        eraEvents: eraEvents,
        landmarks: latestState.landmarks,
      ),
    );
  }

  Character? _pickCharacter(
    StoryEvent event,
    Map<String, Character> characterByCode,
  ) {
    for (final code in event.characterCodes) {
      if (code == 'god') continue;
      final character = characterByCode[code];
      if (character != null) return character;
    }
    for (final code in event.characterCodes) {
      final character = characterByCode[code];
      if (character != null) return character;
    }
    return null;
  }

  Landmark? _regionForEvent(StoryEvent event, List<Landmark> landmarks) {
    final landmarkById = {
      for (final landmark in landmarks) landmark.id: landmark,
    };
    final landmark = landmarkById[event.landmarkId];
    if (landmark == null) return null;
    if (landmark.kind == 'region') return landmark;
    final parentId = landmark.parentLandmarkId;
    return parentId == null ? null : landmarkById[parentId];
  }

  String _locationNameFor(StoryEvent event, List<Landmark> landmarks) {
    final placeName = event.placeName?.trim();
    if (placeName != null && placeName.isNotEmpty) return placeName;
    for (final landmark in landmarks) {
      if (landmark.id == event.landmarkId) return landmark.name;
    }
    return '성경의 한 장소';
  }

  List<StoryEvent> _characterRouteEvents({
    required StoryEvent event,
    required Character? character,
    required List<StoryEvent> eraEvents,
  }) {
    if (character == null) return [event];
    return _withEventFallback(
      eraEvents.where(
        (candidate) => candidate.characterCodes.contains(character.code),
      ),
      event,
    );
  }

  List<StoryEvent> _placeEventsForEvent({
    required StoryEvent event,
    required Landmark? region,
    required List<StoryEvent> eraEvents,
    required List<Landmark> landmarks,
  }) {
    final selectedPlaceName = event.placeName?.trim();
    return _withEventFallback(
      eraEvents.where((candidate) {
        if (region != null) {
          return _regionForEvent(candidate, landmarks)?.id == region.id;
        }
        if (candidate.landmarkId == event.landmarkId) return true;
        final candidatePlaceName = candidate.placeName?.trim();
        return selectedPlaceName != null &&
            selectedPlaceName.isNotEmpty &&
            candidatePlaceName == selectedPlaceName;
      }),
      event,
    );
  }

  List<StoryEvent> _withEventFallback(
    Iterable<StoryEvent> events,
    StoryEvent event,
  ) {
    final sorted = _sortedEvents(events);
    if (!sorted.any((candidate) => candidate.id == event.id)) {
      sorted.add(event);
      sorted.sort(_compareEvents);
    }
    return sorted.isEmpty ? [event] : sorted;
  }

  List<StoryEvent> _sortedEvents(Iterable<StoryEvent> events) {
    return events.toList()..sort(_compareEvents);
  }

  int _compareEvents(StoryEvent a, StoryEvent b) {
    final rank = a.globalRank.compareTo(b.globalRank);
    if (rank != 0) return rank;
    return a.id.compareTo(b.id);
  }

  void _reportCompletion(String eventId, bool completed) {
    if (_reportedEventId == eventId && _reportedCompleted == completed) {
      return;
    }
    _reportedEventId = eventId;
    _reportedCompleted = completed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCompletedChanged?.call(completed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final signedIn = ref.watch(signedInUserProvider) != null;

    return FutureBuilder<_DailyExplorationData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorBox('매일 탐험을 불러오지 못했습니다.\n${snapshot.error}');
        }
        final data = snapshot.data;
        if (data == null) {
          return _errorBox('오늘의 탐험 사건이 아직 없습니다.');
        }
        _selectedEventId ??= data.event.id;
        final exploredEventIds = _exploredEventIds(state);
        _reportCompletion(
          data.event.id,
          exploredEventIds.contains(data.event.id),
        );
        return _buildBody(
          data: data,
          state: state,
          controller: controller,
          signedIn: signedIn,
          exploredEventIds: exploredEventIds,
        );
      },
    );
  }

  Set<String> _exploredEventIds(StoryState state) => {
    ...state.completedEventIds,
    ...state.quizCompletedEventIds,
    ...state.eventEmotionMarks.keys,
  };

  Widget _buildBody({
    required _DailyExplorationData data,
    required StoryState state,
    required StoryController controller,
    required bool signedIn,
    required Set<String> exploredEventIds,
  }) {
    final quizReviewEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.needsReview)
        .map((attempt) => attempt.eventId)
        .toSet();
    final quizConfusedEventIds = state.quizAttemptSummaries.values
        .where((attempt) => attempt.confusedCount > 0)
        .map((attempt) => attempt.eventId)
        .toSet();
    final viewMode = _availableViewMode(data, _viewMode);
    final viewEvents = _eventsForView(data, viewMode);
    final selectedId = viewEvents.any((event) => event.id == _selectedEventId)
        ? _selectedEventId
        : data.event.id;
    final center =
        viewMode == _DailyExplorationViewMode.todayEvent &&
            data.event.hasCoordinate
        ? data.event.latLng
        : null;
    final cardNote = viewMode == _DailyExplorationViewMode.todayEvent
        ? dailyExplorationCardNoteFor(
            mark: state.eventEmotionMarks[data.event.id],
            now: DateTime.now(),
          )
        : null;
    final selectedCharacterCodes =
        viewMode == _DailyExplorationViewMode.characterRoute &&
            data.character != null
        ? {data.character!.code}
        : const <String>{};
    final regionLandmarks =
        viewMode == _DailyExplorationViewMode.characterRoute ||
            data.region == null
        ? const <Landmark>[]
        : [data.region!];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxWidth * 0.011).clamp(8.0, 14.0).toDouble();
        final timelineHeight = eventTimelineRowHeightFor(context, base: 264);
        final mapHeight = (constraints.maxHeight * 0.34)
            .clamp(230.0, 360.0)
            .toDouble();
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.35).toDouble();
        final promptHeight = (cardNote == null ? 0.0 : 56.0) * textScale;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DailyExplorationIntro(data: data),
            if (!signedIn) ...[SizedBox(height: gap), _guestNoticeBanner()],
            SizedBox(height: gap),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0x66FFF6E2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x99B89A66),
                    width: 0.9,
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DailyExplorationViewSwitch(
                        data: data,
                        selectedMode: viewMode,
                        onChanged: (mode) {
                          final nextMode = _availableViewMode(data, mode);
                          final nextEvents = _eventsForView(data, nextMode);
                          setState(() {
                            _viewMode = nextMode;
                            _selectedEventId =
                                nextMode == _DailyExplorationViewMode.todayEvent
                                ? data.event.id
                                : nextEvents.any(
                                    (event) => event.id == data.event.id,
                                  )
                                ? data.event.id
                                : nextEvents.first.id;
                          });
                        },
                      ),
                      SizedBox(height: gap),
                      SizedBox(
                        height: mapHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: StoryMapPanel(
                            events: viewEvents,
                            selectedEventId: selectedId,
                            onSelectEvent: (eventId) {
                              setState(() => _selectedEventId = eventId);
                            },
                            colorForCharacter: controller.colorForCharacter,
                            selectedCharacterCodes: selectedCharacterCodes,
                            showCharacterLegend: false,
                            eraRegionLandmarks: regionLandmarks,
                            revealEventsKey:
                                'daily:${data.dayKey}:${viewMode.name}:${viewEvents.length}:${viewEvents.first.id}:${viewEvents.last.id}',
                            revealInstantly: true,
                            decorate: false,
                            showSelectedCallout: false,
                            animateReveal: false,
                            centerSelectedOnReady: false,
                            fitAllEventsOnReady: true,
                            fitAllZoomAdjust:
                                viewMode == _DailyExplorationViewMode.todayEvent
                                ? -0.28
                                : -0.18,
                            initialCenter: center,
                            initialZoom: center == null ? 5.0 : 6.6,
                          ),
                        ),
                      ),
                      SizedBox(height: gap),
                      Container(
                        height: timelineHeight + promptHeight,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0x55B89A66), width: 1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DailyExplorationEventPrompt(note: cardNote),
                            Expanded(
                              child: EventTimelineRow(
                                events: viewEvents,
                                allEras: data.allEras,
                                charactersByCode: data.charactersByCode,
                                selectedEventId: selectedId,
                                completedEventIds: exploredEventIds,
                                eventEmotionMarks: state.eventEmotionMarks,
                                quizAttemptSummaries:
                                    state.quizAttemptSummaries,
                                quizReviewEventIds: quizReviewEventIds,
                                quizConfusedEventIds: quizConfusedEventIds,
                                highlightedCharacterCodes:
                                    selectedCharacterCodes,
                                colorForHighlightedCharacter:
                                    controller.colorForCharacter,
                                onTapEvent: widget.onOpenEventDetail,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  _DailyExplorationViewMode _availableViewMode(
    _DailyExplorationData data,
    _DailyExplorationViewMode mode,
  ) {
    return _isViewModeEnabled(data, mode)
        ? mode
        : _DailyExplorationViewMode.todayEvent;
  }

  bool _isViewModeEnabled(
    _DailyExplorationData data,
    _DailyExplorationViewMode mode,
  ) {
    switch (mode) {
      case _DailyExplorationViewMode.todayEvent:
        return true;
      case _DailyExplorationViewMode.characterRoute:
        return data.character != null && data.characterRouteEvents.isNotEmpty;
      case _DailyExplorationViewMode.placeStories:
        return data.placeEvents.isNotEmpty;
    }
  }

  List<StoryEvent> _eventsForView(
    _DailyExplorationData data,
    _DailyExplorationViewMode mode,
  ) {
    switch (mode) {
      case _DailyExplorationViewMode.todayEvent:
        return [data.event];
      case _DailyExplorationViewMode.characterRoute:
        return data.characterRouteEvents;
      case _DailyExplorationViewMode.placeStories:
        return data.placeEvents;
    }
  }

  Widget _guestNoticeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E5BE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xD7D3A051), width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8B632E)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '비로그인 상태예요. 오늘의 탐험은 볼 수 있지만 읽기와 퀴즈 진행 기록은 로그인 후 저장돼요.',
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

  Widget _errorBox(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x55F1E1C0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x66B89A66), width: 0.8),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6A4C2E),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _DailyExplorationIntro extends StatelessWidget {
  const _DailyExplorationIntro({required this.data});

  final _DailyExplorationData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0x66FFF6E2),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x88B89A66), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.navigation_rounded,
                color: AppColors.greenBtnBot,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                '오늘의 탐험',
                style: TextStyle(
                  color: AppColors.greenBtnBot,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            spacing: 6,
            children: [
              const _DailyIntroText('오늘은'),
              _DailyIntroChip(
                leading: Text(
                  _eraEmojiFor(data.era.code),
                  style: const TextStyle(fontSize: 13.5, height: 1),
                ),
                label: '${_shortEraLabel(data.era)} 시대',
              ),
              _DailyCharacterChip(character: data.character),
              const _DailyIntroText('과 함께'),
              _DailyIntroChip(
                leading: const Text(
                  '📍',
                  style: TextStyle(fontSize: 13.5, height: 1),
                ),
                label: data.locationName,
              ),
              const _DailyIntroText('에 도착했어요.'),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DailyExplorationViewMode { todayEvent, characterRoute, placeStories }

class _DailyExplorationViewSwitch extends StatelessWidget {
  const _DailyExplorationViewSwitch({
    required this.data,
    required this.selectedMode,
    required this.onChanged,
  });

  final _DailyExplorationData data;
  final _DailyExplorationViewMode selectedMode;
  final ValueChanged<_DailyExplorationViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Text('🧭', style: TextStyle(fontSize: 15.5, height: 1)),
            SizedBox(width: 7),
            Text(
              '오늘의 사건',
              style: TextStyle(
                color: AppColors.greenBtnBot,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DailyExplorationPrimaryAction(
          selected: selectedMode == _DailyExplorationViewMode.todayEvent,
          title: '「${data.event.title}」 사건',
          onTap: () => onChanged(_DailyExplorationViewMode.todayEvent),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 58,
              child: Text(
                '함께 보기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.ink300,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DailyExplorationSideButton(
                icon: Icons.alt_route_rounded,
                title: '인물 루트',
                count: data.character == null
                    ? null
                    : data.characterRouteEvents.length,
                selected:
                    selectedMode == _DailyExplorationViewMode.characterRoute,
                enabled: data.character != null,
                onTap: () =>
                    onChanged(_DailyExplorationViewMode.characterRoute),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DailyExplorationSideButton(
                icon: Icons.place_rounded,
                title: '장소 사건',
                count: data.placeEvents.length,
                selected:
                    selectedMode == _DailyExplorationViewMode.placeStories,
                enabled: data.placeEvents.isNotEmpty,
                onTap: () => onChanged(_DailyExplorationViewMode.placeStories),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyExplorationPrimaryAction extends StatelessWidget {
  const _DailyExplorationPrimaryAction({
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '오늘 선정된 사건 보기',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.greenBtnBot : const Color(0xFFFFF6E2),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? AppColors.greenBorder
                    : const Color(0xCCB89A66),
                width: selected ? 1.2 : 0.9,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? AppColors.fgOnDark : AppColors.ink500,
                      fontSize: 14.2,
                      fontWeight: FontWeight.w900,
                      height: 1.28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyExplorationSideButton extends StatelessWidget {
  const _DailyExplorationSideButton({
    required this.icon,
    required this.title,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int? count;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.greenBtnBot
        : enabled
        ? AppColors.ink450
        : AppColors.ink300.withValues(alpha: 0.62);
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.35).toDouble();
    final countText = count == null ? '준비중' : '${count!}개';
    return Tooltip(
      message: enabled ? '$title 보기' : '$title에 표시할 인물이 아직 없어요',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            height: 38 + ((textScale - 1) * 16),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.greenTint1.withValues(alpha: 0.9)
                  : const Color(0x80FFF6E2),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? AppColors.greenBorder.withValues(alpha: 0.92)
                    : const Color(0x99B89A66),
                width: selected ? 1.2 : 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.1,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  flex: 0,
                  child: Text(
                    countText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.78),
                      fontSize: 10.9,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyExplorationEventPrompt extends StatelessWidget {
  const _DailyExplorationEventPrompt({required this.note});

  final DailyExplorationCardNote? note;

  @override
  Widget build(BuildContext context) {
    if (note == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 2),
      child: _DailyExplorationCardNoteBanner(note: note!),
    );
  }
}

class _DailyExplorationCardNoteBanner extends StatelessWidget {
  const _DailyExplorationCardNoteBanner({required this.note});

  final DailyExplorationCardNote note;

  @override
  Widget build(BuildContext context) {
    final isBlessing = note.kind == DailyExplorationCardNoteKind.blessing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isBlessing
            ? AppColors.greenTint1.withValues(alpha: 0.92)
            : const Color(0xB8FFF6E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isBlessing
              ? AppColors.greenBorder.withValues(alpha: 0.78)
              : const Color(0x88B89A66),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isBlessing ? Icons.check_circle_rounded : Icons.refresh_rounded,
            size: 16,
            color: isBlessing ? AppColors.greenBtnBot : AppColors.goldDeep,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              note.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink450,
                fontSize: 12.4,
                fontWeight: FontWeight.w800,
                height: 1.34,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyIntroText extends StatelessWidget {
  const _DailyIntroText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.ink500,
        fontSize: 14.1,
        fontWeight: FontWeight.w800,
        height: 1.45,
      ),
    );
  }
}

class _DailyIntroChip extends StatelessWidget {
  const _DailyIntroChip({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.58;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(148.0, 240.0)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink450,
                fontSize: 13.0,
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

class _DailyCharacterChip extends StatelessWidget {
  const _DailyCharacterChip({required this.character});

  final Character? character;

  @override
  Widget build(BuildContext context) {
    final fallback = character == null;
    return _DailyIntroChip(
      leading: fallback
          ? Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brownWarm2,
              ),
              child: const Icon(
                Icons.groups_rounded,
                size: 12,
                color: AppColors.fgOnDark,
              ),
            )
          : CharacterAvatar(character: character!, size: 18),
      label: fallback ? '성경 인물들' : character!.name,
    );
  }
}

class _DailyExplorationData {
  const _DailyExplorationData({
    required this.dayKey,
    required this.era,
    required this.event,
    required this.character,
    required this.allEras,
    required this.charactersByCode,
    required this.region,
    required this.locationName,
    required this.characterRouteEvents,
    required this.placeEvents,
  });

  final String dayKey;
  final Era era;
  final StoryEvent event;
  final Character? character;
  final List<Era> allEras;
  final Map<String, Character> charactersByCode;
  final Landmark? region;
  final String locationName;
  final List<StoryEvent> characterRouteEvents;
  final List<StoryEvent> placeEvents;
}

String _shortEraLabel(Era era) {
  switch (era.code) {
    case 'era_patriarch':
      return '족장';
    case 'era_exodus':
      return '출애굽';
    case 'era_judges':
      return '사사';
    case 'era_monarchy':
      return '통일 왕국';
    case 'era_divided_kingdom':
      return '분열왕국';
    case 'era_exile_return':
      return '포로 및 포로 후기';
    case 'era_nt_apostolic':
      return '사도';
    case 'era_nt_post_apostolic':
      return '후기 사도';
  }

  return era.name
      .replaceFirst(RegExp(r'의 시대$'), '')
      .replaceFirst(RegExp(r' 시대$'), '');
}

String _eraEmojiFor(String code) {
  switch (code) {
    case 'era_primeval':
      return '🌍';
    case 'era_patriarch':
      return '⛺';
    case 'era_exodus':
      return '🌊';
    case 'era_judges':
      return '🛡️';
    case 'era_monarchy':
      return '👑';
    case 'era_divided_kingdom':
      return '🧭';
    case 'era_exile_return':
      return '🏛️';
    case 'era_nt_public_ministry':
      return '✨';
    case 'era_nt_apostolic':
      return '⛵';
    case 'era_nt_post_apostolic':
      return '📜';
    case 'era_nt_consummation':
      return '🔥';
    default:
      return '🗺️';
  }
}
