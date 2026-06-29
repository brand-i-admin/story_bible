import 'package:flutter/material.dart';

import '../models/user_companion_diary_entry.dart';
import '../theme/tokens.dart';
import '../widgets/parchment_page_scaffold.dart';
import '../widgets/profile/companion_diary_entry_card.dart';

class CompanionDiaryEntriesScreen extends StatefulWidget {
  const CompanionDiaryEntriesScreen({
    super.key,
    required this.entries,
    this.onSave,
    this.onDelete,
  });

  final List<UserCompanionDiaryEntry> entries;
  final CompanionDiarySaveCallback? onSave;
  final CompanionDiaryDeleteCallback? onDelete;

  @override
  State<CompanionDiaryEntriesScreen> createState() =>
      _CompanionDiaryEntriesScreenState();
}

class _CompanionDiaryEntriesScreenState
    extends State<CompanionDiaryEntriesScreen> {
  late List<UserCompanionDiaryEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries]..sort(_compareEntriesNewestFirst);
  }

  @override
  void didUpdateWidget(CompanionDiaryEntriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _entries = [...widget.entries]..sort(_compareEntriesNewestFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentListPageScaffold(
      title: '오늘의 신앙 기록',
      child: ParchmentCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: _entries.isEmpty
            ? const Center(
                child: Text(
                  '아직 남긴 신앙 기록이 없습니다.\n신앙(예배,말씀,기도,삶의 사건)을 기록해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.ink300,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                    height: 1.55,
                  ),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _entries.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 14, color: Color(0x44BCA47A)),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return CompanionDiaryEntryPreviewCard(
                    entry: entry,
                    dateLabel: formatCompanionDiaryEntryDate(entry.entryDate),
                    onTap: () => _openDetail(context, entry),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final action = await showDialog<CompanionDiaryDetailAction>(
      context: context,
      builder: (dialogContext) => CompanionDiaryEntryDetailDialog(
        entry: entry,
        onEdit: widget.onSave == null
            ? null
            : () => Navigator.of(
                dialogContext,
              ).pop(CompanionDiaryDetailAction.edit),
        onDelete: widget.onDelete == null
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
      await _openEditor(context, entry);
    } else if (action == CompanionDiaryDetailAction.delete) {
      if (!context.mounted) {
        return;
      }
      await _confirmDelete(context, entry);
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final save = widget.onSave;
    if (save == null) {
      return;
    }
    final draft = await showCompanionDiaryEditorDialog(
      context,
      initialEntry: entry,
    );
    if (draft == null) {
      return;
    }
    try {
      final saved = await save(
        entryDate: entry.entryDate,
        title: draft.title,
        body: draft.body,
      );
      if (!context.mounted) {
        return;
      }
      setState(() {
        _replaceEntry(saved);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('동행 일지를 수정했어요.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('동행 일지를 저장하지 못했습니다.\n$error')));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UserCompanionDiaryEntry entry,
  ) async {
    final delete = widget.onDelete;
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
      setState(() {
        _entries = [
          for (final existing in _entries)
            if (!_isSameEntryDate(existing, entry)) existing,
        ];
      });
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

  void _replaceEntry(UserCompanionDiaryEntry saved) {
    _entries = [
      for (final existing in _entries)
        if (!_isSameEntryDate(existing, saved)) existing,
      saved,
    ]..sort(_compareEntriesNewestFirst);
  }

  bool _isSameEntryDate(UserCompanionDiaryEntry a, UserCompanionDiaryEntry b) {
    return a.entryDate.year == b.entryDate.year &&
        a.entryDate.month == b.entryDate.month &&
        a.entryDate.day == b.entryDate.day;
  }
}

int _compareEntriesNewestFirst(
  UserCompanionDiaryEntry a,
  UserCompanionDiaryEntry b,
) {
  final dateOrder = b.entryDate.compareTo(a.entryDate);
  if (dateOrder != 0) {
    return dateOrder;
  }
  return b.updatedAt.compareTo(a.updatedAt);
}
