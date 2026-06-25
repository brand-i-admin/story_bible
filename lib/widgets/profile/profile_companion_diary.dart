import 'package:flutter/material.dart';

import '../../models/user_companion_diary_entry.dart';
import '../../screens/companion_diary_entries_screen.dart';
import '../../theme/tokens.dart';
import 'companion_diary_entry_card.dart';

class CompanionDiaryTodaySection extends StatelessWidget {
  const CompanionDiaryTodaySection({
    super.key,
    required this.entryDate,
    required this.entry,
    required this.entries,
    required this.loading,
    required this.error,
    required this.onSave,
    required this.onDelete,
  });

  final DateTime entryDate;
  final UserCompanionDiaryEntry? entry;
  final List<UserCompanionDiaryEntry> entries;
  final bool loading;
  final String? error;
  final CompanionDiarySaveCallback? onSave;
  final CompanionDiaryDeleteCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final currentEntry = entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading && currentEntry == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
          )
        else if (currentEntry == null)
          _CompanionDiaryEmptyState(
            error: error,
            canWrite: onSave != null,
            onAdd: onSave == null ? null : () => _openEditor(context),
          )
        else
          CompanionDiaryEntryPreviewCard(
            entry: currentEntry,
            onTap: () => _openDetail(context, currentEntry),
          ),
        if (error != null && currentEntry != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.dangerBot,
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 9),
        Align(
          alignment: Alignment.centerRight,
          child: _CompanionDiaryTextButton(
            label: '전체보기',
            onTap: () => _openAllEntries(context),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    return _openEditorForEntry(context, entry);
  }

  Future<void> _openEditorForEntry(
    BuildContext context,
    UserCompanionDiaryEntry? initialEntry,
  ) async {
    final save = onSave;
    if (save == null) {
      return;
    }
    final draft = await showCompanionDiaryEditorDialog(
      context,
      initialEntry: initialEntry,
    );
    if (draft == null) {
      return;
    }
    try {
      await save(
        entryDate: initialEntry?.entryDate ?? entryDate,
        title: draft.title,
        body: draft.body,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entry == null ? '동행 일지를 남겼어요.' : '동행 일지를 수정했어요.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('동행 일지를 저장하지 못했습니다.\n$error')));
    }
  }

  Future<void> _openDetail(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final action = await showDialog<CompanionDiaryDetailAction>(
      context: context,
      builder: (dialogContext) => CompanionDiaryEntryDetailDialog(
        entry: entry,
        onEdit: onSave == null
            ? null
            : () => Navigator.of(
                dialogContext,
              ).pop(CompanionDiaryDetailAction.edit),
        onDelete: onDelete == null
            ? null
            : () => Navigator.of(
                dialogContext,
              ).pop(CompanionDiaryDetailAction.delete),
      ),
    );
    if (action == CompanionDiaryDetailAction.edit) {
      if (!context.mounted) {
        return;
      }
      await _openEditorForEntry(context, entry);
    } else if (action == CompanionDiaryDetailAction.delete) {
      if (!context.mounted) {
        return;
      }
      await _confirmDelete(context, entry);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final delete = onDelete;
    if (delete == null) {
      return;
    }
    final confirmed = await showCompanionDiaryDeleteConfirmDialog(
      context,
      entry,
    );
    if (!confirmed) {
      return;
    }
    try {
      await delete(entry);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('동행 일지를 삭제했어요.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다.\n$error')));
    }
  }

  void _openAllEntries(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanionDiaryEntriesScreen(
          entries: entries,
          onSave: onSave,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _CompanionDiaryEmptyState extends StatelessWidget {
  const _CompanionDiaryEmptyState({
    required this.error,
    required this.canWrite,
    required this.onAdd,
  });

  final String? error;
  final bool canWrite;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentCream.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x55BCA47A), width: 0.8),
      ),
      child: Column(
        children: [
          Text(
            error ??
                (canWrite
                    ? '오늘 하루 예배, 말씀, 기도 등 신앙 기록을 남겨보세요'
                    : '로그인하면 동행 일지를 남길 수 있어요.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink300,
              fontSize: 12.6,
              fontWeight: FontWeight.w800,
              height: 1.42,
            ),
          ),
          if (canWrite) ...[
            const SizedBox(height: 10),
            _CompanionDiaryCircleButton(
              key: const ValueKey('companion-diary-add-button'),
              tooltip: '동행 일지 작성',
              icon: Icons.add_rounded,
              onTap: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

class _CompanionDiaryTextButton extends StatelessWidget {
  const _CompanionDiaryTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.greenTint1.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.greenBot,
              fontSize: 11.2,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionDiaryCircleButton extends StatelessWidget {
  const _CompanionDiaryCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.greenTint2,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 22, color: AppColors.greenBot),
          ),
        ),
      ),
    );
  }
}
