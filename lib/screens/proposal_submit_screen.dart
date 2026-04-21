import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';
import '../models/event_proposal.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../widgets/proposal/bible_refs_picker.dart';
import '../widgets/proposal/person_codes_picker.dart';
import '../widgets/proposal/scene_persons_grid.dart';

/// 이야기 제안 등록/수정 폼. 사역자(is_pastor)만 진입하도록 상위에서 게이트한다.
///
/// [existing] 이 주어지면 수정 모드 (status=pending 인 본인 제안만 가능).
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
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _startYearCtrl = TextEditingController();
  final _endYearCtrl = TextEditingController();
  final _afterIndexCtrl = TextEditingController();
  final List<TextEditingController> _sceneCtrls = List.generate(
    4,
    (_) => TextEditingController(),
  );

  String? _eraId;
  String _timePrecision = 'approx';
  List<String> _personCodes = const [];
  List<Map<String, String>> _bibleRefs = const [];
  List<List<String>> _scenePersons = const [[], [], [], []];

  List<Era> _eras = const [];
  List<PersonOption> _personOptions = const [];
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _eraId = existing.eraId;
      _titleCtrl.text = existing.title;
      _summaryCtrl.text = existing.summary ?? '';
      _placeCtrl.text = existing.placeName ?? '';
      _latCtrl.text = existing.lat?.toString() ?? '';
      _lngCtrl.text = existing.lng?.toString() ?? '';
      _startYearCtrl.text = existing.startYear?.toString() ?? '';
      _endYearCtrl.text = existing.endYear?.toString() ?? '';
      _afterIndexCtrl.text = existing.afterStoryIndex?.toString() ?? '';
      _timePrecision = existing.timePrecision;
      _personCodes = List.of(existing.personCodes);
      _bibleRefs = existing.bibleRefs
          .map<Map<String, String>>(
            (m) => m.map((k, v) => MapEntry(k, v?.toString() ?? '')),
          )
          .toList();
      for (
        var i = 0;
        i < _sceneCtrls.length && i < existing.storyScenes.length;
        i++
      ) {
        _sceneCtrls[i].text = existing.storyScenes[i];
      }
      _scenePersons = List.generate(
        4,
        (i) => i < existing.scenePersons.length
            ? List.of(existing.scenePersons[i])
            : const [],
      );
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _placeCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _startYearCtrl.dispose();
    _endYearCtrl.dispose();
    _afterIndexCtrl.dispose();
    for (final c in _sceneCtrls) {
      c.dispose();
    }
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
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final repo = ref.read(proposalRepositoryProvider);
    final scenes = _sceneCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final refsAsDynamic = _bibleRefs
        .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
        .toList();

    try {
      if (widget.existing == null) {
        await repo.submit(
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _summaryCtrl.text.trim().isEmpty
              ? null
              : _summaryCtrl.text.trim(),
          personCodes: _personCodes,
          placeName: _placeCtrl.text.trim().isEmpty
              ? null
              : _placeCtrl.text.trim(),
          lat: double.tryParse(_latCtrl.text.trim()),
          lng: double.tryParse(_lngCtrl.text.trim()),
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: _bibleRefs,
          storyScenes: scenes,
          scenePersons: _scenePersons,
          afterStoryIndex: int.tryParse(_afterIndexCtrl.text.trim()),
        );
      } else {
        await repo.updateProposal(
          proposalId: widget.existing!.id,
          eraId: _eraId!,
          title: _titleCtrl.text.trim(),
          summary: _summaryCtrl.text.trim().isEmpty
              ? null
              : _summaryCtrl.text.trim(),
          personCodes: _personCodes,
          placeName: _placeCtrl.text.trim().isEmpty
              ? null
              : _placeCtrl.text.trim(),
          lat: double.tryParse(_latCtrl.text.trim()),
          lng: double.tryParse(_lngCtrl.text.trim()),
          startYear: int.tryParse(_startYearCtrl.text.trim()),
          endYear: int.tryParse(_endYearCtrl.text.trim()),
          timePrecision: _timePrecision,
          bibleRefs: refsAsDynamic,
          storyScenes: scenes,
          scenePersons: _scenePersons,
          afterStoryIndex: int.tryParse(_afterIndexCtrl.text.trim()),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingOptions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
              _sectionTitle('시대'),
              DropdownButtonFormField<String>(
                value: _eraId,
                items: [
                  for (final e in _eras)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => _eraId = v),
                validator: (v) => v == null ? '시대를 선택해주세요' : null,
              ),
              _sectionTitle('이 이야기 다음 위치에 배치 (선택)'),
              TextFormField(
                controller: _afterIndexCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '기존 이야기의 story_index. 비우면 맨 앞.',
                ),
              ),
              _sectionTitle('제목'),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '예: 001 창조: 7일과 안식',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '제목은 필수' : null,
              ),
              _sectionTitle('요약'),
              TextFormField(
                controller: _summaryCtrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: '한두 문장으로 요약'),
              ),
              _sectionTitle('등장 인물 코드'),
              PersonCodesPicker(
                available: _personOptions,
                initial: _personCodes,
                onChanged: (codes) => setState(() => _personCodes = codes),
              ),
              _sectionTitle('장소'),
              TextFormField(
                controller: _placeCtrl,
                decoration: const InputDecoration(hintText: '예: 베들레헴'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: '위도 lat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: '경도 lng'),
                    ),
                  ),
                ],
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
              _sectionTitle('4장면 (각 한두 문장)'),
              for (var i = 0; i < _sceneCtrls.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextFormField(
                    controller: _sceneCtrls[i],
                    maxLines: 2,
                    decoration: InputDecoration(labelText: '장면 ${i + 1}'),
                  ),
                ),
              ],
              _sectionTitle('장면별 등장 인물'),
              ScenePersonsGrid(
                personCodes: _personCodes,
                sceneCount: 4,
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
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
