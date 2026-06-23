import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/character_name_fallbacks.dart';
import '../models/bible_ref.dart';
import '../models/character.dart';
import '../models/event_emotion_mark.dart';
import '../models/quiz_attempt_summary.dart';
import '../models/story_event.dart';
import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';
import '../utils/scene_asset_loader.dart';
import 'character_avatar.dart';
import 'emotion_badge_icon.dart';
import 'parchment_dialog.dart';
import 'proposal/delete_event_proposal_sheet.dart';
import 'pulse_highlight.dart';
import 'story_home_styles.dart';
import 'sub_page_scaffold.dart';

/// 사건 상세 페이지.
///
/// 1. 제목
/// 2. 배경 지식
/// 3. 요약 + 4개 장면 이미지 (있으면)
/// 4. 관련 성경 본문 + 이동 버튼
/// 5. 퀴즈 시작 버튼
///
/// 완료 여부는 [storyControllerProvider]의 `completedEventIds`로 판정한다.
class EventDetailPage extends ConsumerStatefulWidget {
  const EventDetailPage({
    super.key,
    required this.event,
    required this.sceneAssetsFuture,
    required this.onOpenBibleReader,
    required this.onStartQuiz,
    this.prevEvent,
    this.nextEvent,
    this.onNavigateToEvent,
    this.onEmotionEngraved,
    this.onLoginRequired,
  });

  final StoryEvent event;
  final Future<List<String>> sceneAssetsFuture;

  /// 성경 리더를 열 때 호출되는 콜백. 읽어야 할 본문 범위들을 함께 전달한다.
  final Future<bool> Function(List<BibleNavigationTarget> targets)
  onOpenBibleReader;

  /// 퀴즈 시작 버튼을 누를 때 호출되는 콜백. (eventId)
  final void Function(String eventId) onStartQuiz;

  /// (선택) 좌측에 작고 연하게 표시될 이전 이야기. null 이면 표시 안 함.
  final StoryEvent? prevEvent;

  /// (선택) 우측에 작고 연하게 표시될 다음 이야기. null 이면 표시 안 함.
  final StoryEvent? nextEvent;

  /// prev/next 카드 클릭 또는 좌우 스와이프 시 호출. 호출 시 부모는 같은
  /// 페이지를 새 사건으로 pushReplacement 하는 식으로 처리한다.
  final void Function(StoryEvent target)? onNavigateToEvent;

  /// 감정 새김 저장이 끝난 직후 호출. 부모는 상세 페이지를 닫고 지도 카드 위
  /// 축하 효과를 재생한 뒤 같은 상세 페이지로 되돌아갈 수 있다.
  final Future<void> Function(StoryEvent event, EventEmotionOption option)?
  onEmotionEngraved;
  final void Function(String message)? onLoginRequired;

  @override
  ConsumerState<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends ConsumerState<EventDetailPage> {
  /// 다음 이야기 카드 glow 활성 여부.
  /// - 진입 시 이미 완료된 사건이면 즉시 true (post-frame 으로 setState).
  /// - 페이지 안에서 둘 다 완료해서 축하 애니메이션이 끝났을 때도 true.
  /// - 완료 취소되면 다시 false.
  bool _glowNext = false;
  String? _eventCharactersEraId;
  Future<List<Character>>? _eventCharactersFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(storyControllerProvider);
      final eventId = widget.event.id;
      final isCompleted = _isCompletedFor(state, eventId);
      if (isCompleted && widget.nextEvent != null) {
        setState(() => _glowNext = true);
      }
    });
  }

  bool _isCompletedFor(StoryState state, String eventId) {
    final engraved = state.eventEmotionMarks.containsKey(eventId);
    return state.bibleReadEventIds.contains(eventId) &&
        state.quizCompletedEventIds.contains(eventId) &&
        engraved;
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

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final storyText = (event.summary ?? '').trim();
    final backgroundText = event.backgroundText;
    final refs = event.bibleRefs;
    final readTargets = event.bibleRefs
        .map((ref) => parseBibleNavigationTarget(ref.displayText))
        .nonNulls
        .toList(growable: false);

    // 완료 전이(false → true) 감지. 페이지 진입 시 이미 완료라면 발화하지 않음.
    // 반대 전이(true → false, 완료 취소)에는 다음 이야기 glow 도 끔.
    ref.listen<StoryState>(storyControllerProvider, (previous, next) {
      if (previous == null) return;
      final wasCompleted = _isCompletedFor(previous, event.id);
      final isCompleted = _isCompletedFor(next, event.id);
      if (!wasCompleted && isCompleted) {
        if (widget.nextEvent != null && !_glowNext) {
          setState(() => _glowNext = true);
        }
      }
      if (!isCompleted && _glowNext) {
        setState(() => _glowNext = false);
      }
    });

    final currentState = ref.watch(storyControllerProvider);
    final isBibleRead = currentState.bibleReadEventIds.contains(event.id);
    final isQuizCompleted = currentState.quizCompletedEventIds.contains(
      event.id,
    );
    final lastScore = currentState.lastQuizScores[event.id];
    final attemptSummary = currentState.quizAttemptSummaries[event.id];
    final emotionMark = currentState.eventEmotionMarks[event.id];
    final isSaved = currentState.savedEventIds.contains(event.id);

    return _buildPage(
      event: event,
      storyText: storyText,
      backgroundText: backgroundText,
      refs: refs,
      readTargets: readTargets,
      currentCharacters: currentState.characters,
      isBibleRead: isBibleRead,
      isQuizCompleted: isQuizCompleted,
      lastScore: lastScore,
      attemptSummary: attemptSummary,
      emotionMark: emotionMark,
      isSaved: isSaved,
    );
  }

  Widget _buildPage({
    required StoryEvent event,
    required String storyText,
    required String backgroundText,
    required List<BibleRef> refs,
    required List<BibleNavigationTarget> readTargets,
    required List<Character> currentCharacters,
    required bool isBibleRead,
    required bool isQuizCompleted,
    required ({int correct, int total})? lastScore,
    required QuizAttemptSummary? attemptSummary,
    required EventEmotionMark? emotionMark,
    required bool isSaved,
  }) {
    return SubPageScaffold(
      title: event.title,
      compactBackOnly: true,
      child: GestureDetector(
        onHorizontalDragEnd: _handleHorizontalSwipe,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStoryCard(
                      event: event,
                      storyText: storyText,
                      backgroundText: backgroundText,
                      refs: refs,
                      readTargets: readTargets,
                      currentCharacters: currentCharacters,
                      isBibleRead: isBibleRead,
                      isQuizCompleted: isQuizCompleted,
                      lastScore: lastScore,
                      attemptSummary: attemptSummary,
                      emotionMark: emotionMark,
                      isSaved: isSaved,
                    ),
                    _buildNavigationRow(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -200 && widget.nextEvent != null) {
      widget.onNavigateToEvent?.call(widget.nextEvent!);
    } else if (v > 200 && widget.prevEvent != null) {
      widget.onNavigateToEvent?.call(widget.prevEvent!);
    }
  }

  Widget _buildStoryCard({
    required StoryEvent event,
    required String storyText,
    required String backgroundText,
    required List<BibleRef> refs,
    required List<BibleNavigationTarget> readTargets,
    required List<Character> currentCharacters,
    required bool isBibleRead,
    required bool isQuizCompleted,
    required ({int correct, int total})? lastScore,
    required QuizAttemptSummary? attemptSummary,
    required EventEmotionMark? emotionMark,
    required bool isSaved,
  }) {
    return DecoratedBox(
      decoration: modalSurfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF3B2A16), height: 1.55),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StoryHeader(
                event: event,
                isSaved: isSaved,
                onToggleSaved: () => _toggleSavedEvent(event),
              ),
              const SizedBox(height: 14),
              storySection(
                title: '배경 지식',
                content: backgroundText,
                action: _buildCharacterAvatarAction(event, currentCharacters),
              ),
              const SizedBox(height: 12),
              storySection(
                title: '요약: ',
                content: storyText.isNotEmpty ? storyText : '요약 정보가 없습니다.',
                footer: _buildSceneRow(),
                inlineTitle: true,
              ),
              const SizedBox(height: 12),
              _buildReadAndQuizProgress(
                event: event,
                refs: refs,
                readTargets: readTargets,
                isBibleRead: isBibleRead,
                isQuizCompleted: isQuizCompleted,
                lastScore: lastScore,
                attemptSummary: attemptSummary,
                emotionMark: emotionMark,
              ),
              _DeleteProposalButton(event: event),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Character>> _loadEventCharacters(String eraId) {
    if (_eventCharactersFuture == null || _eventCharactersEraId != eraId) {
      _eventCharactersEraId = eraId;
      _eventCharactersFuture = ref
          .read(storyRepositoryProvider)
          .fetchCharactersByEra(eraId);
    }
    return _eventCharactersFuture!;
  }

  Widget? _buildCharacterAvatarAction(
    StoryEvent event,
    List<Character> currentCharacters,
  ) {
    if (event.characterCodes.isEmpty) {
      return null;
    }

    final knownCharacters = _orderedCharactersForEvent(
      event,
      currentCharacters,
    );
    if (knownCharacters.length == event.characterCodes.length) {
      return _EventCharacterAvatarStack(characters: knownCharacters);
    }

    return FutureBuilder<List<Character>>(
      future: _loadEventCharacters(event.eraId),
      builder: (context, snapshot) {
        final source = snapshot.hasData ? snapshot.data! : currentCharacters;
        final characters = _orderedCharactersForEvent(
          event,
          source,
          includeFallbacks: true,
        );
        if (characters.isNotEmpty) {
          return _EventCharacterAvatarStack(characters: characters);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  List<Character> _orderedCharactersForEvent(
    StoryEvent event,
    List<Character> characters, {
    bool includeFallbacks = false,
  }) {
    if (event.characterCodes.isEmpty) {
      return const [];
    }
    final byCode = <String, Character>{
      for (final character in characters) character.code: character,
    };
    final orderedCharacters = [
      for (final code in event.characterCodes) ...[
        if (byCode[code] != null)
          _localizedCharacter(byCode[code]!)
        else if (includeFallbacks)
          _fallbackCharacterForCode(code),
      ],
    ];
    return orderedCharacters..sort(_compareEventCharacters);
  }

  int _compareEventCharacters(Character a, Character b) {
    final aIsGod = _isGodCharacter(a);
    final bIsGod = _isGodCharacter(b);
    if (aIsGod != bIsGod) {
      return aIsGod ? -1 : 1;
    }

    final nameCompare = a.name.compareTo(b.name);
    if (nameCompare != 0) {
      return nameCompare;
    }

    final displayOrderCompare = a.displayOrder.compareTo(b.displayOrder);
    if (displayOrderCompare != 0) {
      return displayOrderCompare;
    }
    return a.code.compareTo(b.code);
  }

  bool _isGodCharacter(Character character) {
    final code = character.code.trim().toLowerCase();
    final name = character.name.trim();
    return code == 'god' || name == '하나님';
  }

  Character _localizedCharacter(Character character) {
    final name = localizedCharacterName(
      code: character.code,
      name: character.name,
    );
    if (name == character.name) {
      return character;
    }
    return Character(
      id: character.id,
      code: character.code,
      name: name,
      tagline: character.tagline,
      description: character.description,
      avatarUrl: character.avatarUrl,
      avatarStoragePath: character.avatarStoragePath,
      displayOrder: character.displayOrder,
    );
  }

  Character _fallbackCharacterForCode(String code) {
    final normalizedCode = code.trim();
    return Character(
      id: normalizedCode,
      code: normalizedCode,
      name: localizedCharacterName(code: normalizedCode),
      tagline: null,
      description: null,
      avatarUrl: normalizedCode.isEmpty
          ? null
          : 'assets/avatars/$normalizedCode.png',
      displayOrder: 0,
    );
  }

  Widget _buildSceneRow() {
    return FutureBuilder<List<String>>(
      future: widget.sceneAssetsFuture,
      builder: (context, snapshot) {
        final sceneAssets = snapshot.data ?? const <String>[];
        if (sceneAssets.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: storySceneRow(
            sceneAssets,
            sceneCaptions: widget.event.sceneCaptions,
          ),
        );
      },
    );
  }

  Widget _buildReadAndQuizProgress({
    required StoryEvent event,
    required List<BibleRef> refs,
    required List<BibleNavigationTarget> readTargets,
    required bool isBibleRead,
    required bool isQuizCompleted,
    required ({int correct, int total})? lastScore,
    required QuizAttemptSummary? attemptSummary,
    required EventEmotionMark? emotionMark,
  }) {
    return _ReadAndQuizSection(
      eventId: event.id,
      refs: refs,
      readTargets: readTargets,
      isBibleRead: isBibleRead,
      isQuizCompleted: isQuizCompleted,
      emotionMark: emotionMark,
      lastScore: lastScore,
      attemptSummary: attemptSummary,
      onOpenBibleReader: widget.onOpenBibleReader,
      onStartQuiz: () => widget.onStartQuiz(event.id),
      onEngraveEmotion: () => _openEmotionEngraving(event),
      onUndoBibleRead: () => _undoBibleRead(event.id),
      onUndoQuiz: () => _undoQuiz(event.id),
      onUndoEmotionMark: () => _undoEmotionMark(event.id),
    );
  }

  void _undoBibleRead(String eventId) {
    final notifier = ref.read(storyControllerProvider.notifier);
    notifier.setBibleRead(eventId: eventId, isRead: false);
  }

  Future<void> _openEmotionEngraving(StoryEvent event) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      _requestLogin('지도 위에 감정을 새기려면 로그인이 필요해요.');
      return;
    }

    final state = ref.read(storyControllerProvider);
    final existingMark = state.eventEmotionMarks[event.id];
    final saved = await showDialog<EventEmotionOption>(
      context: context,
      builder: (_) {
        return _EmotionEngravingDialog(
          eventTitle: event.title,
          initialMark: existingMark,
          onSave: (option, note) async {
            await ref
                .read(storyControllerProvider.notifier)
                .setEmotionMark(eventId: event.id, option: option, note: note);
          },
        );
      },
    );
    if (!mounted || saved == null) {
      return;
    }
    await widget.onEmotionEngraved?.call(event, saved);
  }

  void _undoQuiz(String eventId) {
    final notifier = ref.read(storyControllerProvider.notifier);
    notifier.setQuizCompleted(eventId: eventId, isCompleted: false);
  }

  void _undoEmotionMark(String eventId) {
    ref
        .read(storyControllerProvider.notifier)
        .clearEmotionMark(eventId: eventId);
  }

  Future<void> _toggleSavedEvent(StoryEvent event) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      _requestLogin('이야기를 저장하려면 로그인이 필요해요.');
      return;
    }
    try {
      final saved = await ref
          .read(storyControllerProvider.notifier)
          .toggleSavedEvent(event.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? '이야기를 저장했어요.' : '저장을 해제했어요.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 상태를 바꾸지 못했습니다.\n$error')));
    }
  }

  Widget _buildNavigationRow() {
    if ((widget.prevEvent == null && widget.nextEvent == null) ||
        widget.onNavigateToEvent == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: widget.prevEvent != null
                ? _NavRow(
                    label: '이전 이야기',
                    event: widget.prevEvent!,
                    isPrev: true,
                    onTap: () => widget.onNavigateToEvent!(widget.prevEvent!),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: widget.nextEvent != null
                ? PulseHighlight(
                    active: _glowNext,
                    child: _NavRow(
                      label: '다음 이야기',
                      event: widget.nextEvent!,
                      isPrev: false,
                      onTap: () => widget.onNavigateToEvent!(widget.nextEvent!),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _StoryHeader extends StatelessWidget {
  const _StoryHeader({
    required this.event,
    required this.isSaved,
    required this.onToggleSaved,
  });

  final StoryEvent event;
  final bool isSaved;
  final VoidCallback onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final metaLabel = _eventDetailMetaLabel(event);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  event.title,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2B15),
                  ),
                ),
              ),
              if (metaLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  metaLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink450,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: isSaved ? '저장 해제' : '이야기 저장',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleSaved,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSaved ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isSaved ? AppColors.goldDeep : const Color(0xFF9A7A4A),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventCharacterAvatarStack extends StatelessWidget {
  const _EventCharacterAvatarStack({required this.characters});

  static const double _size = 31;
  static const double _gap = 5;

  final List<Character> characters;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return const SizedBox.shrink();
    }
    final visibleCharacters = characters.take(4).toList(growable: false);
    final hiddenCount = characters.length - visibleCharacters.length;
    final names = characters.map((character) => character.name).join(', ');

    return Tooltip(
      message: names.isEmpty ? '등장인물' : '등장인물: $names',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < visibleCharacters.length; index++) ...[
            if (index > 0) const SizedBox(width: _gap),
            _EventCharacterAvatarWithName(
              character: visibleCharacters[index],
              size: _size,
            ),
          ],
          if (hiddenCount > 0) ...[
            if (visibleCharacters.isNotEmpty) const SizedBox(width: _gap),
            _HiddenCharacterCountBadge(count: hiddenCount, size: _size),
          ],
        ],
      ),
    );
  }
}

class _EventCharacterAvatarWithName extends StatelessWidget {
  const _EventCharacterAvatarWithName({
    required this.character,
    required this.size,
  });

  final Character character;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = character.name.trim();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CharacterAvatar(character: character, size: size),
          if (name.isNotEmpty)
            Positioned(
              bottom: 1,
              child: _EventCharacterNamePill(name: name, maxWidth: size * 1.06),
            ),
        ],
      ),
    );
  }
}

class _EventCharacterNamePill extends StatelessWidget {
  const _EventCharacterNamePill({required this.name, required this.maxWidth});

  final String name;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xDD201309),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.42),
            width: 0.45,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1.5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 7.8,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HiddenCharacterCountBadge extends StatelessWidget {
  const _HiddenCharacterCountBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF8C6337),
        border: Border.all(color: const Color(0xFFF3E7CC), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Color(0xFFFDF4DE),
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _eventDetailMetaLabel(StoryEvent event) {
  final parts = <String>[];
  final yearLabel = _eventYearLabel(
    event.startYear,
    event.endYear,
    event.timePrecision,
  );
  if (yearLabel.isNotEmpty) {
    parts.add(yearLabel);
  }
  final placeName = event.placeName?.trim();
  if (placeName != null && placeName.isNotEmpty) {
    parts.add(placeName);
  }
  return parts.join(' · ');
}

String _eventYearLabel(int? startYear, int? endYear, String precision) {
  final suffix = precision == 'exact' ? '' : '경';
  if (startYear == null && endYear == null) {
    return '';
  }
  if (startYear == null) {
    return '${_formatHistoricalYear(endYear!)}$suffix';
  }
  if (endYear == null || endYear == startYear) {
    return '${_formatHistoricalYear(startYear)}$suffix';
  }
  final sameEra =
      (startYear < 0 && endYear < 0) || (startYear > 0 && endYear > 0);
  if (sameEra) {
    final prefix = startYear < 0 ? 'B.C. ' : 'A.D. ';
    return '$prefix${startYear.abs()}-${endYear.abs()}년$suffix';
  }
  return '${_formatHistoricalYear(startYear)}-${_formatHistoricalYear(endYear)}$suffix';
}

String _formatHistoricalYear(int year) {
  if (year < 0) {
    return 'B.C. ${year.abs()}년';
  }
  return 'A.D. $year년';
}

/// 이전/다음 이야기 가로 네비 카드. 작은 원형 썸네일 + 라벨 + 사건 제목 + 화살표.
class _NavRow extends StatelessWidget {
  _NavRow({
    required this.label,
    required this.event,
    required this.isPrev,
    required this.onTap,
  });

  final String label;
  final StoryEvent event;
  final bool isPrev;
  final VoidCallback onTap;
  final SceneAssetLoader _loader = SceneAssetLoader();

  @override
  Widget build(BuildContext context) {
    final thumbnail = ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: ColoredBox(
          color: const Color(0xFFF1E4C8),
          child: FutureBuilder<List<String>>(
            future: _loader.loadForEvent(event),
            builder: (_, snap) {
              const placeholder = Icon(
                Icons.menu_book,
                color: Color(0xFF8C6743),
                size: 22,
              );
              if (!snap.hasData || snap.data!.isEmpty) {
                return const Center(child: placeholder);
              }
              final path = snap.data!.first;
              if (path.startsWith('http')) {
                return Image.network(
                  path,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: placeholder),
                );
              }
              return Image.asset(
                path,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: placeholder),
              );
            },
          ),
        ),
      ),
    );

    final textBlock = Column(
      crossAxisAlignment: isPrev
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8C6743),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isPrev ? TextAlign.left : TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF3A2B15),
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x80FFFBEF), // 50% opacity — 시야가 비치는 투명
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x66B89A66), width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 3,
                offset: Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            children: isPrev
                ? [
                    const Icon(
                      Icons.chevron_left,
                      size: 22,
                      color: Color(0xFF8C6743),
                    ),
                    const SizedBox(width: 4),
                    thumbnail,
                    const SizedBox(width: 10),
                    Expanded(child: textBlock),
                  ]
                : [
                    Expanded(child: textBlock),
                    const SizedBox(width: 10),
                    thumbnail,
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: Color(0xFF8C6743),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

/// 본문 읽기 + 퀴즈 풀기 묶음 섹션. 두 버튼 모두 완료해야 사건이 진행률에
/// 추가된다 (StoryController._syncOverallCompletion 이 자동 처리).
class _ReadAndQuizSection extends StatelessWidget {
  const _ReadAndQuizSection({
    required this.eventId,
    required this.refs,
    required this.readTargets,
    required this.isBibleRead,
    required this.isQuizCompleted,
    required this.emotionMark,
    required this.lastScore,
    required this.attemptSummary,
    required this.onOpenBibleReader,
    required this.onStartQuiz,
    required this.onEngraveEmotion,
    required this.onUndoBibleRead,
    required this.onUndoQuiz,
    required this.onUndoEmotionMark,
  });

  final String eventId;
  final List<BibleRef> refs;
  final List<BibleNavigationTarget> readTargets;
  final bool isBibleRead;
  final bool isQuizCompleted;
  final EventEmotionMark? emotionMark;
  final ({int correct, int total})? lastScore;
  final QuizAttemptSummary? attemptSummary;
  final Future<bool> Function(List<BibleNavigationTarget> targets)
  onOpenBibleReader;
  final VoidCallback onStartQuiz;
  final VoidCallback onEngraveEmotion;
  final VoidCallback onUndoBibleRead;
  final VoidCallback onUndoQuiz;
  final VoidCallback onUndoEmotionMark;

  @override
  Widget build(BuildContext context) {
    final readLabel = refs.isEmpty
        ? '본문 읽기'
        : '${refs.map((r) => r.displayText).join(', ')} · 읽기';
    final quizLabel = _quizLabel();
    final canEngrave = isBibleRead && isQuizCompleted;
    final engraved = emotionMark != null;
    final engravingLabel = engraved
        ? _engravingLabel(emotionMark!)
        : '지도 위에 새기기';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF1DC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9B785), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '본문 읽고 퀴즈 풀기',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A2B15),
            ),
          ),
          const SizedBox(height: 10),
          _CompletableActionRow(
            label: readLabel,
            completed: isBibleRead,
            onTap: readTargets.isEmpty
                ? null
                : () => onOpenBibleReader(readTargets),
            onUndo: onUndoBibleRead,
          ),
          const SizedBox(height: 8),
          _CompletableActionRow(
            label: quizLabel,
            completed: isQuizCompleted,
            onTap: onStartQuiz,
            onUndo: onUndoQuiz,
            tone: _quizButtonTone(),
          ),
          const SizedBox(height: 8),
          _CompletableActionRow(
            label: engravingLabel,
            completed: engraved,
            onTap: canEngrave ? onEngraveEmotion : null,
            onUndo: onUndoEmotionMark,
          ),
        ],
      ),
    );
  }

  String _engravingLabel(EventEmotionMark mark) {
    final note = mark.note.trim();
    return note.isEmpty ? mark.emotionLabel : '${mark.emotionLabel} - $note';
  }

  String _quizLabel() {
    final attempt = attemptSummary;
    String countsLabel({
      required int correct,
      required int total,
      required int confused,
    }) {
      final wrong = (total - correct - confused).clamp(0, total);
      return '정답 $correct · 오답 $wrong · 헷갈림 $confused';
    }

    if (!isQuizCompleted) {
      if (attempt != null && attempt.needsReview) {
        return '퀴즈 다시 풀기 (${countsLabel(correct: attempt.correctCount, total: attempt.totalCount, confused: attempt.confusedCount)})';
      }
      return '퀴즈 시작';
    }
    if (lastScore == null || lastScore!.total == 0) {
      return '퀴즈 (없음)';
    }
    if (attempt != null) {
      return '퀴즈 (${countsLabel(correct: attempt.correctCount, total: attempt.totalCount, confused: attempt.confusedCount)})';
    }
    return '퀴즈 (${countsLabel(correct: lastScore!.correct, total: lastScore!.total, confused: 0)})';
  }

  _ActionButtonTone? _quizButtonTone() {
    final attempt = attemptSummary;
    if (attempt != null && attempt.totalCount > 0) {
      return _ActionButtonTone.fromQuizCounts(
        correct: attempt.correctCount,
        total: attempt.totalCount,
      );
    }
    final score = lastScore;
    if (score != null && score.total > 0) {
      return _ActionButtonTone.fromQuizCounts(
        correct: score.correct,
        total: score.total,
      );
    }
    return null;
  }
}

/// 진행 가능한 액션 버튼 한 행 — 미완 시 골드, 완료 시 초록 + 작은 '완료 취소'.
class _CompletableActionRow extends StatelessWidget {
  const _CompletableActionRow({
    required this.label,
    required this.completed,
    required this.onTap,
    required this.onUndo,
    this.tone,
  });

  final String label;
  final bool completed;
  final VoidCallback? onTap;
  final VoidCallback? onUndo;
  final _ActionButtonTone? tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Opacity(
            opacity: onTap == null ? 0.48 : 1,
            child: IgnorePointer(
              ignoring: onTap == null,
              child: filledActionButton(
                label: label,
                onTap: onTap ?? () {},
                completed: completed,
                gradientColors: tone?.gradientColors,
                borderColor: tone?.borderColor,
                shadowColor: tone?.shadowColor,
              ),
            ),
          ),
        ),
        if (completed && onUndo != null) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: const Color(0xFF8C4A3A),
            ),
            child: const Text(
              '완료 취소',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButtonTone {
  const _ActionButtonTone({
    required this.gradientColors,
    required this.borderColor,
    required this.shadowColor,
  });

  final List<Color> gradientColors;
  final Color borderColor;
  final Color shadowColor;

  factory _ActionButtonTone.fromQuizCounts({
    required int correct,
    required int total,
  }) {
    if (total <= 0) {
      return const _ActionButtonTone(
        gradientColors: [AppColors.greenBtnTop, AppColors.greenBtnBot],
        borderColor: AppColors.greenRim,
        shadowColor: Color(0x223D8758),
      );
    }
    if (correct <= 0) {
      return const _ActionButtonTone(
        gradientColors: [AppColors.dangerTop, AppColors.dangerBot],
        borderColor: AppColors.dangerRim,
        shadowColor: Color(0x33B4583B),
      );
    }
    if (correct >= total) {
      return const _ActionButtonTone(
        gradientColors: [AppColors.greenBtnTop, AppColors.greenBtnBot],
        borderColor: AppColors.greenRim,
        shadowColor: Color(0x223D8758),
      );
    }
    return const _ActionButtonTone(
      gradientColors: [Color(0xFFF39A32), Color(0xFFD96518)],
      borderColor: Color(0xFFFFD29A),
      shadowColor: Color(0x33D96518),
    );
  }
}

class _EmotionEngravingDialog extends StatefulWidget {
  const _EmotionEngravingDialog({
    required this.eventTitle,
    required this.initialMark,
    required this.onSave,
  });

  final String eventTitle;
  final EventEmotionMark? initialMark;
  final Future<void> Function(EventEmotionOption option, String note) onSave;

  @override
  State<_EmotionEngravingDialog> createState() =>
      _EmotionEngravingDialogState();
}

class _EmotionEngravingDialogState extends State<_EmotionEngravingDialog> {
  EventEmotionOption? _selected;
  late final TextEditingController _noteController;
  late int _step;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = EventEmotionOption.byKey(widget.initialMark?.emotionKey ?? '');
    _noteController = TextEditingController(
      text: widget.initialMark?.note ?? '',
    );
    _step = widget.initialMark == null ? 0 : 1;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return ParchmentDialog(
      title: '지도 위에 새기기',
      subtitle: widget.eventTitle,
      showCloseButton: true,
      actions: [
        if (_step == 1)
          ParchmentDialogActionButton(
            label: '이전',
            style: ParchmentDialogActionStyle.secondary,
            onTap: _saving ? null : () => setState(() => _step = 0),
          ),
        ParchmentDialogActionButton(
          label: _step == 0 ? '다음' : (_saving ? '저장 중' : '새기기'),
          onTap: _primaryActionEnabled ? _handlePrimaryAction : null,
        ),
      ],
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _step == 0
            ? _buildEmotionStep(context)
            : _buildNoteStep(context, selected),
      ),
    );
  }

  bool get _primaryActionEnabled {
    if (_saving) return false;
    if (_step == 0) return _selected != null;
    return _selected != null && _noteController.text.trim().isNotEmpty;
  }

  Widget _buildEmotionStep(BuildContext context) {
    return Column(
      key: const ValueKey('emotion-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '이 이야기에서 마음에 남은 감정을 하나 골라 주세요.',
          style: TextStyle(
            color: Color(0xFF6A4C2E),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.05,
          children: [
            for (final option in EventEmotionOption.options)
              _EmotionChoiceChip(
                option: option,
                selected: _selected?.key == option.key,
                onTap: () => setState(() => _selected = option),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoteStep(BuildContext context, EventEmotionOption? selected) {
    final option = selected ?? EventEmotionOption.options.last;
    return Column(
      key: const ValueKey('note-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              color: Color(0xFF3A2B15),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
            children: [
              const TextSpan(text: '나는 이 이야기에서 '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: EmotionBadgeIcon(
                    emotionKey: option.key,
                    size: 18,
                    elevation: false,
                  ),
                ),
              ),
              TextSpan(
                text: option.label,
                style: const TextStyle(color: Color(0xFFB07220)),
              ),
              const TextSpan(text: '이 남았다.'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ParchmentDialogTextField(
          controller: _noteController,
          hintText: '왜 이 감정이 남았는지 적어 보세요.',
          maxLength: 100,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  void _handlePrimaryAction() {
    if (_step == 0) {
      setState(() => _step = 1);
      return;
    }
    final selected = _selected;
    if (selected == null) return;
    _save(selected);
  }

  Future<void> _save(EventEmotionOption selected) async {
    setState(() => _saving = true);
    try {
      await widget.onSave(selected, _noteController.text);
      if (mounted) {
        Navigator.of(context).pop(selected);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _EmotionChoiceChip extends StatelessWidget {
  const _EmotionChoiceChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final EventEmotionOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFE7B8) : const Color(0xFFF8F0E2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFFB07220)
                  : const Color(0xAA8E6F48),
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmotionBadgeIcon(
                emotionKey: option.key,
                size: 18,
                elevation: false,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF7C4716)
                        : const Color(0xFF5E4427),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
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

/// 사역자/관리자 전용 — 이 이야기에 대한 삭제 제안을 내는 TextButton.
///
/// 일반 사용자에게는 아예 렌더되지 않는다. 권한 프로바이더가 로딩 중이면 빈
/// 공간으로 fallback 해 레이아웃이 흔들리지 않도록 한다.
class _DeleteProposalButton extends ConsumerWidget {
  const _DeleteProposalButton({required this.event});

  final StoryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 삭제 제안은 pastor 또는 admin 누구나 가능. (admin 은 직접 DB 조작도
    // 가능하지만, 제안 채널을 통해 history/댓글이 남도록 일관성 유지)
    final isAdmin = ref.watch(isAdminProvider);
    final isPastorAsync = ref.watch(isPastorProvider);
    final isPastor = isPastorAsync.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    if (!isAdmin && !isPastor) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('이 이야기 삭제 제안'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF8C4A3A)),
          onPressed: () {
            showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => DeleteEventProposalSheet(event: event),
            );
          },
        ),
      ),
    );
  }
}
