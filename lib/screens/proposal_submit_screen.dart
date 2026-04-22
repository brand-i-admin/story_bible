import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/event_proposal.dart';
import '../models/story_event.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../widgets/proposal/bible_refs_picker.dart';
import '../widgets/proposal/character_codes_picker.dart';
import '../widgets/proposal/new_character_dialog.dart';
import '../widgets/proposal/proposal_character_row.dart';
import '../widgets/proposal/proposal_location_picker.dart';
import '../widgets/proposal/proposal_quiz_editor.dart';
import '../widgets/proposal/proposal_scenes_editor.dart';
import '../widgets/proposal/scene_characters_grid.dart';

/// 이야기 제안 등록/수정 폼 (wizard).
///
/// 홈 UI 톤으로 5 단계:
///   Step 0. 안내
///   Step 1. 시대 선택 (구약/신약 탭 + era 카드 그리드)
///   Step 2. 등장인물과 위치 선택
///           sub-phase: characters(복수) → event:0 → event:1 → ... → summary
///   Step 3. 세부 내용 (제목 / 요약 / 장소(지도) / 연도 / 성경 / 장면)
///   Step 4. 퀴즈 (4지선다 1~3개) + 최종 "제안 등록" 버튼
///
/// 최종 `after_story_index` 는 **선택된 인물별 사건의 story_index 중 최댓값**.
/// 이 뒤에 삽입되면 모든 선택된 사건 이상(+) 으로 시프트되어 정합성 유지.
class ProposalSubmitScreen extends ConsumerStatefulWidget {
  const ProposalSubmitScreen({super.key, this.existing});

  final EventProposal? existing;

  @override
  ConsumerState<ProposalSubmitScreen> createState() =>
      _ProposalSubmitScreenState();
}

class _ProposalSubmitScreenState extends ConsumerState<ProposalSubmitScreen> {
  // Top-level wizard step.
  // 0: intro, 1: era, 2: characters & position, 3: details, 4: quiz
  int _step = 0;

  // Step 2 내부 sub-phase. 'characters' | 'event:<index>' | 'summary'
  String _step2Phase = 'characters';

  // Selections
  String _testament = 'old';
  String? _eraId;
  List<String> _characterCodes = const [];
  // 최종 삽입 위치. null = 맨 앞 또는 미선택 — _positionPicked 로 구분.
  int? _afterStoryIndex;
  bool _positionPicked = false;

  // Options loaded once
  List<Era> _eras = const [];
  List<CharacterOption> _characterOptions = const [];
  final Map<String, List<StoryEvent>> _eventsByEra = {};

  // Step 3 fields
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _startYearCtrl = TextEditingController();
  final _endYearCtrl = TextEditingController();
  String _timePrecision = 'approx';
  double? _lat;
  double? _lng;
  List<Map<String, String>> _bibleRefs = const [];
  List<String> _scenes = const [''];
  List<List<String>> _sceneCharacters = const [[]];

  // 장면별 AI 생성 이미지 상태 (scenes 와 같은 길이로 유지).
  List<ProposalSceneImage> _sceneImages = const [ProposalSceneImage()];

  // 이번 제안에서 새로 만든 캐릭터 (기존 characters 에 없던 것).
  // Submit 시 `proposed_characters` 컬럼에 그대로 저장된다.
  // key = character code, value = ProposedCharacter.
  final Map<String, ProposedCharacter> _newCharactersByCode = {};

  // Step 4 퀴즈 초안. 최소 1개, 최대 3개. 초기값은 빈 퀴즈 1개.
  List<QuizDraft> _quizDrafts = const [QuizDraft.empty];

  // 이번 제안의 draft 식별자. 서버 bucket 경로(`.../draftId/scene_N.png`) 에
  // 쓰여 같은 draft 안의 scene 들이 한 폴더에 모인다. 제출 성공 후 이 값은
  // 더 이상 바뀌지 않는다 (수정 모드에서는 기존 proposal.id 를 사용).
  late String _draftId;

  // 이미지 생성 중 전역 블로킹. AI 에 한 번에 한 장만 보낼 수 있도록.
  bool _generatingImage = false;
  int? _generatingSceneIndex;

  bool _loadingOptions = true;
  bool _loadingEvents = false;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _eraId = e.eraId;
      _characterCodes = List.of(e.characterCodes);
      // 기존 after_story_index 가 있으면 모든 인물에 동일하게 기록
      if (e.afterStoryIndex != null) {
        _afterStoryIndex = e.afterStoryIndex;
        _positionPicked = true;
      }
      _lat = e.lat;
      _lng = e.lng;
      _timePrecision = e.timePrecision;
      _titleCtrl.text = e.title;
      _summaryCtrl.text = e.summary ?? '';
      _placeCtrl.text = e.placeName ?? '';
      _startYearCtrl.text = e.startYear?.toString() ?? '';
      _endYearCtrl.text = e.endYear?.toString() ?? '';
      _bibleRefs = e.bibleRefs
          .map<Map<String, String>>(
            (m) => m.map((k, v) => MapEntry(k, v?.toString() ?? '')),
          )
          .toList();
      _scenes = e.storyScenes.isEmpty ? [''] : List.of(e.storyScenes);
      _sceneCharacters = List.generate(
        _scenes.length,
        (i) => i < e.sceneCharacters.length
            ? List<String>.of(e.sceneCharacters[i])
            : <String>[],
      );
      // 수정 모드: 기존 이미지 경로 + prompt 를 그대로 복원해 draft 상태에서
      // "재생성" 으로만 갱신되도록.
      _sceneImages = List.generate(_scenes.length, (i) {
        final path = i < e.sceneImagePaths.length ? e.sceneImagePaths[i] : '';
        final prompt = i < e.sceneImagePrompts.length
            ? e.sceneImagePrompts[i]
            : '';
        return ProposalSceneImage(
          path: path.isEmpty ? null : path,
          prompt: prompt.isEmpty ? null : prompt,
        );
      });
      // 수정 모드에서 기존 제안에 있던 새 캐릭터 복원.
      for (final c in e.proposedCharacters) {
        if (c.code.isNotEmpty) _newCharactersByCode[c.code] = c;
      }
      // 기존 퀴즈 복원 (빈 배열이면 빈 퀴즈 1개로 초기화해 editor 가 비정상 상태
      // 로 빠지지 않게 함).
      _quizDrafts = e.quizQuestions.isEmpty
          ? const [QuizDraft.empty]
          : e.quizQuestions;
      // 수정 모드는 Step 3 (details) 에서 바로 시작
      _step = 3;
      // draftId 는 proposal id 를 그대로 사용 — 이미지 덮어쓰기가 같은
      // 폴더에 이뤄지도록.
      _draftId = e.id;
    } else {
      _sceneImages = const [ProposalSceneImage()];
      _draftId = _generateDraftId();
    }
    // 텍스트 필드 변경 시 제출 버튼 활성화 여부 재평가.
    _titleCtrl.addListener(_onFormChanged);
    _summaryCtrl.addListener(_onFormChanged);
    _placeCtrl.addListener(_onFormChanged);
    _startYearCtrl.addListener(_onFormChanged);
    _endYearCtrl.addListener(_onFormChanged);
    _loadOptions();
  }

  /// 간단한 draft id — time + random. supabase storage path 에만 쓰이므로 UUID
  /// 형식 강제는 불필요. 서버 편에서 폴더 이름으로만 사용.
  String _generateDraftId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = (DateTime.now().microsecondsSinceEpoch & 0xffff).toRadixString(
      16,
    );
    return 'draft_${ts}_$rand';
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onFormChanged);
    _summaryCtrl.removeListener(_onFormChanged);
    _placeCtrl.removeListener(_onFormChanged);
    _startYearCtrl.removeListener(_onFormChanged);
    _endYearCtrl.removeListener(_onFormChanged);
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _placeCtrl.dispose();
    _startYearCtrl.dispose();
    _endYearCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final client = ref.read(supabaseClientProvider);
      final eras = await ref.read(storyRepositoryProvider).fetchEras();
      final characterRows = await client
          .from('characters')
          .select('code, name')
          .order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _eras = eras;
        _characterOptions = characterRows
            .map<CharacterOption>(
              (row) => CharacterOption(
                code: row['code'] as String,
                name: row['name'] as String,
              ),
            )
            .toList();
        _loadingOptions = false;
        // 기존 era 가 있으면 testament 도 맞춤
        if (_eraId != null) {
          final match = eras.where((e) => e.id == _eraId).toList();
          if (match.isNotEmpty) _testament = match.first.testament;
          _loadEventsForEra(_eraId!);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _errorText = '옵션을 불러오지 못했습니다: $e';
      });
    }
  }

  Future<void> _loadEventsForEra(String eraId) async {
    if (_eventsByEra.containsKey(eraId)) return;
    setState(() => _loadingEvents = true);
    try {
      final events = await ref
          .read(storyRepositoryProvider)
          .fetchEventsByEra(eraId);
      if (!mounted) return;
      setState(() {
        _eventsByEra[eraId] = events;
        _loadingEvents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eventsByEra[eraId] = const [];
        _loadingEvents = false;
      });
    }
  }

  // ===== Derived =====

  /// Step 3 세부사항 검증 — Step 4(퀴즈) 로 넘어가기 위한 최소 조건.
  /// (시대/등장인물/삽입 위치 는 Step 2 에서 이미 확정된 상태로 Step 3 에 옴)
  bool get _canProceedFromDetails {
    if (_titleCtrl.text.trim().isEmpty) return false;
    if (_summaryCtrl.text.trim().isEmpty) return false;
    // 장소: 이름 + 지도 좌표 모두 필수
    if (_placeCtrl.text.trim().isEmpty) return false;
    if (_lat == null || _lng == null) return false;
    // 연도: 시작/끝 둘 다 정수 + 끝 ≥ 시작
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null || ey == null) return false;
    if (ey < sy) return false;
    // 성경 본문: 최소 1개
    if (_bibleRefs.isEmpty) return false;
    // 장면: trim 후 non-empty 가 최소 1개
    final nonEmptyScenes = _scenes
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (nonEmptyScenes.isEmpty) return false;
    // 장면 이미지: 입력된 모든 장면이 생성 완료되어야 다음 단계로 진행 가능
    for (var i = 0; i < _scenes.length; i++) {
      if (_scenes[i].trim().isEmpty) continue;
      if (i >= _sceneImages.length || !_sceneImages[i].isReady) {
        return false;
      }
    }
    return true;
  }

  /// 퀴즈 검증 — 1~3개 각각 완전히 채워져 있어야 함 (RPC CHECK 와 동일).
  bool get _canSubmitQuiz {
    if (_quizDrafts.isEmpty || _quizDrafts.length > 3) return false;
    return _quizDrafts.every((q) => q.isValid);
  }

  /// 최종 제출 버튼 활성화 조건 — 세부사항 + 퀴즈 모두 유효.
  bool get _canSubmit => _canProceedFromDetails && _canSubmitQuiz;

  /// 연도 입력 에러 (끝 < 시작 인 경우에만). 비어있거나 파싱 실패는 null.
  String? get _yearError {
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null || ey == null) return null;
    if (ey < sy) return '끝 연도는 시작 연도와 같거나 더 뒤여야 합니다.';
    return null;
  }

  List<Era> get _visibleEras =>
      _eras.where((e) => e.testament == _testament).toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  List<StoryEvent> get _eraEvents =>
      _eraId != null ? (_eventsByEra[_eraId!] ?? const []) : const [];

  Era? get _selectedEra {
    if (_eraId == null) return null;
    final match = _eras.where((e) => e.id == _eraId);
    return match.isEmpty ? null : match.first;
  }

  /// 선택된 인물이 한 명 이상 등장하는 events — position phase 리스트용.
  List<StoryEvent> _eventsForPositionList() {
    if (_characterCodes.isEmpty) return const [];
    final selected = _characterCodes.toSet();
    return _eraEvents
        .where((e) => e.characterCodes.any(selected.contains))
        .toList();
  }

  // ===== Step navigation =====

  bool get _canGoNext {
    switch (_step) {
      case 0:
        return true; // intro — 언제나 진행 가능
      case 1:
        return _eraId != null;
      case 2:
        switch (_step2Phase) {
          case 'characters':
            return _characterCodes.isNotEmpty;
          case 'position':
            return _positionPicked;
          case 'summary':
            return _positionPicked;
          default:
            return false;
        }
      case 3:
        // Step 3 (세부사항) 이 모두 유효해야 Step 4 (퀴즈) 로 이동 가능
        return _canProceedFromDetails;
      case 4:
        return true; // 마지막 단계 — 제출 버튼이 별도
    }
    return false;
  }

  void _onNext() {
    if (!_canGoNext) return;
    setState(() {
      switch (_step) {
        case 0:
          _step = 1;
          break;
        case 1:
          _step = 2;
          _step2Phase = 'characters';
          break;
        case 2:
          switch (_step2Phase) {
            case 'characters':
              _step2Phase = 'position';
              break;
            case 'position':
              _step2Phase = 'summary';
              break;
            case 'summary':
              _step = 3;
              break;
          }
          break;
        case 3:
          _step = 4;
          break;
        case 4:
          // 마지막 단계 — 제출 버튼으로만 진행
          break;
      }
    });
  }

  void _onPrev() {
    setState(() {
      switch (_step) {
        case 0:
          return;
        case 1:
          _step = 0;
          break;
        case 2:
          switch (_step2Phase) {
            case 'characters':
              _step = 1;
              break;
            case 'position':
              _step2Phase = 'characters';
              break;
            case 'summary':
              _step2Phase = 'position';
              break;
          }
          break;
        case 3:
          _step = 2;
          _step2Phase = 'summary';
          break;
        case 4:
          _step = 3;
          break;
      }
    });
  }

  // ===== Submit =====

  Future<void> _onSubmit() async {
    if (_eraId == null) {
      setState(() => _errorText = '시대를 선택해주세요.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _errorText = '제목은 필수입니다.');
      return;
    }
    final scenes = _scenes
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (scenes.isEmpty) {
      setState(() => _errorText = '장면을 최소 1개 입력해주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final repo = ref.read(proposalRepositoryProvider);
    // scenes 에 해당하는 (비어있지 않은) 인덱스만 골라 이미지/프롬프트 배열 재구성.
    final paddedSceneCharacters = <List<String>>[];
    final sceneImagePaths = <String>[];
    final sceneImagePrompts = <String>[];
    for (var i = 0; i < _scenes.length; i++) {
      if (_scenes[i].trim().isEmpty) continue;
      paddedSceneCharacters.add(
        i < _sceneCharacters.length ? _sceneCharacters[i] : const [],
      );
      final img = i < _sceneImages.length
          ? _sceneImages[i]
          : const ProposalSceneImage();
      sceneImagePaths.add(img.path ?? '');
      sceneImagePrompts.add(img.prompt ?? '');
    }
    final refsAsDynamic = _bibleRefs
        .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
        .toList();
    final afterIdx = _afterStoryIndex;

    try {
      // 현재 선택된 인물들 중 실제 "이번에 새로 만든" 것만 proposed 로 보낸다.
      // 사용자가 선택 해제한 새 캐릭터는 제외.
      final selectedCodes = _characterCodes.toSet();
      final proposedCharactersPayload = _newCharactersByCode.values
          .where((c) => selectedCodes.contains(c.code))
          .toList(growable: false);
      if (widget.existing == null) {
        await repo.submit(
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _emptyAsNull(_summaryCtrl.text),
          characterCodes: _characterCodes,
          placeName: _emptyAsNull(_placeCtrl.text),
          lat: _lat,
          lng: _lng,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: _bibleRefs,
          storyScenes: scenes,
          sceneCharacters: paddedSceneCharacters,
          sceneImagePaths: sceneImagePaths,
          sceneImagePrompts: sceneImagePrompts,
          proposedCharacters: proposedCharactersPayload,
          quizQuestions: _quizDrafts,
          afterStoryIndex: afterIdx,
        );
      } else {
        await repo.updateProposal(
          proposalId: widget.existing!.id,
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _emptyAsNull(_summaryCtrl.text),
          characterCodes: _characterCodes,
          placeName: _emptyAsNull(_placeCtrl.text),
          lat: _lat,
          lng: _lng,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: refsAsDynamic,
          storyScenes: scenes,
          sceneCharacters: paddedSceneCharacters,
          sceneImagePaths: sceneImagePaths,
          sceneImagePrompts: sceneImagePrompts,
          proposedCharacters: proposedCharactersPayload,
          quizQuestions: _quizDrafts,
          afterStoryIndex: afterIdx,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null ? '제안이 등록되었습니다 (대기중)' : '제안이 수정되었습니다',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = 'DB 오류: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '제출 실패: $e';
      });
    }
  }

  String? _emptyAsNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  // ===== Build =====

  @override
  Widget build(BuildContext context) {
    if (_loadingOptions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '새 이야기 제안' : '제안 수정'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ProgressHeader(step: _step),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _errorText!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: _buildStepBody(theme)),
                _buildBottomNav(theme),
              ],
            ),
          ),
          if (_generatingImage) const _GeneratingImageOverlay(),
        ],
      ),
    );
  }

  Widget _buildStepBody(ThemeData theme) {
    switch (_step) {
      case 0:
        return _buildStep0Intro(theme);
      case 1:
        return _buildStep1Era(theme);
      case 2:
        switch (_step2Phase) {
          case 'characters':
            return _buildStep2Persons(theme);
          case 'position':
            return _buildStep2Position(theme);
          case 'summary':
            return _buildStep2Summary(theme);
          default:
            return const SizedBox.shrink();
        }
      case 3:
        return _buildStep3Details(theme);
      case 4:
        return _buildStep4Quiz(theme);
    }
    return const SizedBox.shrink();
  }

  // ---------- Step 0: 안내 ----------
  Widget _buildStep0Intro(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '새 성경 이야기를 제안합니다',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Text(
                  '시작하기 전에 아래 내용을 확인해주세요. 새 이야기는 모든 정보가 입력되어야 관리자 승인 후 지도에 나타날 수 있습니다.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                const _IntroBullet(
                  number: '1',
                  title: '시대를 고릅니다',
                  body: '구약 6시대 · 신약 4시대 중 이 이야기가 속한 시대를 선택합니다.',
                ),
                const _IntroBullet(
                  number: '2',
                  title: '이 이야기에 등장할 모든 인물을 고릅니다',
                  body: '복수 선택 가능. 해당 시대에 이미 등장한 인물이 우선 정렬되어 나옵니다.',
                ),
                const _IntroBullet(
                  number: '3',
                  title: '새 이야기가 들어갈 위치를 고릅니다',
                  body:
                      '선택한 등장인물들이 나오는 이야기들이 시대 순서대로 한 페이지에 나열됩니다. '
                      '그 중 새 이야기가 어느 이야기 뒤에 들어가면 좋을지 하나 골라주세요.',
                ),
                const _IntroBullet(
                  number: '4',
                  title: '세부 내용을 작성합니다',
                  body: '제목 / 요약 / 장소(지도) / 연도 / 성경 본문 / 4장면까지 입력 후 제출합니다.',
                ),
                const SizedBox(height: 24),
                Text(
                  '제출 후 관리자 검토를 거쳐 승인되면 앱의 지도에 반영됩니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Step 1: 시대 ----------
  Widget _buildStep1Era(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'old', label: Text('구약')),
              ButtonSegment(value: 'new', label: Text('신약')),
            ],
            selected: {_testament},
            onSelectionChanged: (s) => setState(() {
              _testament = s.first;
              // era 선택이 필터 밖으로 밀려나면 리셋
              if (_selectedEra?.testament != _testament) {
                _eraId = null;
                _afterStoryIndex = null;
                _positionPicked = false;
              }
            }),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 360,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3.2,
              children: [
                for (var i = 0; i < _visibleEras.length; i++)
                  _EraCard(
                    index: i + 1,
                    era: _visibleEras[i],
                    selected: _eraId == _visibleEras[i].id,
                    onTap: () => _selectEra(_visibleEras[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectEra(Era era) {
    setState(() {
      _eraId = era.id;
      // era 바뀌면 이전 선택 리셋
      _afterStoryIndex = null;
      _positionPicked = false;
    });
    _loadEventsForEra(era.id);
  }

  // ---------- Step 2a: 인물 복수 ----------
  Widget _buildStep2Persons(ThemeData theme) {
    final era = _selectedEra;
    // era 의 published events 에 실제 등장하는 인물 코드만 우선순위로
    final presentCodes = <String>{
      for (final ev in _eraEvents) ...ev.characterCodes,
    };
    final sorted = <CharacterOption>[];
    final later = <CharacterOption>[];
    for (final opt in _characterOptions) {
      if (presentCodes.contains(opt.code)) {
        sorted.add(opt);
      } else {
        later.add(opt);
      }
    }
    sorted.sort((a, b) => a.name.compareTo(b.name));
    later.sort((a, b) => a.name.compareTo(b.name));

    // "이번 제안에서 새로 만든" 인물 카드 (별도 섹션) — 기존 목록엔 없으므로
    // 수동 렌더. CharacterOption 으로 변환해 같은 chip group helper 를 재사용.
    final newOpts =
        _newCharactersByCode.values
            .map((c) => CharacterOption(code: c.code, name: c.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${era?.name ?? ''} 안에서 이 이야기에 등장할 인물들을 고르세요',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '복수 선택 가능. 다음 단계에서 각 인물별로 이 이야기가 어느 사건 뒤에 들어갈지 고르게 됩니다. '
            '목록에 없는 인물은 "새 인물 만들기" 로 AI 아바타를 생성해 추가할 수 있습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openNewCharacterDialog,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('새 인물 만들기'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (newOpts.isNotEmpty) ...[
                    _characterChipGroup(theme, '이번 제안에서 새로 만든 인물', newOpts),
                    const SizedBox(height: 16),
                  ],
                  if (sorted.isNotEmpty)
                    _characterChipGroup(theme, '이 시대 등장 인물', sorted),
                  if (later.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _characterChipGroup(theme, '전체 인물', later),
                  ],
                  const SizedBox(height: 16),
                  Text('선택 요약', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _SummaryBox(
                    children: _characterCodes.isEmpty
                        ? const [Text('선택된 인물이 없습니다')]
                        : [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in _characterCodes)
                                  Chip(label: Text(_displayName(c))),
                              ],
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "새 인물 만들기" 버튼 핸들러.
  Future<void> _openNewCharacterDialog() async {
    final existing = <String>{
      for (final o in _characterOptions) o.code,
      ..._newCharactersByCode.keys,
    };
    final added = await NewCharacterDialog.show(
      context,
      draftId: _draftId,
      existingCodes: existing,
    );
    if (added == null || !mounted) return;
    setState(() {
      _newCharactersByCode[added.code] = added;
      // 아바타 row / 장면 생성 시에도 이 코드가 쓰이므로 options 에도 삽입.
      // 주의: `_characterOptions` 는 DB 로드된 최종 목록이라, 런타임에만 추가.
      if (!_characterOptions.any((o) => o.code == added.code)) {
        _characterOptions = [
          ..._characterOptions,
          CharacterOption(code: added.code, name: added.name),
        ];
      }
      // 방금 만든 인물은 자동으로 선택 상태로.
      if (!_characterCodes.contains(added.code)) {
        _characterCodes = [..._characterCodes, added.code];
      }
    });
  }

  Widget _characterChipGroup(
    ThemeData theme,
    String title,
    List<CharacterOption> opts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in opts)
              FilterChip(
                label: Text(p.name),
                selected: _characterCodes.contains(p.code),
                onSelected: (sel) => _toggleCharacter(p.code),
              ),
          ],
        ),
      ],
    );
  }

  void _toggleCharacter(String code) {
    setState(() {
      final next = List<String>.of(_characterCodes);
      if (next.remove(code)) {
        // 인물 제외 시 이미 한 위치 선택이 있었으면 유지 (era 단위 선택이라 유효)
      } else {
        next.add(code);
      }
      _characterCodes = next;
    });
  }

  String _displayName(String code) {
    final match = _characterOptions.where((p) => p.code == code).toList();
    return match.isNotEmpty ? match.first.name : code;
  }

  // ===== Step 4: 장면 이미지 생성 =====

  /// 이 이야기에 등장할 인물 아바타 row — Step 4 상단에 표시.
  /// 새로 만든 캐릭터는 proposal-characters 버킷 경로, 기존 캐릭터는 characters
  /// 버킷의 `{code}.png` 로 해석.
  List<ProposalCharacterRowItem> _characterRowItems() {
    final client = ref.read(supabaseClientProvider);
    final repo = ref.read(proposalRepositoryProvider);
    return _characterCodes.map((code) {
      final opt = _characterOptions.firstWhere(
        (c) => c.code == code,
        orElse: () => CharacterOption(code: code, name: code),
      );
      final newChar = _newCharactersByCode[code];
      final url = newChar != null
          ? repo.publicUrlForStoragePath(newChar.storagePath)
          : client.storage.from('characters').getPublicUrl('$code.png');
      return ProposalCharacterRowItem(
        code: code,
        name: opt.name,
        avatarUrl: url,
      );
    }).toList();
  }

  /// `ProposalScenesEditor.onGenerate` 콜백 — Edge Function 에 1장 생성 요청.
  /// 전역 `_generatingImage` 플래그로 다른 버튼을 블록.
  Future<ProposalSceneImage?> _onGenerateSceneImage(
    int sceneIndex,
    String sceneText,
  ) async {
    if (_generatingImage) return null;
    setState(() {
      _generatingImage = true;
      _generatingSceneIndex = sceneIndex;
      _errorText = null;
    });
    try {
      final repo = ref.read(proposalRepositoryProvider);
      final result = await repo.generateProposalScene(
        sceneText: sceneText,
        characterCodes: _characterCodes,
        draftId: _draftId,
        sceneIndex: sceneIndex,
        eventTitle: _titleCtrl.text.trim().isEmpty
            ? null
            : _titleCtrl.text.trim(),
        placeName: _placeCtrl.text.trim().isEmpty
            ? null
            : _placeCtrl.text.trim(),
      );
      return ProposalSceneImage(
        path: result.storagePath,
        prompt: result.prompt,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = '이미지 생성 실패: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 생성 실패: $e')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _generatingImage = false;
          _generatingSceneIndex = null;
        });
      }
    }
  }

  // ---------- Step 2b: 통합 위치 선택 (인물 라벨 포함) ----------
  Widget _buildStep2Position(ThemeData theme) {
    final events = _eventsForPositionList();
    final selectedSet = _characterCodes.toSet();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('새 이야기가 들어갈 위치를 하나 고르세요', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '선택한 등장인물들이 나오는 이야기들이 시대 순서대로 나열됩니다. '
            '탭한 이야기 "뒤"에 새 이야기가 들어갑니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingEvents
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      _InsertionCard(
                        title: '맨 앞에 배치',
                        subtitle: '이 시대의 첫 이야기가 됩니다',
                        selected: _positionPicked && _afterStoryIndex == null,
                        onTap: () => setState(() {
                          _afterStoryIndex = null;
                          _positionPicked = true;
                        }),
                      ),
                      if (events.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              '선택한 인물들이 등장하는 이야기가 아직 없습니다. "맨 앞" 선택만 가능합니다.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final e in events)
                          _InsertionCard(
                            title: e.title,
                            subtitle: e.summary ?? '',
                            storyIndex: e.storyIndex,
                            // 카드에 "이 이야기에 등장하는" 인물 중 현재 선택된 것 강조.
                            characterLabels: [
                              for (final c in e.characterCodes)
                                if (selectedSet.contains(c))
                                  _CharacterLabel(
                                    name: _displayName(c),
                                    highlighted: true,
                                  ),
                            ],
                            selected:
                                _positionPicked &&
                                _afterStoryIndex == e.storyIndex,
                            onTap: () => setState(() {
                              _afterStoryIndex = e.storyIndex;
                              _positionPicked = true;
                            }),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- Step 2 summary ----------
  Widget _buildStep2Summary(ThemeData theme) {
    final era = _selectedEra;
    final finalIdx = _afterStoryIndex;
    final selectedEventTitle = finalIdx == null
        ? '맨 앞'
        : _eraEvents
              .where((e) => e.storyIndex == finalIdx)
              .map((e) => e.title)
              .firstOrEmpty();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('선택 요약', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _SummaryBox(
            children: [
              _kv(theme, '시대', era?.name ?? '—'),
              const SizedBox(height: 6),
              _kv(
                theme,
                '등장 인물',
                _characterCodes.isEmpty
                    ? '—'
                    : _characterCodes.map(_displayName).join(', '),
              ),
              const Divider(height: 20),
              _kv(
                theme,
                '삽입 위치',
                finalIdx == null
                    ? '${era?.name ?? '시대'} 의 맨 앞'
                    : '$selectedEventTitle (#$finalIdx) 뒤',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            k,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    );
  }

  // ---------- Step 3 details ----------
  Widget _buildStep3Details(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryChipRow(theme),
        _sectionTitle('제목'),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(hintText: '예: 창조: 7일과 안식'),
        ),
        _sectionTitle('요약'),
        TextField(
          controller: _summaryCtrl,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '최대 4문장으로 요약'),
        ),
        _sectionTitle('장소'),
        TextField(
          controller: _placeCtrl,
          decoration: const InputDecoration(
            hintText: '예: 베들레헴 (좌표는 아래 지도에서 고릅니다)',
          ),
        ),
        const SizedBox(height: 8),
        ProposalLocationPicker(
          initialLat: _lat,
          initialLng: _lng,
          referencePins: _referencePinsForSelectedCharacters(),
          onChanged: (lat, lng) => setState(() {
            _lat = lat;
            _lng = lng;
          }),
        ),
        _sectionTitle('연도'),
        _yearHint(theme),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startYearCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: '시작 (BC는 음수)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _endYearCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: '끝'),
              ),
            ),
          ],
        ),
        if (_yearError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _yearError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _timePrecision,
          items: const [
            DropdownMenuItem(value: 'approx', child: Text('대략 (approx)')),
            DropdownMenuItem(value: 'exact', child: Text('정확 (exact)')),
          ],
          onChanged: (v) => setState(() => _timePrecision = v ?? 'approx'),
          decoration: const InputDecoration(labelText: '연도 정확도'),
        ),
        _sectionTitle('성경 본문'),
        BibleRefsPicker(
          initial: _bibleRefs,
          onChanged: (refs) => setState(() => _bibleRefs = refs),
        ),
        _sectionTitle('장면 (이미지 생성용)'),
        ProposalCharacterRow(characters: _characterRowItems()),
        const SizedBox(height: 10),
        ProposalScenesEditor(
          initialScenes: _scenes,
          initialImages: _sceneImages,
          busy: _generatingImage,
          busySceneIndex: _generatingSceneIndex,
          publicUrlForPath: (path) => ref
              .read(proposalRepositoryProvider)
              .publicUrlForProposalScene(path),
          onChanged: (scenes, images) => setState(() {
            _scenes = scenes;
            _sceneCharacters = List.generate(
              scenes.length,
              (i) => i < _sceneCharacters.length
                  ? _sceneCharacters[i]
                  : const <String>[],
            );
            // 길이 맞추기. 새 장면이 추가되면 빈 이미지로 초기화.
            _sceneImages = List.generate(
              scenes.length,
              (i) => i < images.length ? images[i] : const ProposalSceneImage(),
            );
          }),
          onGenerate: _onGenerateSceneImage,
        ),
        _sectionTitle('장면별 등장 인물'),
        SceneCharactersGrid(
          characterCodes: _characterCodes,
          sceneCount: _scenes.length,
          initial: _sceneCharacters,
          onChanged: (sp) => setState(() => _sceneCharacters = sp),
          characterNameByCode: {
            for (final opt in _characterOptions) opt.code: opt.name,
          },
        ),
        const SizedBox(height: 24),
        if (!_canProceedFromDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '모든 필수 항목을 채우면 "다음" 버튼이 활성화됩니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ---------- Step 4: 퀴즈 + 제출 ----------
  Widget _buildStep4Quiz(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '이야기를 읽은 사람이 풀 4지선다 퀴즈를 1~3개 만들어주세요.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ProposalQuizEditor(
          initial: _quizDrafts,
          onChanged: (drafts) => setState(() => _quizDrafts = drafts),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_submitting || !_canSubmit) ? null : _onSubmit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.existing == null ? '제안 등록' : '수정 저장'),
          ),
        ),
        if (!_canSubmit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '문제·선택지 4개·해설을 모두 채우면 제출 버튼이 활성화됩니다.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  // 선택된 인물들이 등장하는 기존 이야기 좌표 — 지도 picker 에 힌트로 표시.
  // Step 2 에서 고른 '이 이야기 뒤' 의 이야기는 highlighted 로 표시해 강조.
  List<ProposalReferencePin> _referencePinsForSelectedCharacters() {
    if (_characterCodes.isEmpty) return const [];
    final selected = _characterCodes.toSet();
    final pins = <ProposalReferencePin>[];
    for (final e in _eraEvents) {
      if (e.lat == null || e.lng == null) continue;
      final isHighlighted =
          _afterStoryIndex != null && e.storyIndex == _afterStoryIndex;
      if (isHighlighted || e.characterCodes.any(selected.contains)) {
        pins.add(
          ProposalReferencePin(
            lat: e.lat!,
            lng: e.lng!,
            label: e.title,
            highlighted: isHighlighted,
          ),
        );
      }
    }
    return pins;
  }

  // "이전 이야기": Step 2 에서 고른 바로 그 이야기 (신규 이야기가 그 뒤에 들어감).
  StoryEvent? get _prevEvent {
    if (_afterStoryIndex == null) return null;
    final match = _eraEvents.where((e) => e.storyIndex == _afterStoryIndex);
    return match.isEmpty ? null : match.first;
  }

  // "다음 이야기": 새 이야기 뒤에 밀려날 이야기 (시프트 전 기준 story_index +1).
  // _afterStoryIndex == null 이면 새 이야기가 맨 앞이므로 현재 story_index=1 인
  // 이야기가 다음으로 밀려난다.
  StoryEvent? get _nextEvent {
    final target = (_afterStoryIndex ?? 0) + 1;
    final match = _eraEvents.where((e) => e.storyIndex == target);
    return match.isEmpty ? null : match.first;
  }

  // 연도 입력 힌트 — 선택 인물 전체 범위 + 이전/다음 이야기 연도.
  Widget _yearHint(ThemeData theme) {
    if (_characterCodes.isEmpty) return const SizedBox.shrink();
    final selected = _characterCodes.toSet();
    final starts = <int>[];
    final ends = <int>[];
    for (final e in _eraEvents) {
      if (!e.characterCodes.any(selected.contains)) continue;
      if (e.startYear != null) starts.add(e.startYear!);
      if (e.endYear != null) ends.add(e.endYear!);
    }
    final hasRange = starts.isNotEmpty || ends.isNotEmpty;
    final prev = _prevEvent;
    final next = _nextEvent;
    if (!hasRange && prev == null && next == null) {
      return const SizedBox.shrink();
    }
    String fmt(int y) => y < 0 ? 'B.C. ${-y}' : 'A.D. $y';
    String? fmtRange(int? a, int? b) {
      if (a == null && b == null) return null;
      if (a == b && a != null) return fmt(a);
      return '${a != null ? fmt(a) : '?'} ~ ${b != null ? fmt(b) : '?'}';
    }

    String? eventYearLabel(StoryEvent? ev) {
      if (ev == null) return null;
      return fmtRange(ev.startYear, ev.endYear);
    }

    final rangeLabel = fmtRange(
      starts.isEmpty ? null : starts.reduce((a, b) => a < b ? a : b),
      ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rangeLabel != null)
            Text(
              '• 선택된 인물의 기존 사건 연도 범위: $rangeLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (prev != null)
            Text(
              '• 이전 이야기: "${prev.title}"'
              '${eventYearLabel(prev) != null ? ' (${eventYearLabel(prev)})' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (_afterStoryIndex == null)
            Text(
              '• 이전 이야기: (맨 앞 선택 — 없음)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (next != null)
            Text(
              '• 다음 이야기: "${next.title}"'
              '${eventYearLabel(next) != null ? ' (${eventYearLabel(next)})' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              '• 다음 이야기: (이 시대의 마지막으로 배치됩니다)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  String _afterSelectionChipLabel() {
    if (_afterStoryIndex == null) {
      return '선택된 이야기: 없음 (맨 앞에 배치)';
    }
    final prev = _prevEvent;
    if (prev == null) {
      return '선택된 이야기: #${_afterStoryIndex!}';
    }
    final yr = _fmtYearRange(prev.startYear, prev.endYear);
    return yr == null
        ? '선택된 이야기: ${prev.title}'
        : '선택된 이야기: ${prev.title} ($yr)';
  }

  static String _fmtYear(int y) => y < 0 ? 'B.C. ${-y}' : 'A.D. $y';
  static String? _fmtYearRange(int? a, int? b) {
    if (a == null && b == null) return null;
    if (a == b && a != null) return _fmtYear(a);
    return '${a != null ? _fmtYear(a) : '?'} ~ ${b != null ? _fmtYear(b) : '?'}';
  }

  Widget _summaryChipRow(ThemeData theme) {
    final era = _selectedEra;
    return _SummaryBox(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (era != null)
              Chip(
                label: Text('시대: ${era.name}'),
                avatar: const Icon(Icons.access_time, size: 16),
              ),
            if (_characterCodes.isNotEmpty)
              Chip(
                label: Text(
                  '인물: ${_characterCodes.map(_displayName).join(', ')}',
                ),
                avatar: const Icon(Icons.people_alt_outlined, size: 16),
              ),
            Chip(
              label: Text(_afterSelectionChipLabel()),
              avatar: const Icon(Icons.place_outlined, size: 16),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  // ---------- Bottom Nav ----------
  Widget _buildBottomNav(ThemeData theme) {
    final isFirst = _step == 0;
    final isLast = _step == 4;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: isFirst ? null : _onPrev,
            icon: const Icon(Icons.chevron_left),
            label: const Text('이전'),
          ),
          const Spacer(),
          if (!isLast)
            FilledButton.icon(
              onPressed: _canGoNext ? _onNext : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('다음'),
            ),
        ],
      ),
    );
  }
}

// ============ sub widgets ============

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});
  final int step;

  static const _labels = ['제안 안내', '시대', '등장인물과 위치', '세부 내용', '퀴즈'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: step == i
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${i + 1}. ${_labels[i]}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: step == i
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: step == i ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (i < _labels.length - 1)
                Container(
                  width: 12,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: theme.dividerColor,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EraCard extends StatelessWidget {
  const _EraCard({
    required this.index,
    required this.era,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final Era era;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 1.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.secondaryContainer,
                ),
                child: Text(
                  '$index',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(era.name, style: theme.textTheme.titleSmall),
                    if (era.startYear != null || era.endYear != null)
                      Text(
                        _yearRange(era),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  String _yearRange(Era era) {
    String fmt(int? y) {
      if (y == null) return '?';
      return y < 0 ? 'B.C. ${-y}' : 'A.D. $y';
    }

    return '(${fmt(era.startYear)} ~ ${fmt(era.endYear)})';
  }
}

class _CharacterLabel {
  const _CharacterLabel({required this.name, this.highlighted = false});
  final String name;
  final bool highlighted;
}

class _InsertionCard extends StatelessWidget {
  const _InsertionCard({
    required this.title,
    required this.subtitle,
    this.characterLabels,
    this.storyIndex,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<_CharacterLabel>? characterLabels;
  final int? storyIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? highlight.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? highlight : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (storyIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: Text(
                      '#$storyIndex',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (characterLabels != null &&
                          characterLabels!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final l in characterLabels!)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: l.highlighted
                                      ? highlight.withValues(alpha: 0.18)
                                      : theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: l.highlighted
                                        ? highlight.withValues(alpha: 0.6)
                                        : theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  l.name,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: l.highlighted
                                        ? highlight
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: l.highlighted
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: highlight, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _IntroBullet extends StatelessWidget {
  const _IntroBullet({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondaryContainer,
            ),
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrEmptyExt on Iterable<String> {
  String firstOrEmpty() => isEmpty ? '' : first;
}

/// 이미지 생성 중 전체 화면을 블록하는 모달 overlay.
///
/// AI 에 한 번에 한 장만 보낼 수 있으므로 생성이 돌아가는 동안 사용자가 다른
/// 장면 생성을 시도하지 못하도록 입력 이벤트를 흡수한다. `AbsorbPointer` +
/// 반투명 배경 + 중앙 안내 카드.
class _GeneratingImageOverlay extends StatelessWidget {
  const _GeneratingImageOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(strokeWidth: 3.5),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'AI 가 그림을 생성중입니다',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '한 번에 한 장만 생성할 수 있어요. 잠시만 기다려주세요. '
                        '완료되면 자동으로 다음 작업을 할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
