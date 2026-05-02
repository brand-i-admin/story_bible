import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/parchment_page_scaffold.dart';

class ProfileNoteEditorScreen extends StatefulWidget {
  const ProfileNoteEditorScreen({super.key});

  @override
  State<ProfileNoteEditorScreen> createState() =>
      _ProfileNoteEditorScreenState();
}

class _ProfileNoteEditorScreenState extends State<ProfileNoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목과 내용을 모두 입력해 주세요.')));
      return;
    }

    Navigator.of(
      context,
    ).pop(<String, String>{'title': title, 'content': content});
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentPageScaffold(
      title: '노트 쓰기',
      actions: [
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB7742B),
            foregroundColor: AppColors.parchmentCream,
          ),
          child: const Text('저장'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: ParchmentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: '제목',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
