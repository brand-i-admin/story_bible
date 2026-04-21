import 'package:flutter/material.dart';

/// 4장면 동적 에디터.
///
/// - 최소 1개 장면(장면 1) 필수
/// - 최대 4개까지 `+ 장면 추가` 로 늘림
/// - 2~4번째 장면은 `-` 버튼으로 삭제 가능
/// - 각 장면 1문장(이미지 생성용). 변경 시 [onChanged] 로 전체 리스트 전달
class ProposalScenesEditor extends StatefulWidget {
  const ProposalScenesEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.maxScenes = 4,
  });

  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
  final int maxScenes;

  @override
  State<ProposalScenesEditor> createState() => _ProposalScenesEditorState();
}

class _ProposalScenesEditorState extends State<ProposalScenesEditor> {
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial.isEmpty ? [''] : List.of(widget.initial);
    _ctrls = seed
        .take(widget.maxScenes)
        .map((s) => TextEditingController(text: s))
        .toList();
    if (_ctrls.isEmpty) {
      _ctrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_ctrls.map((c) => c.text).toList());
  }

  void _addScene() {
    if (_ctrls.length >= widget.maxScenes) return;
    setState(() => _ctrls.add(TextEditingController()));
    _notify();
  }

  void _removeScene(int index) {
    if (_ctrls.length <= 1) return;
    setState(() {
      _ctrls[index].dispose();
      _ctrls.removeAt(index);
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
            '각 한 문장, 이미지 생성을 위한 문장입니다. 최소 1개 · 최대 ${widget.maxScenes}개.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < _ctrls.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      '장면 ${i + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrls[i],
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: i == 0 ? '필수 — 예: 하늘이 열리고 빛이 내리는 순간' : '선택',
                    ),
                    onChanged: (_) => _notify(),
                  ),
                ),
                if (_ctrls.length > 1)
                  IconButton(
                    tooltip: '이 장면 삭제',
                    onPressed: () => _removeScene(i),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
          ),
        ],
        if (_ctrls.length < widget.maxScenes)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addScene,
              icon: const Icon(Icons.add),
              label: Text('장면 추가 (${_ctrls.length}/${widget.maxScenes})'),
            ),
          ),
      ],
    );
  }
}
