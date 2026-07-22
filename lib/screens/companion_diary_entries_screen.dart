import 'package:flutter/material.dart';

import '../models/user_companion_diary_entry.dart';
import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/kst_date.dart';
import '../widgets/parchment_page_scaffold.dart';
import '../widgets/profile/companion_diary_entry_card.dart';
import 'companion_diary_editor_screen.dart';

class CompanionDiaryEntriesScreen extends StatefulWidget {
  const CompanionDiaryEntriesScreen({
    super.key,
    required this.entries,
    this.onSave,
    this.onDelete,
    this.now,
  });

  final List<UserCompanionDiaryEntry> entries;
  final CompanionDiarySaveCallback? onSave;
  final CompanionDiaryDeleteCallback? onDelete;
  final DateTime? now;

  @override
  State<CompanionDiaryEntriesScreen> createState() =>
      _CompanionDiaryEntriesScreenState();
}

class _CompanionDiaryEntriesScreenState
    extends State<CompanionDiaryEntriesScreen> {
  late List<UserCompanionDiaryEntry> _entries;
  _CompanionDiaryEntriesFilter _filter = _CompanionDiaryEntriesFilter.thisMonth;

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
    final today = _dateOnly(toKst(widget.now ?? DateTime.now()));
    final monthEntries = _entries
        .where(
          (entry) =>
              entry.entryDate.year == today.year &&
              entry.entryDate.month == today.month,
        )
        .toList(growable: false);
    final visibleEntries = _filter == _CompanionDiaryEntriesFilter.thisMonth
        ? monthEntries
        : _entries;
    return ParchmentListPageScaffold(
      title: '다이어리',
      bodyPadding: const EdgeInsets.fromLTRB(
        AppSpacing.x5,
        62,
        AppSpacing.x5,
        AppSpacing.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompanionDiaryStatsRow(
            monthRecordCount: _uniqueDateCount(monthEntries),
            streakDays: _currentStreakDays(today),
          ),
          const SizedBox(height: AppSpacing.x6),
          _CompanionDiaryFilterBar(
            selected: _filter,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: AppSpacing.x6),
          Expanded(
            child: visibleEntries.isEmpty
                ? _CompanionDiaryEntriesEmptyState(filter: _filter)
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: visibleEntries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.x6),
                    itemBuilder: (context, index) {
                      final entry = visibleEntries[index];
                      return CompanionDiaryEntryPreviewCard(
                        entry: entry,
                        dateLabel: _formatDiaryDateTime(entry),
                        maxBodyLines: 2,
                        onTap: () => _openDetail(context, entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  int _uniqueDateCount(List<UserCompanionDiaryEntry> entries) {
    return entries.map((entry) => _dateOnly(entry.entryDate)).toSet().length;
  }

  int _currentStreakDays(DateTime today) {
    final dates = _entries.map((entry) => _dateOnly(entry.entryDate)).toSet();
    var cursor = dates.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    if (!dates.contains(cursor)) {
      return 0;
    }
    var streak = 0;
    while (dates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
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
    final draft = await openCompanionDiaryEditorPage(
      context,
      entryDate: entry.entryDate,
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
      ).showSnackBar(const SnackBar(content: Text('다이어리를 수정했어요.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('다이어리를 저장하지 못했습니다.\n$error')));
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
      ).showSnackBar(const SnackBar(content: Text('다이어리를 삭제했어요.')));
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

enum _CompanionDiaryEntriesFilter { all, thisMonth }

class _CompanionDiaryStatsRow extends StatelessWidget {
  const _CompanionDiaryStatsRow({
    required this.monthRecordCount,
    required this.streakDays,
  });

  final int monthRecordCount;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: _CompanionDiaryStatCard(
            key: const ValueKey('companion-diary-month-stat'),
            icon: Icons.calendar_month_rounded,
            label: '이번 달',
            value: '$monthRecordCount일 기록',
            accent: palette.primaryDeep,
          ),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: _CompanionDiaryStatCard(
            key: const ValueKey('companion-diary-streak-stat'),
            icon: Icons.local_fire_department_rounded,
            label: '연속',
            value: '$streakDays일',
            accent: palette.successBottom,
          ),
        ),
      ],
    );
  }
}

class _CompanionDiaryStatCard extends StatelessWidget {
  const _CompanionDiaryStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 102),
      padding: const EdgeInsets.all(AppSpacing.x5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.10),
          palette.cardSurface,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 25),
          const SizedBox(height: AppSpacing.x3),
          Text(
            label,
            style: AppTextStyles.subtitle.copyWith(color: palette.mutedText),
          ),
          const SizedBox(height: AppSpacing.x2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.h2.copyWith(
                color: palette.text,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanionDiaryFilterBar extends StatelessWidget {
  const _CompanionDiaryFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _CompanionDiaryEntriesFilter selected;
  final ValueChanged<_CompanionDiaryEntriesFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompanionDiaryFilterButton(
            key: const ValueKey('companion-diary-filter-all'),
            label: '전체',
            selected: selected == _CompanionDiaryEntriesFilter.all,
            onTap: () => onChanged(_CompanionDiaryEntriesFilter.all),
          ),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: _CompanionDiaryFilterButton(
            key: const ValueKey('companion-diary-filter-this-month'),
            label: '이번 달',
            selected: selected == _CompanionDiaryEntriesFilter.thisMonth,
            onTap: () => onChanged(_CompanionDiaryEntriesFilter.thisMonth),
          ),
        ),
      ],
    );
  }
}

class _CompanionDiaryFilterButton extends StatelessWidget {
  const _CompanionDiaryFilterButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final background = selected ? palette.primary : palette.cardSurface;
    final foreground = selected ? AppColors.fgOnDark : palette.text;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? palette.primary : palette.subtleBorder,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.buttonLabel.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _CompanionDiaryEntriesEmptyState extends StatelessWidget {
  const _CompanionDiaryEntriesEmptyState({required this.filter});

  final _CompanionDiaryEntriesFilter filter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final message = filter == _CompanionDiaryEntriesFilter.thisMonth
        ? '이번 달에 남긴 다이어리가 없어요.'
        : '아직 남긴 다이어리가 없어요.\n오늘 탭에서 첫 기록을 남겨보세요.';
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(
          color: palette.mutedText,
          fontWeight: FontWeight.w800,
          height: 1.55,
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatDiaryDateHeader(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 ${weekdays[date.weekday - 1]}요일';
}

String _formatDiaryDateTime(UserCompanionDiaryEntry entry) {
  final local = toKst(entry.updatedAt);
  final period = local.hour < 12 ? '오전' : '오후';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_formatDiaryDateHeader(entry.entryDate)} · $period $hour:$minute';
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
