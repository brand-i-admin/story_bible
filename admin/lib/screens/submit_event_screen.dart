import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/era.dart';
import '../state/admin_providers.dart';
import '../widgets/bible_refs_picker.dart';
import '../widgets/person_codes_picker.dart';
import '../widgets/scene_persons_grid.dart';

/// 관리자가 새 이야기를 등록한다.
///
/// 핵심 단계:
/// 1) era 선택 → 같은 era 의 published 이야기 슬롯 자동 로드
/// 2) "이 다음에" 슬롯 선택 → afterStoryIndex 결정 (DB RPC가 +1 시프트)
/// 3) 지도 클릭으로 lat/lng 자동
/// 4) 인물 코드: 자동완성 + 자유 입력 (PersonCodesPicker)
/// 5) 성경 본문: book dropdown + chapter:verse from/to (BibleRefsPicker)
/// 6) 4 scene 텍스트 + scene_persons 체크박스 (ScenePersonsGrid)
/// 7) 제출 → RPC 내부에서 status='published' 로 강제 등록
class SubmitEventScreen extends ConsumerStatefulWidget {
  const SubmitEventScreen({super.key});

  @override
  ConsumerState<SubmitEventScreen> createState() => _SubmitEventScreenState();
}

class _SubmitEventScreenState extends ConsumerState<SubmitEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _placeNameCtrl = TextEditingController();
  final _startYearCtrl = TextEditingController();
  final _endYearCtrl = TextEditingController();
  final _scenes = List.generate(4, (_) => TextEditingController());

  Era? _selectedEra;
  List<Era> _eras = const [];
  List<({int storyIndex, String title})> _slots = const [];
  ({int storyIndex, String title})? _afterSlot;
  LatLng? _picked;

  List<PersonOption> _personOptions = const [];
  List<String> _personCodes = const [];
  List<List<String>> _scenePersons = List.generate(4, (_) => const <String>[]);
  List<Map<String, String>> _bibleRefs = const [];

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    for (final ctrl in _scenes) {
      ctrl.addListener(() => setState(() {})); // 장면 텍스트 채워질 때 grid 라벨도 즉시
    }
  }

  Future<void> _loadInitial() async {
    final repo = ref.read(adminRepositoryProvider);
    final eras = await repo.fetchEras();
    final persons = await repo.fetchPersons();
    if (!mounted) return;
    setState(() {
      _eras = eras;
      _personOptions = persons
          .map((p) => PersonOption(code: p.code, name: p.name))
          .toList();
    });
  }

  Future<void> _onEraChanged(Era? era) async {
    if (era == null) return;
    setState(() {
      _selectedEra = era;
      _afterSlot = null;
      _slots = const [];
    });
    final slots = await ref
        .read(adminRepositoryProvider)
        .fetchPublishedSlots(era.id);
    if (!mounted) return;
    setState(() => _slots = slots);
  }

  Future<void> _submit() async {
    if (_selectedEra == null) {
      setState(() => _error = 'era 를 선택해 주세요');
      return;
    }
    if (_picked == null) {
      setState(() => _error = '지도에서 좌표를 클릭해 주세요');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final scenesText = _scenes
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final newId = await ref
          .read(adminRepositoryProvider)
          .submitEvent(
            eraCode: _selectedEra!.code,
            afterStoryIndex: _afterSlot?.storyIndex,
            title: _titleCtrl.text.trim(),
            summary: _summaryCtrl.text.trim(),
            storyScenes: scenesText,
            scenePersons: _scenePersons.take(scenesText.length).toList(),
            personCodes: _personCodes,
            bibleRefs: _bibleRefs,
            startYear: int.tryParse(_startYearCtrl.text.trim()),
            endYear: int.tryParse(_endYearCtrl.text.trim()),
            timePrecision: 'approx',
            placeName: _placeNameCtrl.text.trim(),
            lat: _picked!.latitude,
            lng: _picked!.longitude,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('등록 완료: $newId')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filledScenes = _scenes
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .length;
    final sceneCount = filledScenes == 0 ? 4 : filledScenes;

    return Scaffold(
      appBar: AppBar(title: const Text('새 이야기 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<Era>(
              value: _selectedEra,
              decoration: const InputDecoration(labelText: '시대 (era)'),
              items: _eras
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                  .toList(),
              onChanged: _onEraChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<({int storyIndex, String title})?>(
              value: _afterSlot,
              decoration: const InputDecoration(
                labelText: '이 이야기 다음에 배치 (선택)',
                helperText: '비워두면 era 맨 앞에 끼워 넣습니다',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('— 맨 앞 —')),
                ..._slots.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      '${s.storyIndex}. ${s.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _afterSlot = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '제목 (예: "216 새 이야기 제목")',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '필수' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _summaryCtrl,
              decoration: const InputDecoration(labelText: '요약 (1~2 문장)'),
              maxLines: 2,
              validator: (v) => v == null || v.trim().isEmpty ? '필수' : null,
            ),
            const SizedBox(height: 16),
            const Text('등장인물 코드'),
            const SizedBox(height: 4),
            PersonCodesPicker(
              available: _personOptions,
              initial: const [],
              onChanged: (v) => setState(() => _personCodes = v),
            ),
            const SizedBox(height: 16),
            const Text('성경 본문'),
            const SizedBox(height: 4),
            BibleRefsPicker(
              initial: const [],
              onChanged: (v) => setState(() => _bibleRefs = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startYearCtrl,
                    decoration: const InputDecoration(labelText: 'start_year'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endYearCtrl,
                    decoration: const InputDecoration(labelText: 'end_year'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _placeNameCtrl,
              decoration: const InputDecoration(labelText: '장소명'),
            ),
            const SizedBox(height: 8),
            const Text('지도에서 좌표 선택 (탭) :'),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _picked ?? const LatLng(31.78, 35.22),
                  initialZoom: 4.5,
                  onTap: (tapPos, latlng) => setState(() => _picked = latlng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.brandi.story_bible_admin',
                  ),
                  if (_picked != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _picked!,
                          width: 28,
                          height: 28,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_picked != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'lat=${_picked!.latitude.toStringAsFixed(4)}, '
                  'lng=${_picked!.longitude.toStringAsFixed(4)}',
                ),
              ),
            const SizedBox(height: 16),
            const Text('4개 장면 (시각 묘사 위주, 대사 X)'),
            const SizedBox(height: 4),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextFormField(
                  controller: _scenes[i],
                  decoration: InputDecoration(labelText: '장면 ${i + 1}'),
                  maxLines: 2,
                ),
              ),
            const SizedBox(height: 12),
            const Text('장면별 등장인물 (체크)'),
            const SizedBox(height: 4),
            ScenePersonsGrid(
              personCodes: _personCodes,
              sceneCount: sceneCount,
              initial: _scenePersons,
              onChanged: (v) => setState(() => _scenePersons = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('제출'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
