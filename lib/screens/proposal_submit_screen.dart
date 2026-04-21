import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/event_proposal.dart';
import '../models/story_event.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../widgets/proposal/bible_refs_picker.dart';
import '../widgets/proposal/person_codes_picker.dart';
import '../widgets/proposal/proposal_location_picker.dart';
import '../widgets/proposal/proposal_scenes_editor.dart';
import '../widgets/proposal/scene_persons_grid.dart';

/// 이야기 제안 등록/수정 폼 (wizard).
///
/// 홈 UI 톤으로 3 단계:
///   Step 1. 시대 선택 (구약/신약 탭 + era 카드 그리드)
///   Step 2. 등장인물과 위치 선택
///           sub-phase: persons(복수) → event:0 → event:1 → ... → summary
///   Step 3. 세부 내용 (제목 / 요약 / 장소(지도) / 연도 / 성경 / 장면)
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
  // 0: intro, 1: era, 2: persons & position, 3: details
  int _step = 0;

  // Step 2 내부 sub-phase. 'persons' | 'event:<index>' | 'summary'
  String _step2Phase = 'persons';

  // Selections
  String _testament = 'old';
  String? _eraId;
  List<String> _personCodes = const [];
  // 최종 삽입 위치. null = 맨 앞 또는 미선택 — _positionPicked 로 구분.
  int? _afterStoryIndex;
  bool _positionPicked = false;

  // Options loaded once
  List<Era> _eras = const [];
  List<PersonOption> _personOptions = const [];
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
  List<List<String>> _scenePersons = const [[]];

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
      _personCodes = List.of(e.personCodes);
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
      _scenePersons = List.generate(
        _scenes.length,
        (i) => i < e.scenePersons.length
            ? List<String>.of(e.scenePersons[i])
            : <String>[],
      );
      // 수정 모드는 Step 3 (details) 에서 바로 시작
      _step = 3;
    }
    // 텍스트 필드 변경 시 제출 버튼 활성화 여부 재평가.
    _titleCtrl.addListener(_onFormChanged);
    _summaryCtrl.addListener(_onFormChanged);
    _placeCtrl.addListener(_onFormChanged);
    _startYearCtrl.addListener(_onFormChanged);
    _endYearCtrl.addListener(_onFormChanged);
    _loadOptions();
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
      final personRows = await client
          .from('persons')
          .select('code, name')
          .order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _eras = eras;
        _personOptions = personRows
            .map<PersonOption>(
              (row) => PersonOption(
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

  /// 제출 버튼 활성화 조건 — 필수 필드가 모두 채워졌는지.
  /// (시대/등장인물/삽입 위치 는 Step 2 에서 이미 확정된 상태로 Step 3 에 옴)
  /// 선택 사항: 장면별 등장 인물.
  bool get _canSubmit {
    if (_titleCtrl.text.trim().isEmpty) return false;
    if (_summaryCtrl.text.trim().isEmpty) return false;
    // 장소: 이름 + 지도 좌표 모두 필수
    if (_placeCtrl.text.trim().isEmpty) return false;
    if (_lat == null || _lng == null) return false;
    // 연도: 시작/끝 둘 다 정수로 파싱 가능해야
    if (int.tryParse(_startYearCtrl.text.trim()) == null) return false;
    if (int.tryParse(_endYearCtrl.text.trim()) == null) return false;
    // 성경 본문: 최소 1개
    if (_bibleRefs.isEmpty) return false;
    // 장면: trim 후 non-empty 가 최소 1개
    final nonEmptyScenes = _scenes
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (nonEmptyScenes.isEmpty) return false;
    return true;
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
    if (_personCodes.isEmpty) return const [];
    final selected = _personCodes.toSet();
    return _eraEvents
        .where((e) => e.personCodes.any(selected.contains))
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
          case 'persons':
            return _personCodes.isNotEmpty;
          case 'position':
            return _positionPicked;
          case 'summary':
            return _positionPicked;
          default:
            return false;
        }
      case 3:
        return true; // 제출 버튼이 별도
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
          _step2Phase = 'persons';
          break;
        case 2:
          switch (_step2Phase) {
            case 'persons':
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
          // details step 은 제출 버튼으로
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
            case 'persons':
              _step = 1;
              break;
            case 'position':
              _step2Phase = 'persons';
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
    final paddedScenePersons = List<List<String>>.generate(
      scenes.length,
      (i) => i < _scenePersons.length ? _scenePersons[i] : const [],
    );
    final refsAsDynamic = _bibleRefs
        .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
        .toList();
    final afterIdx = _afterStoryIndex;

    try {
      if (widget.existing == null) {
        await repo.submit(
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _emptyAsNull(_summaryCtrl.text),
          personCodes: _personCodes,
          placeName: _emptyAsNull(_placeCtrl.text),
          lat: _lat,
          lng: _lng,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: _bibleRefs,
          storyScenes: scenes,
          scenePersons: paddedScenePersons,
          afterStoryIndex: afterIdx,
        );
      } else {
        await repo.updateProposal(
          proposalId: widget.existing!.id,
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _emptyAsNull(_summaryCtrl.text),
          personCodes: _personCodes,
          placeName: _emptyAsNull(_placeCtrl.text),
          lat: _lat,
          lng: _lng,
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: refsAsDynamic,
          storyScenes: scenes,
          scenePersons: paddedScenePersons,
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
      body: SafeArea(
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
          case 'persons':
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
      for (final ev in _eraEvents) ...ev.personCodes,
    };
    final sorted = <PersonOption>[];
    final later = <PersonOption>[];
    for (final opt in _personOptions) {
      if (presentCodes.contains(opt.code)) {
        sorted.add(opt);
      } else {
        later.add(opt);
      }
    }
    sorted.sort((a, b) => a.name.compareTo(b.name));
    later.sort((a, b) => a.name.compareTo(b.name));
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
            '복수 선택 가능. 다음 단계에서 각 인물별로 이 이야기가 어느 사건 뒤에 들어갈지 고르게 됩니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sorted.isNotEmpty)
                    _personChipGroup(theme, '이 시대 등장 인물', sorted),
                  if (later.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _personChipGroup(theme, '전체 인물', later),
                  ],
                  const SizedBox(height: 16),
                  Text('선택 요약', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _SummaryBox(
                    children: _personCodes.isEmpty
                        ? const [Text('선택된 인물이 없습니다')]
                        : [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in _personCodes)
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

  Widget _personChipGroup(
    ThemeData theme,
    String title,
    List<PersonOption> opts,
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
                selected: _personCodes.contains(p.code),
                onSelected: (sel) => _togglePerson(p.code),
              ),
          ],
        ),
      ],
    );
  }

  void _togglePerson(String code) {
    setState(() {
      final next = List<String>.of(_personCodes);
      if (next.remove(code)) {
        // 인물 제외 시 이미 한 위치 선택이 있었으면 유지 (era 단위 선택이라 유효)
      } else {
        next.add(code);
      }
      _personCodes = next;
    });
  }

  String _displayName(String code) {
    final match = _personOptions.where((p) => p.code == code).toList();
    return match.isNotEmpty ? match.first.name : code;
  }

  // ---------- Step 2b: 통합 위치 선택 (인물 라벨 포함) ----------
  Widget _buildStep2Position(ThemeData theme) {
    final events = _eventsForPositionList();
    final selectedSet = _personCodes.toSet();
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
                            personLabels: [
                              for (final c in e.personCodes)
                                if (selectedSet.contains(c))
                                  _PersonLabel(
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
                _personCodes.isEmpty
                    ? '—'
                    : _personCodes.map(_displayName).join(', '),
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
          referencePins: _referencePinsForSelectedPersons(),
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
        ProposalScenesEditor(
          initial: _scenes,
          onChanged: (scenes) => setState(() {
            _scenes = scenes;
            _scenePersons = List.generate(
              scenes.length,
              (i) => i < _scenePersons.length
                  ? _scenePersons[i]
                  : const <String>[],
            );
          }),
        ),
        _sectionTitle('장면별 등장 인물'),
        ScenePersonsGrid(
          personCodes: _personCodes,
          sceneCount: _scenes.length,
          initial: _scenePersons,
          onChanged: (sp) => setState(() => _scenePersons = sp),
          personNameByCode: {
            for (final opt in _personOptions) opt.code: opt.name,
          },
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
        const SizedBox(height: 40),
      ],
    );
  }

  // 선택된 인물들이 등장하는 기존 이야기 좌표 — 지도 picker 에 힌트로 표시.
  // Step 2 에서 고른 '이 이야기 뒤' 의 이야기는 highlighted 로 표시해 강조.
  List<ProposalReferencePin> _referencePinsForSelectedPersons() {
    if (_personCodes.isEmpty) return const [];
    final selected = _personCodes.toSet();
    final pins = <ProposalReferencePin>[];
    for (final e in _eraEvents) {
      if (e.lat == null || e.lng == null) continue;
      final isHighlighted =
          _afterStoryIndex != null && e.storyIndex == _afterStoryIndex;
      if (isHighlighted || e.personCodes.any(selected.contains)) {
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
    if (_personCodes.isEmpty) return const SizedBox.shrink();
    final selected = _personCodes.toSet();
    final starts = <int>[];
    final ends = <int>[];
    for (final e in _eraEvents) {
      if (!e.personCodes.any(selected.contains)) continue;
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
            if (_personCodes.isNotEmpty)
              Chip(
                label: Text('인물: ${_personCodes.map(_displayName).join(', ')}'),
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
    final isLast = _step == 3;
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

  static const _labels = ['제안 안내', '시대', '등장인물과 위치', '세부 내용'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class _PersonLabel {
  const _PersonLabel({required this.name, this.highlighted = false});
  final String name;
  final bool highlighted;
}

class _InsertionCard extends StatelessWidget {
  const _InsertionCard({
    required this.title,
    required this.subtitle,
    this.personLabels,
    this.storyIndex,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<_PersonLabel>? personLabels;
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
                      if (personLabels != null && personLabels!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final l in personLabels!)
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
