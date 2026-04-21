import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/event_proposal.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../widgets/proposal/bible_refs_picker.dart';
import '../widgets/proposal/person_codes_picker.dart';
import '../widgets/proposal/proposal_insertion_picker.dart';
import '../widgets/proposal/proposal_location_picker.dart';
import '../widgets/proposal/proposal_scenes_editor.dart';
import '../widgets/proposal/scene_persons_grid.dart';

/// 이야기 제안 등록/수정 폼.
///
/// 흐름 (홈 UI 톤 유지):
/// 1) 시대 선택 (chip)
/// 2) 등장 인물 복수 선택
/// 3) 이야기 카드 리스트에서 "이 이야기 뒤" 위치 선택 (맨 앞 옵션 포함)
/// 4) 제목 / 요약 / 장소(지도 picker) / 연도 / 성경 본문 / 4장면(동적) /
///    장면별 인물
///
/// [existing] 이 주어지면 수정 모드 (본인 pending 만 RLS 허용).
class ProposalSubmitScreen extends ConsumerStatefulWidget {
  const ProposalSubmitScreen({super.key, this.existing});

  final EventProposal? existing;

  @override
  ConsumerState<ProposalSubmitScreen> createState() =>
      _ProposalSubmitScreenState();
}

class _ProposalSubmitScreenState extends ConsumerState<ProposalSubmitScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _startYearCtrl = TextEditingController();
  final _endYearCtrl = TextEditingController();

  String? _eraId;
  String _timePrecision = 'approx';
  List<String> _personCodes = const [];
  int? _afterStoryIndex;
  double? _lat;
  double? _lng;
  List<Map<String, String>> _bibleRefs = const [];
  List<String> _scenes = const [''];
  List<List<String>> _scenePersons = const [[]];

  List<Era> _eras = const [];
  List<PersonOption> _personOptions = const [];
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _eraId = e.eraId;
      _titleCtrl.text = e.title;
      _summaryCtrl.text = e.summary ?? '';
      _placeCtrl.text = e.placeName ?? '';
      _startYearCtrl.text = e.startYear?.toString() ?? '';
      _endYearCtrl.text = e.endYear?.toString() ?? '';
      _timePrecision = e.timePrecision;
      _personCodes = List.of(e.personCodes);
      _afterStoryIndex = e.afterStoryIndex;
      _lat = e.lat;
      _lng = e.lng;
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
        _eraId ??= eras.isNotEmpty ? eras.first.id : null;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _errorText = '옵션을 불러오지 못했습니다: $e';
      });
    }
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eraId == null) {
      setState(() => _errorText = '시대를 선택해주세요.');
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
    final sceneCount = scenes.length;
    final paddedScenePersons = List<List<String>>.generate(
      sceneCount,
      (i) => i < _scenePersons.length ? _scenePersons[i] : const [],
    );
    final refsAsDynamic = _bibleRefs
        .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
        .toList();

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
          afterStoryIndex: _afterStoryIndex,
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
          afterStoryIndex: _afterStoryIndex,
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_errorText != null)
                Card(
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

              // [1~3] 시대 + 인물 + 삽입 위치 (통합 위젯)
              ProposalInsertionPicker(
                eras: _eras,
                availablePersons: _personOptions,
                eventsFetcher: (eraId) =>
                    ref.read(storyRepositoryProvider).fetchEventsByEra(eraId),
                initialEraId: _eraId,
                initialPersonCodes: _personCodes,
                initialAfterStoryIndex: _afterStoryIndex,
                onEraChanged: (id) => setState(() => _eraId = id),
                onPersonCodesChanged: (codes) =>
                    setState(() => _personCodes = codes),
                onAfterStoryIndexChanged: (idx) =>
                    setState(() => _afterStoryIndex = idx),
              ),

              _sectionTitle('제목'),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(hintText: '예: 창조: 7일과 안식'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '제목은 필수입니다' : null,
              ),

              _sectionTitle('요약'),
              TextFormField(
                controller: _summaryCtrl,
                maxLines: 5,
                minLines: 2,
                decoration: const InputDecoration(hintText: '최대 4문장으로 요약'),
              ),

              _sectionTitle('장소'),
              TextFormField(
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
                    child: TextFormField(
                      controller: _startYearCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '시작 (BC는 음수)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
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
                onChanged: (v) =>
                    setState(() => _timePrecision = v ?? 'approx'),
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
          ),
        ),
      ),
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
}
