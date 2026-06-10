import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_bible_verse.dart';
import '../theme/tokens.dart';
import 'parchment_dialog.dart';

const savedVerseCommentMaxLength = 200;

class SavedVerseDeleteDecision {
  const SavedVerseDeleteDecision({
    required this.shouldDelete,
    required this.hadComment,
  });

  final bool shouldDelete;
  final bool hadComment;
}

Future<String> showSavedVerseCommentDialog(BuildContext context) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _SavedVerseCommentDialog(),
  );
  return (result ?? '').trim();
}

Future<SavedVerseDeleteDecision> confirmSavedVerseDelete({
  required BuildContext context,
  required SavedBibleVerse verse,
}) async {
  final comment = verse.comment.trim();
  if (comment.isEmpty) {
    return const SavedVerseDeleteDecision(
      shouldDelete: true,
      hadComment: false,
    );
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return ParchmentDialog(
        title: '말씀 저장을 취소할까요?',
        actions: [
          ParchmentDialogActionButton(
            label: '닫기',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(false),
          ),
          ParchmentDialogActionButton(
            label: '저장 취소',
            style: ParchmentDialogActionStyle.danger,
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "'$comment' 코멘트가 있는데 정말 저장 취소할까요?",
              style: const TextStyle(
                color: AppColors.ink600,
                fontSize: 14.2,
                fontWeight: FontWeight.w800,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    },
  );

  return SavedVerseDeleteDecision(
    shouldDelete: confirmed == true,
    hadComment: true,
  );
}

String savedVerseDeleteSuccessMessage({required bool hadComment}) {
  if (hadComment) {
    return '구절 저장이 취소되었어요.';
  }
  return '저장된 코멘트가 없어서 바로 구절 저장을 취소했어요.';
}

class _SavedVerseCommentDialog extends StatefulWidget {
  const _SavedVerseCommentDialog();

  @override
  State<_SavedVerseCommentDialog> createState() =>
      _SavedVerseCommentDialogState();
}

class _SavedVerseCommentDialogState extends State<_SavedVerseCommentDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentDialog(
      title: '말씀을 저장할까요?',
      subtitle: '닫으면 코멘트 없이 저장됩니다.',
      showCloseButton: true,
      onClose: () => Navigator.of(context).pop(''),
      actions: [
        ParchmentDialogActionButton(
          label: '저장',
          onTap: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
      child: ParchmentDialogTextField(
        controller: _controller,
        hintText: '왜 이 구절을 저장했나요?',
        maxLength: savedVerseCommentMaxLength,
        minLines: 3,
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        inputFormatters: [
          LengthLimitingTextInputFormatter(savedVerseCommentMaxLength),
        ],
      ),
    );
  }
}
