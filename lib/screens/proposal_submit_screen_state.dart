part of 'proposal_submit_screen.dart';

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
  final _backgroundContextCtrl = TextEditingController();
  final _startYearCtrl = TextEditingController();
  final _endYearCtrl = TextEditingController();
  final _unitCodeCtrl = TextEditingController(text: 'default');
  final _unitTitleCtrl = TextEditingController(text: '전체 흐름');
  final _unitOrderCtrl = TextEditingController(text: '1');
  String _timePrecision = 'approx';

  /// v2 위치 모델 — landmarks.id (region/anchor/minor 중 하나) FK.
  /// 새 이야기 제안 시 반드시 한 개를 골라야 한다.
  String? _landmarkId;
  List<Landmark> _landmarks = const [];
  List<Map<String, String>> _bibleRefs = const [];
  List<String> _scenes = const [''];
  List<String> _sceneCaptions = const [''];
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
      // 기존 after_story_index 를 복원한다. null 은 "맨 앞"이라는 유효한 선택이므로
      // 수정 모드에서는 항상 positionPicked 로 취급한다.
      _afterStoryIndex = e.afterStoryIndex;
      _positionPicked = true;
      _landmarkId = e.landmarkId;
      _timePrecision = e.timePrecision;
      _titleCtrl.text = e.title;
      _summaryCtrl.text = e.summary ?? '';
      _backgroundContextCtrl.text = e.backgroundContext ?? '';
      _startYearCtrl.text = e.startYear?.toString() ?? '';
      _endYearCtrl.text = e.endYear?.toString() ?? '';
      _unitCodeCtrl.text = e.unitCode;
      _unitTitleCtrl.text = e.unitTitle;
      _unitOrderCtrl.text = e.unitOrder.toString();
      _bibleRefs = e.bibleRefs
          .map<Map<String, String>>(
            (m) => m.map((k, v) => MapEntry(k, v?.toString() ?? '')),
          )
          .toList();
      _scenes = e.storyScenes.isEmpty ? [''] : List.of(e.storyScenes);
      _sceneCaptions = List.generate(
        _scenes.length,
        (i) => i < e.sceneCaptions.length ? e.sceneCaptions[i] : '',
      );
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
    _backgroundContextCtrl.addListener(_onFormChanged);
    _startYearCtrl.addListener(_onFormChanged);
    _endYearCtrl.addListener(_onFormChanged);
    _unitCodeCtrl.addListener(_onFormChanged);
    _unitTitleCtrl.addListener(_onFormChanged);
    _unitOrderCtrl.addListener(_onFormChanged);
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
    _backgroundContextCtrl.removeListener(_onFormChanged);
    _startYearCtrl.removeListener(_onFormChanged);
    _endYearCtrl.removeListener(_onFormChanged);
    _unitCodeCtrl.removeListener(_onFormChanged);
    _unitTitleCtrl.removeListener(_onFormChanged);
    _unitOrderCtrl.removeListener(_onFormChanged);
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _backgroundContextCtrl.dispose();
    _startYearCtrl.dispose();
    _endYearCtrl.dispose();
    _unitCodeCtrl.dispose();
    _unitTitleCtrl.dispose();
    _unitOrderCtrl.dispose();
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
      final landmarks = await ref
          .read(storyRepositoryProvider)
          .fetchLandmarks();
      if (!mounted) return;
      setState(() {
        _eras = eras;
        _landmarks = landmarks;
        _characterOptions = characterRows
            .map<CharacterOption>(
              (row) => CharacterOption(
                code: row['code'] as String,
                name: localizedCharacterName(
                  code: row['code'] as String,
                  name: row['name'] as String?,
                ),
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
    if (_backgroundContextCtrl.text.trim().isEmpty) return false;
    if (_unitCodeCtrl.text.trim().isEmpty) return false;
    if (_unitTitleCtrl.text.trim().isEmpty) return false;
    if (int.tryParse(_unitOrderCtrl.text.trim()) == null) return false;
    // v2 위치 모델 — landmark 한 개 필수.
    if (_landmarkId == null) return false;
    // 연도: 시작/끝 둘 다 정수 + 끝 ≥ 시작
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null || ey == null) return false;
    if (ey < sy) return false;
    final prev = _prevEvent;
    if (prev != null && prev.endYear != null && sy < prev.endYear!) {
      return false;
    }
    final next = _nextEvent;
    if (next != null && next.startYear != null && ey > next.startYear!) {
      return false;
    }
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
      if (i >= _sceneCaptions.length || _sceneCaptions[i].trim().isEmpty) {
        return false;
      }
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

  /// Step 3 에서 아직 채워지지 않은 필수 항목 목록 — 사용자에게 어디가 비었는지
  /// 한눈에 보여주기 위한 동적 체크리스트. setState 가 발생할 때마다 재계산되어
  /// 채워진 항목은 자동으로 사라진다.
  List<String> get _missingDetailsItems {
    final items = <String>[];
    if (_titleCtrl.text.trim().isEmpty) items.add('제목');
    if (_summaryCtrl.text.trim().isEmpty) items.add('요약');
    if (_backgroundContextCtrl.text.trim().isEmpty) items.add('배경 지식');
    if (_unitCodeCtrl.text.trim().isEmpty) items.add('시간순 구간 코드');
    if (_unitTitleCtrl.text.trim().isEmpty) items.add('시간순 구간 제목');
    if (int.tryParse(_unitOrderCtrl.text.trim()) == null) {
      items.add('시간순 구간 순서 (숫자)');
    }
    if (_landmarkId == null) items.add('지도/칩에서 위치(region/anchor/minor) 선택');
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null) items.add('시작 연도 (숫자)');
    if (ey == null) items.add('끝 연도 (숫자)');
    if (sy != null && ey != null && ey < sy) {
      items.add('끝 연도는 시작 연도와 같거나 더 뒤');
    }
    if (sy != null) {
      final prev = _prevEvent;
      if (prev != null && prev.endYear != null && sy < prev.endYear!) {
        items.add('시작 연도 ≥ 이전 이야기 끝 연도 (${prev.endYear})');
      }
    }
    if (ey != null) {
      final next = _nextEvent;
      if (next != null && next.startYear != null && ey > next.startYear!) {
        items.add('끝 연도 ≤ 다음 이야기 시작 연도 (${next.startYear})');
      }
    }
    if (_bibleRefs.isEmpty) items.add('성경 본문 1개 이상');
    final nonEmptyScenes = _scenes
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (nonEmptyScenes.isEmpty) items.add('장면 1개 이상 (텍스트)');
    for (var i = 0; i < _scenes.length; i++) {
      if (_scenes[i].trim().isEmpty) continue;
      if (i >= _sceneCaptions.length || _sceneCaptions[i].trim().isEmpty) {
        items.add('장면 ${i + 1} 사용자 캡션');
      }
      if (i >= _sceneImages.length || !_sceneImages[i].isReady) {
        items.add('장면 ${i + 1} 이미지 생성');
      }
    }
    return items;
  }

  /// 연도 입력 에러.
  /// - 끝 < 시작
  /// - 시작 < 이전 이야기 끝 연도 (= 이전보다 앞이면 안 됨, 같은 건 OK)
  /// - 끝 > 다음 이야기 시작 연도 (= 다음보다 뒤면 안 됨, 같은 건 OK)
  String? get _yearError {
    final sy = int.tryParse(_startYearCtrl.text.trim());
    final ey = int.tryParse(_endYearCtrl.text.trim());
    if (sy == null || ey == null) return null;
    if (ey < sy) return '끝 연도는 시작 연도와 같거나 더 뒤여야 합니다.';
    final prev = _prevEvent;
    if (prev != null && prev.endYear != null && sy < prev.endYear!) {
      return '시작 연도는 이전 이야기 "${prev.title}" 의 끝 연도(${prev.endYear}) 이상이어야 합니다.';
    }
    final next = _nextEvent;
    if (next != null && next.startYear != null && ey > next.startYear!) {
      return '끝 연도는 다음 이야기 "${next.title}" 의 시작 연도(${next.startYear}) 이하여야 합니다.';
    }
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
  ///
  /// fallback: 결과가 빈 배열이면 (= 신규 인물 단독 케이스, 선택 인물이 등장하는
  /// 기존 이야기가 0개) era 의 전체 events 를 반환. 사역자가 시대 흐름 기준으로
  /// 어느 위치에 끼울지 직접 고를 수 있게.
  List<StoryEvent> _eventsForPositionList() {
    if (_characterCodes.isEmpty) return const [];
    final selected = _characterCodes.toSet();
    final highlighted = _eraEvents
        .where((e) => e.characterCodes.any(selected.contains))
        .toList();
    if (highlighted.isNotEmpty) return highlighted;
    return List<StoryEvent>.from(_eraEvents);
  }

  /// position list 가 fallback (= 선택 인물이 등장하는 기존 이야기가 없어 era
  /// 전체를 보여주는 모드) 인지. UI 의 안내 문구 분기에 사용.
  bool get _isPositionListFallback {
    if (_characterCodes.isEmpty) return false;
    final selected = _characterCodes.toSet();
    final hasAnyMatch = _eraEvents.any(
      (e) => e.characterCodes.any(selected.contains),
    );
    return !hasAnyMatch && _eraEvents.isNotEmpty;
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
    final unitOrder = int.tryParse(_unitOrderCtrl.text.trim());
    if (unitOrder == null) {
      setState(() => _errorText = '시간순 구간 순서는 숫자로 입력해주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final repo = ref.read(proposalRepositoryProvider);
    // scenes 에 해당하는 (비어있지 않은) 인덱스만 골라 이미지/프롬프트 배열 재구성.
    final paddedSceneCharacters = <List<String>>[];
    final sceneCaptions = <String>[];
    final sceneImagePaths = <String>[];
    final sceneImagePrompts = <String>[];
    for (var i = 0; i < _scenes.length; i++) {
      if (_scenes[i].trim().isEmpty) continue;
      sceneCaptions.add(
        i < _sceneCaptions.length ? _sceneCaptions[i].trim() : '',
      );
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
          backgroundContext: _emptyAsNull(_backgroundContextCtrl.text),
          characterCodes: _characterCodes,
          landmarkId: _landmarkId!,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: _bibleRefs,
          storyScenes: scenes,
          sceneCaptions: sceneCaptions,
          sceneCharacters: paddedSceneCharacters,
          unitCode: _unitCodeCtrl.text.trim(),
          unitTitle: _unitTitleCtrl.text.trim(),
          unitOrder: unitOrder,
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
          backgroundContext: _emptyAsNull(_backgroundContextCtrl.text),
          characterCodes: _characterCodes,
          landmarkId: _landmarkId!,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: refsAsDynamic,
          storyScenes: scenes,
          sceneCaptions: sceneCaptions,
          sceneCharacters: paddedSceneCharacters,
          unitCode: _unitCodeCtrl.text.trim(),
          unitTitle: _unitTitleCtrl.text.trim(),
          unitOrder: unitOrder,
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
                  body: '구약 7시대 · 신약 4시대 중 이 이야기가 속한 시대를 선택합니다.',
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
      final newChar = _newCharactersByCode[code];
      // 신규 캐릭터는 사용자가 입력한 한글 이름이 보장돼 있으므로 최우선.
      // DB fetch 가 영문 fallback 이거나 일시적으로 안 끝났을 때도 한글로 표시.
      String name = newChar?.name.trim() ?? '';
      if (name.isEmpty) {
        final opt = _characterOptions.firstWhere(
          (c) => c.code == code,
          orElse: () => CharacterOption(code: code, name: code),
        );
        name = opt.name;
      }
      final url = newChar != null
          ? repo.publicUrlForStoragePath(newChar.storagePath)
          : client.storage.from('characters').getPublicUrl('$code.png');
      return ProposalCharacterRowItem(code: code, name: name, avatarUrl: url);
    }).toList();
  }

  /// `ProposalScenesEditor.onGenerate` 콜백 — Edge Function 에 1장 생성 요청.
  /// 전역 `_generatingImage` 플래그로 다른 버튼을 블록.
  Future<ProposalSceneImage?> _onGenerateSceneImage(
    int sceneIndex,
    String sceneText,
    List<String> sceneCharacterCodes,
  ) async {
    if (_generatingImage) return null;
    setState(() {
      _generatingImage = true;
      _generatingSceneIndex = sceneIndex;
      _errorText = null;
    });
    try {
      final repo = ref.read(proposalRepositoryProvider);
      // 이 장면에 v 표시한 인물만 reference 로 전달 → AI 가 그 인물의 아바타와
      // 이름만 받아 일관성 있게 그릴 수 있다.
      final result = await repo.generateProposalScene(
        sceneText: sceneText,
        characterCodes: sceneCharacterCodes,
        draftId: _draftId,
        sceneIndex: sceneIndex,
        eventTitle: _titleCtrl.text.trim().isEmpty
            ? null
            : _titleCtrl.text.trim(),
        placeName: _selectedLandmark?.name,
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
            _isPositionListFallback
                ? '선택한 인물이 등장하는 기존 이야기가 없어 이 시대의 모든 이야기를 '
                      '보여드립니다. 시대 흐름상 어느 이야기 "뒤"에 들어갈지 골라주세요. '
                      '맨 앞도 선택 가능합니다.'
                : '선택한 등장인물들이 나오는 이야기들이 시대 순서대로 나열됩니다. '
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
                              '이 시대에 등록된 이야기가 아직 없습니다. "맨 앞" 선택만 가능합니다.',
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
        _sectionTitle('배경 지식'),
        TextField(
          controller: _backgroundContextCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '시대 배경과 이 사건이 무엇을 다루는지 1~2문장으로 적어주세요.',
          ),
        ),
        _sectionTitle('장소'),
        // 좌우 2-col: col1 = 장소 이름 입력 + 좌표 안내, col2 = 지도 (위아래로 더 큼)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오른쪽 지도/칩에서 위치를 선택하세요.\n반드시 region 1개는 골라야 합니다.\n해당 region 의 anchor/minor 점도 선택할 수 있습니다.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedLandmark != null)
                      Text(
                        '선택: ${_selectedLandmark!.name}\n'
                        '(${_selectedLandmark!.kind})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else
                      Text(
                        '아직 위치 미선택',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ProposalLocationPicker(
                  eraLandmarks: _landmarksForSelectedEra(),
                  initialLandmarkId: _landmarkId,
                  referencePins: _referencePinsForSelectedCharacters(),
                  height: 420,
                  onChanged: (id) => setState(() => _landmarkId = id),
                ),
              ),
            ],
          ),
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
        _sectionTitle('시간순 구간'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _unitCodeCtrl,
                decoration: const InputDecoration(
                  labelText: '구간 코드',
                  hintText: '예: div_elijah',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _unitTitleCtrl,
                decoration: const InputDecoration(
                  labelText: '구간 제목',
                  hintText: '예: 엘리야와 엘리사',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _unitOrderCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                ),
                decoration: const InputDecoration(labelText: '순서'),
              ),
            ),
          ],
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
          initialSceneCharacters: _sceneCharacters,
          availableCharacterCodes: _characterCodes,
          characterNameByCode: {
            for (final opt in _characterOptions) opt.code: opt.name,
            // 신규 캐릭터의 사용자 한글 이름이 항상 우선 (DB lookup 결과 덮어씀).
            for (final c in _newCharactersByCode.values)
              if (c.name.trim().isNotEmpty) c.code: c.name,
          },
          busy: _generatingImage,
          busySceneIndex: _generatingSceneIndex,
          publicUrlForPath: (path) => ref
              .read(proposalRepositoryProvider)
              .publicUrlForProposalScene(path),
          onChanged: (scenes, images, sceneCharacters) => setState(() {
            _scenes = scenes;
            _sceneCaptions = List.generate(
              scenes.length,
              (i) => i < _sceneCaptions.length ? _sceneCaptions[i] : '',
            );
            _sceneCharacters = sceneCharacters;
            _sceneImages = List.generate(
              scenes.length,
              (i) => i < images.length ? images[i] : const ProposalSceneImage(),
            );
          }),
          onGenerate: _onGenerateSceneImage,
        ),
        const SizedBox(height: 12),
        _buildSceneCaptionsEditor(theme),
        const SizedBox(height: 24),
        _missingDetailsChecklist(theme),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSceneCaptionsEditor(ThemeData theme) {
    final editableIndexes = <int>[
      for (var i = 0; i < _scenes.length; i++)
        if (_scenes[i].trim().isNotEmpty) i,
    ];
    if (editableIndexes.isEmpty) {
      return Text(
        '장면을 입력하면 사용자에게 보일 장면 캡션을 추가할 수 있어요.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('장면 캡션 (사용자 표시용)'),
        for (final i in editableIndexes) ...[
          if (i != editableIndexes.first) const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('scene-caption-$i-${_scenes[i].hashCode}'),
            initialValue: i < _sceneCaptions.length ? _sceneCaptions[i] : '',
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: '장면 ${i + 1} 캡션',
              hintText: '이미지 아래에 짧게 보일 설명',
            ),
            onChanged: (value) => setState(() {
              final next = List<String>.of(_sceneCaptions);
              while (next.length <= i) {
                next.add('');
              }
              next[i] = value;
              _sceneCaptions = next;
            }),
          ),
        ],
      ],
    );
  }

  /// Step 3 하단의 동적 누락 항목 체크리스트.
  /// - 채워야 할 게 있으면 노란 박스 + 항목 리스트 (체크박스 빈 칸 아이콘)
  /// - 모두 채워지면 초록 박스 "모든 항목 완료 — 다음으로 이동 가능"
  Widget _missingDetailsChecklist(ThemeData theme) {
    final missing = _missingDetailsItems;
    if (missing.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F3DE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF7FB07B)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF2D7B4D), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '모든 필수 항목 완료 — 하단 "다음" 버튼으로 이동할 수 있어요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF2D7B4D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9A536)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFB07A1A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"다음" 버튼을 활성화하려면 아래 ${missing.length}개 항목을 채워주세요',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B4A14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_box_outline_blank,
                      color: Color(0xFFB07A1A),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B4A14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Step 4: 퀴즈 + 제출 ----------
  Widget _buildStep4Quiz(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '이야기를 읽은 사람이 풀 퀴즈를 1~3개 만들어주세요. 4번 보기는 승인 시 자동으로 붙습니다.',
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
              '문제·선택지 3개·해설을 모두 채우면 제출 버튼이 활성화됩니다.',
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

  /// 현재 시대(era)에 노출되는 landmarks 만 picker 로 넘긴다.
  /// 시대 코드가 era_codes 배열에 포함된 region/anchor/minor 만 통과.
  List<Landmark> _landmarksForSelectedEra() {
    final eraCode = _selectedEraCode;
    if (eraCode == null) return _landmarks;
    return _landmarks
        .where((lm) => lm.eraCodes.isEmpty || lm.eraCodes.contains(eraCode))
        .toList(growable: false);
  }

  String? get _selectedEraCode {
    if (_eraId == null) return null;
    final match = _eras.where((e) => e.id == _eraId);
    return match.isEmpty ? null : match.first.code;
  }

  Landmark? get _selectedLandmark {
    if (_landmarkId == null) return null;
    for (final lm in _landmarks) {
      if (lm.id == _landmarkId) return lm;
    }
    return null;
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
