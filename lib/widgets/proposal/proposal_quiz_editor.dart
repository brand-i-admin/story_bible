import 'package:flutter/material.dart';

import '../../models/event_proposal.dart';

/// 새 이야기 제안의 Step 5 — 4지선다 퀴즈 1~3개 편집기.
///
/// 제약:
///   - 최소 1개, 최대 3개
///   - 각 퀴즈는 4지선다 (choices.length == 4) + 정답 인덱스 0~3
///   - 질문/선택지 4개/해설 모두 비어있으면 안 됨 (RPC CHECK 와 동일)
///
/// 외부는 [QuizDraft] 리스트만 주고받는다. 내부 TextEditingController 는
/// question/choices/explanation 갯수에 맞춰 생성·정리되며, 상태 변경 시
/// [onChanged] 로 즉시 리스트를 흘려 보낸다 (부모의 _canSubmit 검증용).
class ProposalQuizEditor extends StatefulWidget {
  const ProposalQuizEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.maxCount = 3,
    this.minCount = 1,
  });

  final List<QuizDraft> initial;
  final ValueChanged<List<QuizDraft>> onChanged;
  final int maxCount;
  final int minCount;

  @override
  State<ProposalQuizEditor> createState() => _ProposalQuizEditorState();
}

class _ProposalQuizEditorState extends State<ProposalQuizEditor> {
  late List<_QuizRowControllers> _rows;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial.isEmpty ? [QuizDraft.empty] : widget.initial;
    _rows = seed.map(_QuizRowControllers.fromDraft).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final drafts = _rows.map((r) => r.toDraft()).toList(growable: false);
    widget.onChanged(drafts);
  }

  void _addQuiz() {
    if (_rows.length >= widget.maxCount) return;
    setState(() {
      _rows.add(_QuizRowControllers.fromDraft(QuizDraft.empty));
    });
    _emit();
  }

  void _removeQuiz(int index) {
    if (_rows.length <= widget.minCount) return;
    setState(() {
      _rows.removeAt(index).dispose();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '4지선다 문제 ${widget.minCount}~${widget.maxCount}개. '
            '문제·선택지 4개·해설 모두 필수입니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _QuizCard(
              index: i,
              controllers: _rows[i],
              canRemove: _rows.length > widget.minCount,
              onRemove: () => _removeQuiz(i),
              onChanged: _emit,
            ),
          ),
        if (_rows.length < widget.maxCount)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addQuiz,
              icon: const Icon(Icons.add),
              label: Text('퀴즈 추가 (${_rows.length}/${widget.maxCount})'),
            ),
          ),
      ],
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.index,
    required this.controllers,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _QuizRowControllers controllers;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '퀴즈 ${index + 1}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  tooltip: '이 퀴즈 삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
            ],
          ),
          TextField(
            controller: controllers.question,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '문제',
              hintText: '예: 요셉을 애굽으로 팔아 넘긴 사람들은 누구입니까?',
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Radio<int>(
                    value: i,
                    groupValue: controllers.answerIndex,
                    onChanged: (v) {
                      if (v != null) {
                        controllers.answerIndex = v;
                        onChanged();
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: controllers.choices[i],
                      decoration: InputDecoration(
                        labelText:
                            '선택지 ${i + 1}${controllers.answerIndex == i ? ' (정답)' : ''}',
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: controllers.explanation,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '해설 (필수)',
              hintText: '정답 근거 — 성경 구절이나 배경 설명',
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

/// 퀴즈 한 행의 편집용 controller 묶음. answerIndex 는 Radio 공유용이라
/// controller 가 아닌 원시 int — 변경되면 상위가 rebuild 되도록
/// AnimatedBuilder 없이 onChanged 시그널로만 전달.
class _QuizRowControllers {
  _QuizRowControllers({
    required this.question,
    required this.choices,
    required this.explanation,
    required this.answerIndex,
  });

  factory _QuizRowControllers.fromDraft(QuizDraft d) {
    final choiceCtrls = List<TextEditingController>.generate(
      4,
      (i) =>
          TextEditingController(text: i < d.choices.length ? d.choices[i] : ''),
    );
    return _QuizRowControllers(
      question: TextEditingController(text: d.question),
      choices: choiceCtrls,
      explanation: TextEditingController(text: d.explanation),
      answerIndex: d.answerIndex.clamp(0, 3),
    );
  }

  final TextEditingController question;
  final List<TextEditingController> choices;
  final TextEditingController explanation;
  int answerIndex;

  QuizDraft toDraft() {
    return QuizDraft(
      question: question.text,
      choices: choices.map((c) => c.text).toList(growable: false),
      answerIndex: answerIndex,
      explanation: explanation.text,
    );
  }

  void dispose() {
    question.dispose();
    for (final c in choices) {
      c.dispose();
    }
    explanation.dispose();
  }
}
