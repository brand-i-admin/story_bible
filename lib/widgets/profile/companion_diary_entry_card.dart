import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_companion_diary_entry.dart';
import '../../theme/tokens.dart';
import '../parchment_dialog.dart';

typedef CompanionDiarySaveCallback =
    Future<UserCompanionDiaryEntry> Function({
      required DateTime entryDate,
      required String title,
      required String body,
    });

typedef CompanionDiaryDeleteCallback =
    Future<void> Function(UserCompanionDiaryEntry entry);

enum CompanionDiaryDetailAction { edit, delete }

class CompanionDiaryDraft {
  const CompanionDiaryDraft({required this.title, required this.body});

  final String title;
  final String body;
}

class CompanionDiaryEntryPreviewCard extends StatelessWidget {
  const CompanionDiaryEntryPreviewCard({
    super.key,
    required this.entry,
    this.dateLabel,
    this.onTap,
    this.maxBodyLines = 3,
  });

  final UserCompanionDiaryEntry entry;
  final String? dateLabel;
  final VoidCallback? onTap;
  final int maxBodyLines;

  @override
  Widget build(BuildContext context) {
    final date = dateLabel?.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.parchmentCream.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x66BCA47A), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (date != null && date.isNotEmpty) ...[
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.greenBot,
                    fontSize: 11.6,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 7),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const CompanionDiaryEmojiBadge(
                    key: ValueKey('companion-diary-entry-emoji-badge'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink800,
                        fontSize: 15.2,
                        fontWeight: FontWeight.w900,
                        height: 1.22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                entry.body,
                key: ValueKey('companion-diary-preview-body-${entry.id}'),
                maxLines: maxBodyLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink350,
                  fontSize: 12.4,
                  fontWeight: FontWeight.w700,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanionDiaryEmojiBadge extends StatelessWidget {
  const CompanionDiaryEmojiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.greenTint1,
        border: Border.all(color: AppColors.greenBot.withAlpha(0x55)),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('📝', style: TextStyle(fontSize: 17, height: 1)),
      ),
    );
  }
}

class CompanionDiaryEntryDetailDialog extends StatelessWidget {
  const CompanionDiaryEntryDetailDialog({
    super.key,
    required this.entry,
    this.onEdit,
    this.onDelete,
  });

  final UserCompanionDiaryEntry entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ParchmentDialog(
      title: '동행 일지 상세',
      subtitle: formatCompanionDiaryEntryDate(entry.entryDate),
      showCloseButton: true,
      actions: [
        if (onEdit != null)
          ParchmentDialogActionButton(
            key: const ValueKey('companion-diary-detail-edit-button'),
            label: '수정',
            onTap: onEdit,
          ),
        if (onDelete != null)
          ParchmentDialogActionButton(
            key: const ValueKey('companion-diary-detail-delete-button'),
            label: '삭제',
            style: ParchmentDialogActionStyle.danger,
            onTap: onDelete,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CompanionDiaryEmojiBadge(),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    color: AppColors.ink800,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            entry.body,
            key: ValueKey('companion-diary-detail-body-${entry.id}'),
            style: const TextStyle(
              color: AppColors.ink500,
              fontSize: 13.4,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

Future<CompanionDiaryDraft?> showCompanionDiaryEditorDialog(
  BuildContext context, {
  UserCompanionDiaryEntry? initialEntry,
}) {
  return showDialog<CompanionDiaryDraft>(
    context: context,
    builder: (_) => _CompanionDiaryEditorDialog(initialEntry: initialEntry),
  );
}

Future<bool> showCompanionDiaryDeleteConfirmDialog(
  BuildContext context,
  UserCompanionDiaryEntry entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ParchmentDialog(
      title: '동행 일지를 삭제할까요?',
      subtitle: '남긴 일지를 삭제합니다.',
      actions: [
        ParchmentDialogActionButton(
          label: '취소',
          style: ParchmentDialogActionStyle.secondary,
          onTap: () => Navigator.of(dialogContext).pop(false),
        ),
        ParchmentDialogActionButton(
          label: '삭제',
          style: ParchmentDialogActionStyle.danger,
          onTap: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
      child: Text(
        entry.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.ink500,
          fontSize: 13.2,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    ),
  );
  return confirmed == true;
}

String formatCompanionDiaryEntryDate(DateTime date) {
  return '${date.month}월 ${date.day}일';
}

class _CompanionDiaryEditorDialog extends StatefulWidget {
  const _CompanionDiaryEditorDialog({required this.initialEntry});

  final UserCompanionDiaryEntry? initialEntry;

  @override
  State<_CompanionDiaryEditorDialog> createState() =>
      _CompanionDiaryEditorDialogState();
}

class _CompanionDiaryEditorDialogState
    extends State<_CompanionDiaryEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _bodyController = TextEditingController(
      text: widget.initialEntry?.body ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEntry != null;
    return ParchmentDialog(
      title: isEditing ? '동행 일지 수정' : '동행 일지 작성',
      subtitle: '오늘 하루 예수님과 동행한 마음을 기록해 보세요.',
      showCloseButton: true,
      actions: [
        ParchmentDialogActionButton(
          label: isEditing ? '수정' : '저장',
          onTap: _canSubmit ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ParchmentDialogTextField(
            controller: _titleController,
            hintText: '제목',
            maxLength: 80,
            autofocus: true,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ParchmentDialogTextField(
            controller: _bodyController,
            hintText: '오늘 어떤 순간에 예수님과 동행했나요?',
            maxLength: 1000,
            minLines: 5,
            maxLines: 8,
            autofocus: false,
            keyboardType: TextInputType.multiline,
            inputFormatters: [LengthLimitingTextInputFormatter(1000)],
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  bool get _canSubmit {
    return _titleController.text.trim().isNotEmpty &&
        _bodyController.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_canSubmit) {
      return;
    }
    Navigator.of(context).pop(
      CompanionDiaryDraft(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
      ),
    );
  }
}
