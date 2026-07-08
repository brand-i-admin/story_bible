import 'package:flutter/material.dart';

import '../../models/user_companion_diary_entry.dart';
import '../../screens/companion_diary_entries_screen.dart';
import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../pulse_highlight.dart';
import 'companion_diary_entry_card.dart';
import 'glowing_add_button.dart';

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
          alignment: Alignment.center,
          child: _CompanionDiaryTextButton(
            label: '전체 보기',
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
          content: Text(entry == null ? '신앙 다이어리를 남겼어요.' : '신앙 다이어리를 수정했어요.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('신앙 다이어리를 저장하지 못했습니다.\n$error')));
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
      ).showSnackBar(const SnackBar(content: Text('신앙 다이어리를 삭제했어요.')));
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

class CompanionDiaryFeatureCard extends StatelessWidget {
  const CompanionDiaryFeatureCard({
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
    final palette = AppPaletteTheme.of(context);
    final canWrite = onSave != null;
    final hasEntry = entry != null;
    final message = error ?? '오늘 하나님과 함께한 순간을 기록해 보세요!';
    final darkSurface =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
        Brightness.dark;
    final surfaceTop = Color.alphaBlend(
      palette.successBottom.withValues(alpha: darkSurface ? 0.18 : 0.10),
      darkSurface ? palette.cardSurface : AppColors.greenTint1,
    );
    final surfaceBottom = Color.alphaBlend(
      palette.successTop.withValues(alpha: darkSurface ? 0.24 : 0.14),
      darkSurface ? palette.softSurface : AppColors.parchmentCream,
    );
    final diaryEntry = entry;
    final diaryTitle = diaryEntry != null && diaryEntry.title.trim().isNotEmpty
        ? diaryEntry.title.trim()
        : '제목 없는 다이어리';
    final diaryBody = diaryEntry != null && diaryEntry.body.trim().isNotEmpty
        ? diaryEntry.body.trim()
        : '작성한 내용이 없습니다.';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('companion-diary-feature-card'),
        onTap: () => _openAllEntries(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 138),
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [surfaceTop, surfaceBottom],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.sm,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -3,
                bottom: -4,
                child: _DiaryNotebookMark(active: hasEntry),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.successFill,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.completedBorder),
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          size: 13.5,
                          color: palette.successBottom,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '신앙 다이어리',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: palette.mutedText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (hasEntry)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diaryTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12.2,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          diaryBody,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 11.6,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: error == null
                            ? palette.text
                            : AppColors.dangerBot,
                        fontSize: AppFontSizes.base,
                        fontWeight: FontWeight.w800,
                        height: 1.45,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (loading && !hasEntry)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else if (!hasEntry && canWrite)
                    Align(
                      alignment: Alignment.center,
                      child: _DiaryWriteButton(
                        onTap: () => _openEditor(context),
                      ),
                    )
                  else if (!canWrite)
                    Text(
                      '로그인하면 기록할 수 있어요.',
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
          content: Text(entry == null ? '신앙 다이어리를 남겼어요.' : '신앙 다이어리를 수정했어요.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('신앙 다이어리를 저장하지 못했습니다.\n$error')));
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

class _DiaryWriteButton extends StatelessWidget {
  const _DiaryWriteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final darkSurface =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
        Brightness.dark;
    final backgroundColor = Color.alphaBlend(
      palette.successBottom.withValues(alpha: darkSurface ? 0.32 : 0.16),
      palette.cardSurface,
    );
    final labelColor = darkSurface ? AppColors.fgOnDark : palette.successBottom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 9),
      child: PulseHighlight(
        active: true,
        pulseCount: null,
        duration: const Duration(milliseconds: 2100),
        borderRadius: BorderRadius.circular(999),
        color: darkSurface ? palette.successTop : AppColors.greenRim,
        child: Material(
          key: const ValueKey('companion-diary-write-button-pill'),
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileGlowingAddButton(
                    key: const ValueKey('companion-diary-add-button'),
                    tooltip: '신앙 다이어리 기록하기',
                    onTap: onTap,
                    size: 28,
                    iconSize: 19,
                    backgroundColor: palette.successBottom,
                    foregroundColor: AppColors.fgOnDark,
                    pulseDuration: const Duration(milliseconds: 1600),
                    pulseCount: null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '기록하기',
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 12.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiaryNotebookMark extends StatelessWidget {
  const _DiaryNotebookMark({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: active ? 0.30 : 0.22,
      child: SizedBox(
        width: 82,
        height: 82,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: -0.08,
              child: Container(
                width: 50,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.parchmentCream,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.greenBorder, width: 1.4),
                  boxShadow: AppShadows.sm,
                ),
              ),
            ),
            Positioned(
              right: 13,
              bottom: 10,
              child: Transform.rotate(
                angle: 0.46,
                child: Container(
                  width: 8,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.greenBot,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
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
          if (canWrite) ...[
            ProfileGlowingAddButton(
              key: const ValueKey('companion-diary-add-button'),
              tooltip: '신앙 다이어리 작성',
              onTap: onAdd,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            error ??
                (canWrite
                    ? '신앙(예배,말씀,기도,삶의 사건)을 기록해보세요'
                    : '로그인하면 신앙 다이어리를 남길 수 있어요.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink300,
              fontSize: 12.6,
              fontWeight: FontWeight.w800,
              height: 1.42,
            ),
          ),
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
