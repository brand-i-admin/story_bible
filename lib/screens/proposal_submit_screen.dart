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
  // 0: era, 1: persons & position, 2: details
  int _step = 0;

  // Step 2 내부 sub-phase. 'persons' | 'event:<index>' | 'summary'
  String _step2Phase = 'persons';

  // Selections
  String _testament = 'old';
  String? _eraId;
  List<String> _personCodes = const [];
  // 인물별 '이 사건 뒤에' 선택 — storyIndex (null = 맨 앞). 인물 code → int?.
  Map<String, int?> _afterByPerson = {};

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
        _afterByPerson = {for (final c in _personCodes) c: e.afterStoryIndex};
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
      // 수정 모드는 Step 3 에서 바로 시작
      _step = 2;
    }
    _loadOptions();
  }

  @override
  void dispose() {
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

  List<Era> get _visibleEras =>
      _eras.where((e) => e.testament == _testament).toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  List<StoryEvent> get _eraEvents =>
      _eraId != null ? (_eventsByEra[_eraId!] ?? const []) : const [];

  List<StoryEvent> _eventsForPerson(String code) {
    return _eraEvents.where((e) => e.personCodes.contains(code)).toList();
  }

  Era? get _selectedEra {
    if (_eraId == null) return null;
    final match = _eras.where((e) => e.id == _eraId);
    return match.isEmpty ? null : match.first;
  }

  /// 모든 인물별 선택이 완료되었는지
  bool get _allPersonsChosePosition {
    if (_personCodes.isEmpty) return false;
    return _personCodes.every(_afterByPerson.containsKey);
  }

  /// 최종 삽입 위치 = 선택된 인물들이 고른 storyIndex 중 최댓값. 하나도 없으면 null.
  int? get _finalAfterStoryIndex {
    final picks = _afterByPerson.values.whereType<int>().toList();
    if (picks.isEmpty) return null;
    return picks.reduce((a, b) => a > b ? a : b);
  }

  // ===== Step navigation =====

  bool get _canGoNext {
    switch (_step) {
      case 0:
        return _eraId != null;
      case 1:
        switch (_step2Phase) {
          case 'persons':
            return _personCodes.isNotEmpty;
          case 'summary':
            return _allPersonsChosePosition;
          default:
            // 'event:<idx>' — 해당 인물 선택 완료 시 다음으로
            final idx = _currentEventPhaseIndex;
            if (idx == null) return false;
            final code = _personCodes[idx];
            return _afterByPerson.containsKey(code);
        }
      case 2:
        return true; // 제출 버튼이 별도
    }
    return false;
  }

  int? get _currentEventPhaseIndex {
    if (!_step2Phase.startsWith('event:')) return null;
    return int.tryParse(_step2Phase.substring('event:'.length));
  }

  void _onNext() {
    if (!_canGoNext) return;
    setState(() {
      switch (_step) {
        case 0:
          _step = 1;
          _step2Phase = 'persons';
          break;
        case 1:
          switch (_step2Phase) {
            case 'persons':
              _step2Phase = _personCodes.isEmpty ? 'summary' : 'event:0';
              break;
            case 'summary':
              _step = 2;
              break;
            default:
              final idx = _currentEventPhaseIndex!;
              if (idx + 1 < _personCodes.length) {
                _step2Phase = 'event:${idx + 1}';
              } else {
                _step2Phase = 'summary';
              }
          }
          break;
        case 2:
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
          switch (_step2Phase) {
            case 'persons':
              _step = 0;
              break;
            case 'event:0':
              _step2Phase = 'persons';
              break;
            case 'summary':
              _step2Phase = _personCodes.isEmpty
                  ? 'persons'
                  : 'event:${_personCodes.length - 1}';
              break;
            default:
              final idx = _currentEventPhaseIndex!;
              _step2Phase = idx > 0 ? 'event:${idx - 1}' : 'persons';
          }
          break;
        case 2:
          _step = 1;
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
    final afterIdx = _finalAfterStoryIndex;

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
        return _buildStep1Era(theme);
      case 1:
        switch (_step2Phase) {
          case 'persons':
            return _buildStep2Persons(theme);
          case 'summary':
            return _buildStep2Summary(theme);
          default:
            return _buildStep2Events(theme);
        }
      case 2:
        return _buildStep3Details(theme);
    }
    return const SizedBox.shrink();
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
                _afterByPerson.clear();
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
      _afterByPerson.clear();
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
        _afterByPerson.remove(code);
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

  // ---------- Step 2b~2n: 인물별 사건 선택 ----------
  Widget _buildStep2Events(ThemeData theme) {
    final idx = _currentEventPhaseIndex!;
    final code = _personCodes[idx];
    final events = _eventsForPerson(code);
    final selectedStoryIndex = _afterByPerson[code];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_displayName(code)} (${idx + 1}/${_personCodes.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${_displayName(code)} 의 어느 사건 뒤에 이 이야기가 들어가나요? 해당 사건을 탭하세요.',
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
                        subtitle: '이 인물 관점에서 첫 사건이 됩니다',
                        selected:
                            _afterByPerson.containsKey(code) &&
                            selectedStoryIndex == null,
                        onTap: () => setState(() {
                          _afterByPerson[code] = null;
                        }),
                      ),
                      if (events.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              '이 인물이 등장하는 이야기가 아직 없습니다. "맨 앞" 선택이 가능합니다.',
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
                            personCodes: e.personCodes,
                            selected: _afterByPerson[code] == e.storyIndex,
                            onTap: () => setState(() {
                              _afterByPerson[code] = e.storyIndex;
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
    final finalIdx = _finalAfterStoryIndex;
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
              Text(
                '인물별 선택',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              for (final code in _personCodes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${_displayName(code)} → ${_labelForPersonSelection(code)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const Divider(height: 20),
              _kv(
                theme,
                '최종 삽입 위치',
                finalIdx == null
                    ? '시대의 맨 앞'
                    : '$selectedEventTitle (#$finalIdx) 뒤',
              ),
              const SizedBox(height: 4),
              Text(
                '(여러 인물이 다른 위치를 고른 경우, 가장 뒤 위치 기준으로 삽입되어 모든 선택을 만족합니다)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _labelForPersonSelection(String code) {
    if (!_afterByPerson.containsKey(code)) return '미선택';
    final idx = _afterByPerson[code];
    if (idx == null) return '맨 앞';
    final match = _eraEvents.where((e) => e.storyIndex == idx).toList();
    final title = match.isNotEmpty ? match.first.title : '#$idx';
    return '$title 뒤';
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
          onChanged: (lat, lng) => setState(() {
            _lat = lat;
            _lng = lng;
          }),
        ),
        _sectionTitle('연도'),
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
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _onSubmit,
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
              label: Text(
                _finalAfterStoryIndex == null
                    ? '위치: 맨 앞'
                    : '위치: #${_finalAfterStoryIndex!} 뒤',
              ),
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
    final isLast = _step == 2;
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

  static const _labels = ['시대 선택', '등장인물과 위치', '세부 내용'];

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

class _InsertionCard extends StatelessWidget {
  const _InsertionCard({
    required this.title,
    required this.subtitle,
    this.personCodes,
    this.storyIndex,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<String>? personCodes;
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

extension _FirstOrEmptyExt on Iterable<String> {
  String firstOrEmpty() => isEmpty ? '' : first;
}
