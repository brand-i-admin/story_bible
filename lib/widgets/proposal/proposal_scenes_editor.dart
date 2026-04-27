import 'package:flutter/material.dart';

import 'image_zoom_dialog.dart';

/// 장면별 생성된 이미지 상태.
/// - `path`: Storage 경로 ('proposal-scenes/...') — 성공 시에만 세팅
/// - `prompt`: Vertex 에 실제 보낸 instruction (재생성 시 참고)
/// 두 값이 모두 null 이면 아직 이 장면 이미지를 생성하지 않은 상태.
class ProposalSceneImage {
  const ProposalSceneImage({this.path, this.prompt});

  final String? path;
  final String? prompt;

  bool get isReady => path != null && path!.isNotEmpty;
}

/// 1~4장면 텍스트 + 이미지 생성 에디터.
///
/// 기존 `ProposalScenesEditor` 가 텍스트만 다뤘던 것을 확장 —
/// 각 행마다 "이미지 생성" 버튼이 있고 생성 완료된 이미지는 썸네일로 노출.
/// 이미지 재생성은 같은 버튼 재클릭.
///
/// 동시 생성 금지: 호출자(부모 화면)가 `busy=true` 를 세팅하면 모든 버튼이
/// 비활성화된다. AI 가 한 번에 여러 요청을 못 받으므로 전체 화면 modal
/// overlay 와 함께 사용.
class ProposalScenesEditor extends StatefulWidget {
  const ProposalScenesEditor({
    super.key,
    required this.initialScenes,
    required this.initialImages,
    required this.initialSceneCharacters,
    required this.availableCharacterCodes,
    required this.characterNameByCode,
    required this.onChanged,
    required this.onGenerate,
    this.busy = false,
    this.busySceneIndex,
    this.maxScenes = 4,
    this.publicUrlForPath,
  });

  final List<String> initialScenes;
  final List<ProposalSceneImage> initialImages;

  /// 장면별 선택된 등장 인물 코드 — 길이가 부족하면 빈 리스트로 채움.
  final List<List<String>> initialSceneCharacters;

  /// Step 2/3 에서 확정된 후보 인물 코드 (전체).
  final List<String> availableCharacterCodes;

  /// 코드 → 표시 이름. 새 캐릭터는 사용자가 지은 한글 이름.
  final Map<String, String> characterNameByCode;

  /// 텍스트/이미지/장면별 인물 집합이 바뀔 때 부모로 최신 스냅샷 전달.
  final void Function(
    List<String> scenes,
    List<ProposalSceneImage> images,
    List<List<String>> sceneCharacters,
  )
  onChanged;

  /// 부모가 실제 생성 로직을 수행한다 (Repository 호출).
  /// [sceneCharacterCodes] 는 이 장면에 v 표시된 인물만 — Edge Function 이
  /// 이 인물들의 아바타만 reference 로 첨부해 일관성을 보장한다.
  /// 반환된 [ProposalSceneImage] 를 해당 인덱스에 반영.
  /// 실패 시 부모는 예외를 던지거나 null 반환.
  final Future<ProposalSceneImage?> Function(
    int sceneIndex,
    String sceneText,
    List<String> sceneCharacterCodes,
  )
  onGenerate;

  final bool busy;
  final int? busySceneIndex;
  final int maxScenes;

  /// 생성된 Storage 경로 → 브라우저에서 실제 로드할 public URL 변환기.
  final String Function(String storagePath)? publicUrlForPath;

  @override
  State<ProposalScenesEditor> createState() => _ProposalScenesEditorState();
}

class _ProposalScenesEditorState extends State<ProposalScenesEditor> {
  late List<TextEditingController> _ctrls;
  late List<ProposalSceneImage> _images;
  late List<Set<String>> _sceneChars;

  @override
  void initState() {
    super.initState();
    final seedScenes = widget.initialScenes.isEmpty
        ? ['']
        : List.of(widget.initialScenes);
    _ctrls = seedScenes
        .take(widget.maxScenes)
        .map((s) => TextEditingController(text: s))
        .toList();
    if (_ctrls.isEmpty) {
      _ctrls.add(TextEditingController());
    }
    _images = List.generate(_ctrls.length, (i) {
      if (i < widget.initialImages.length) return widget.initialImages[i];
      return const ProposalSceneImage();
    });
    final allowed = widget.availableCharacterCodes.toSet();
    _sceneChars = List.generate(_ctrls.length, (i) {
      if (i < widget.initialSceneCharacters.length) {
        return widget.initialSceneCharacters[i].where(allowed.contains).toSet();
      }
      return <String>{};
    });
  }

  @override
  void didUpdateWidget(covariant ProposalScenesEditor old) {
    super.didUpdateWidget(old);
    // 부모가 후보 인물을 바꾸면 (Step 2 수정) 사라진 코드는 정리.
    if (!_listEquals(
      old.availableCharacterCodes,
      widget.availableCharacterCodes,
    )) {
      final allowed = widget.availableCharacterCodes.toSet();
      setState(() {
        _sceneChars = _sceneChars.map((s) => s.intersection(allowed)).toList();
      });
      _notify();
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(
      _ctrls.map((c) => c.text).toList(),
      List.of(_images),
      _sceneChars.map((s) => s.toList()).toList(),
    );
  }

  void _addScene() {
    if (_ctrls.length >= widget.maxScenes) return;
    setState(() {
      _ctrls.add(TextEditingController());
      _images.add(const ProposalSceneImage());
      _sceneChars.add(<String>{});
    });
    _notify();
  }

  void _removeScene(int index) {
    if (_ctrls.length <= 1) return;
    setState(() {
      _ctrls[index].dispose();
      _ctrls.removeAt(index);
      _images.removeAt(index);
      _sceneChars.removeAt(index);
    });
    _notify();
  }

  void _toggleSceneChar(int sceneIdx, String code, bool selected) {
    setState(() {
      if (selected) {
        _sceneChars[sceneIdx].add(code);
      } else {
        _sceneChars[sceneIdx].remove(code);
      }
    });
    _notify();
  }

  /// 그 장면에서 v 표시한 인물 중 텍스트에 이름이 빠진 목록.
  /// 빈 리스트면 "이미지 생성" 가능.
  List<String> _missingNames(int index) {
    final text = _ctrls[index].text;
    final missing = <String>[];
    for (final code in _sceneChars[index]) {
      final name = widget.characterNameByCode[code] ?? code;
      if (name.trim().isEmpty) continue;
      if (!text.contains(name)) missing.add(name);
    }
    return missing;
  }

  Future<void> _onGeneratePressed(int index) async {
    if (widget.busy) return;
    final text = _ctrls[index].text.trim();
    if (text.isEmpty) return;
    if (_missingNames(index).isNotEmpty) return; // gating
    final selectedCodes = _sceneChars[index].toList(growable: false);
    final result = await widget.onGenerate(index, text, selectedCodes);
    if (!mounted || result == null) return;
    setState(() {
      if (index < _images.length) {
        _images[index] = result;
      }
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '각 한 문장, 이미지 생성을 위한 문장입니다. 최소 1개 · 최대 ${widget.maxScenes}개.\n'
            '문장을 쓰고 "이미지 생성" 버튼을 누르면 AI 가 그림을 한 장 만들어 줍니다. '
            '마음에 안 들면 다시 눌러 재생성할 수 있습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < _ctrls.length; i++) ...[
          _SceneRow(
            index: i,
            controller: _ctrls[i],
            image: _images[i],
            availableCharacterCodes: widget.availableCharacterCodes,
            characterNameByCode: widget.characterNameByCode,
            selectedCharCodes: _sceneChars[i],
            missingNames: _missingNames(i),
            onToggleChar: (code, sel) => _toggleSceneChar(i, code, sel),
            onTextChanged: () {
              setState(() {}); // missingNames 재계산
              _notify();
            },
            onGenerate: () => _onGeneratePressed(i),
            onRemove: _ctrls.length > 1 ? () => _removeScene(i) : null,
            busy: widget.busy,
            isBusyHere:
                widget.busy &&
                widget.busySceneIndex != null &&
                widget.busySceneIndex == i,
            publicUrlForPath: widget.publicUrlForPath,
          ),
          const SizedBox(height: 12),
        ],
        if (_ctrls.length < widget.maxScenes)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.busy ? null : _addScene,
              icon: const Icon(Icons.add),
              label: Text('장면 추가 (${_ctrls.length}/${widget.maxScenes})'),
            ),
          ),
      ],
    );
  }
}

class _SceneRow extends StatelessWidget {
  const _SceneRow({
    required this.index,
    required this.controller,
    required this.image,
    required this.availableCharacterCodes,
    required this.characterNameByCode,
    required this.selectedCharCodes,
    required this.missingNames,
    required this.onToggleChar,
    required this.onTextChanged,
    required this.onGenerate,
    required this.onRemove,
    required this.busy,
    required this.isBusyHere,
    required this.publicUrlForPath,
  });

  final int index;
  final TextEditingController controller;
  final ProposalSceneImage image;
  final List<String> availableCharacterCodes;
  final Map<String, String> characterNameByCode;
  final Set<String> selectedCharCodes;
  final List<String> missingNames;
  final void Function(String code, bool selected) onToggleChar;
  final VoidCallback onTextChanged;
  final Future<void> Function() onGenerate;
  final VoidCallback? onRemove;
  final bool busy;
  final bool isBusyHere;
  final String Function(String)? publicUrlForPath;

  /// 우측 이미지 박스의 정사각 변. 좌측 텍스트 col 높이가 이 값보다 짧으면
  /// IntrinsicHeight + crossAxisStretch 로 좌측이 확장된다.
  static const double _imageBoxSize = 220;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textHasContent = controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 좌측: 라벨 + 인물 체크박스 + 입력 + 상태 + 생성 버튼.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '장면 ${index + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (availableCharacterCodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '이전 단계에서 등장 인물을 먼저 골라야 이 장면에 인물을 지정할 수 있어요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '이 장면에 등장하는 인물을 먼저 체크하세요',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 0,
                            children: [
                              for (final code in availableCharacterCodes)
                                FilterChip(
                                  label: Text(
                                    characterNameByCode[code] ?? code,
                                  ),
                                  selected: selectedCharCodes.contains(code),
                                  onSelected: busy
                                      ? null
                                      : (sel) => onToggleChar(code, sel),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          maxLines: 3,
                          minLines: 2,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: '장면 설명',
                            hintText: index == 0
                                ? '필수 — 체크한 인물의 이름을 정확히 한 번 이상 포함해 주세요'
                                : '선택 — 체크한 인물의 이름을 정확히 포함',
                          ),
                          onChanged: (_) => onTextChanged(),
                        ),
                      ),
                      if (onRemove != null)
                        IconButton(
                          tooltip: '이 장면 삭제',
                          onPressed: busy ? null : onRemove,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    image.isReady ? '이미지 생성 완료' : '아직 이미지 없음',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: image.isReady
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: image.isReady
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            (!textHasContent || busy || missingNames.isNotEmpty)
                            ? null
                            : () => onGenerate(),
                        icon: Icon(
                          image.isReady ? Icons.refresh : Icons.auto_awesome,
                          size: 16,
                        ),
                        label: Text(image.isReady ? '재생성' : '이미지 생성'),
                      ),
                    ],
                  ),
                  if (missingNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '선택된 인물이 모두 정확히 동일한 이름으로 언급되어야 합니다. '
                        '누락된 이름: ${missingNames.join(", ")}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (image.isReady)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '이미지를 누르면 크게 볼 수 있어요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // 우측: 큰 정사각 이미지 (220x220). 클릭 시 풀스크린 zoom.
            SizedBox(
              width: _imageBoxSize,
              height: _imageBoxSize,
              child: _SceneImageThumb(
                image: image,
                publicUrlForPath: publicUrlForPath,
                loading: isBusyHere,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneImageThumb extends StatelessWidget {
  const _SceneImageThumb({
    required this.image,
    required this.publicUrlForPath,
    required this.loading,
  });

  final ProposalSceneImage image;
  final String Function(String)? publicUrlForPath;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = (image.isReady && publicUrlForPath != null)
        ? publicUrlForPath!(image.path!)
        : null;

    Widget inner;
    if (loading) {
      inner = const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (url != null) {
      inner = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    } else {
      inner = Center(
        child: Icon(
          Icons.image_outlined,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      );
    }

    final box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox.expand(child: inner),
    );

    if (url == null) return box;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showImageZoomDialog(context, url: url),
        child: box,
      ),
    );
  }
}
