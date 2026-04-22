import 'package:flutter/material.dart';

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
    required this.onChanged,
    required this.onGenerate,
    this.busy = false,
    this.busySceneIndex,
    this.maxScenes = 4,
    this.publicUrlForPath,
  });

  final List<String> initialScenes;
  final List<ProposalSceneImage> initialImages;

  /// 텍스트 또는 이미지 집합이 바뀔 때 부모로 최신 스냅샷 전달.
  final void Function(List<String> scenes, List<ProposalSceneImage> images)
  onChanged;

  /// 부모가 실제 생성 로직을 수행한다 (Repository 호출).
  /// 반환된 [ProposalSceneImage] 를 해당 인덱스에 반영.
  /// 실패 시 부모는 예외를 던지거나 null 반환.
  final Future<ProposalSceneImage?> Function(int sceneIndex, String sceneText)
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
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_ctrls.map((c) => c.text).toList(), List.of(_images));
  }

  void _addScene() {
    if (_ctrls.length >= widget.maxScenes) return;
    setState(() {
      _ctrls.add(TextEditingController());
      _images.add(const ProposalSceneImage());
    });
    _notify();
  }

  void _removeScene(int index) {
    if (_ctrls.length <= 1) return;
    setState(() {
      _ctrls[index].dispose();
      _ctrls.removeAt(index);
      _images.removeAt(index);
    });
    _notify();
  }

  Future<void> _onGeneratePressed(int index) async {
    if (widget.busy) return;
    final text = _ctrls[index].text.trim();
    if (text.isEmpty) return;
    final result = await widget.onGenerate(index, text);
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
            onTextChanged: _notify,
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
  final VoidCallback onTextChanged;
  final Future<void> Function() onGenerate;
  final VoidCallback? onRemove;
  final bool busy;
  final bool isBusyHere;
  final String Function(String)? publicUrlForPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textHasContent = controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    '장면 ${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 1,
                  enabled: !busy,
                  decoration: InputDecoration(
                    hintText: index == 0
                        ? '필수 — 예: 하늘이 열리고 빛이 내리는 순간'
                        : '선택 — 한 문장',
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
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SceneImageThumb(
                image: image,
                publicUrlForPath: publicUrlForPath,
                loading: isBusyHere,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          onPressed: (!textHasContent || busy)
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
                  ],
                ),
              ),
            ],
          ),
        ],
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
    const size = 96.0;
    Widget inner;
    if (loading) {
      inner = const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (image.isReady && publicUrlForPath != null) {
      inner = Image.network(
        publicUrlForPath!(image.path!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      inner = Icon(
        Icons.image_outlined,
        size: 32,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: inner,
    );
  }
}
