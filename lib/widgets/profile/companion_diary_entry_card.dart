import 'package:flutter/material.dart';

import '../../models/user_companion_diary_entry.dart';
import '../../theme/app_color_palette.dart';
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
    final palette = AppPaletteTheme.of(context);
    final darkSurface = palette == AppColorPalette.blackMap;
    final date = dateLabel?.trim();
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final cardColor = darkSurface
        ? palette.cardSurface
        : AppColors.parchmentCream.withValues(alpha: 0.74);
    final borderColor = darkSurface
        ? palette.subtleBorder
        : const Color(0x66BCA47A);
    final dateColor = darkSurface ? palette.successTop : AppColors.greenBot;
    final titleColor = darkSurface ? palette.text : AppColors.ink800;
    final bodyColor = darkSurface ? palette.text : AppColors.ink350;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 15.2,
                        fontWeight: FontWeight.w900,
                        height: 1.22,
                      ),
                    ),
                  ),
                  if (date != null && date.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        date,
                        maxLines: largeText ? null : 1,
                        overflow: largeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        softWrap: true,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: dateColor,
                          fontSize: 11.2,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              Text(
                entry.body,
                key: ValueKey('companion-diary-preview-body-${entry.id}'),
                maxLines: largeText ? null : maxBodyLines,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  color: bodyColor,
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
    final palette = AppPaletteTheme.of(context);
    final darkSurface = palette == AppColorPalette.blackMap;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: darkSurface ? palette.successFill : AppColors.greenTint1,
        border: Border.all(
          color: darkSurface
              ? palette.successBottom.withValues(alpha: 0.62)
              : AppColors.greenBot.withAlpha(0x55),
        ),
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
    final palette = AppPaletteTheme.of(context);
    final darkSurface = palette == AppColorPalette.blackMap;
    final titleColor = darkSurface ? palette.text : AppColors.ink800;
    final bodyColor = darkSurface ? palette.text : AppColors.ink500;
    return ParchmentDialog(
      title: '다이어리 상세',
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
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('companion-diary-detail-body-surface'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.x5),
            decoration: BoxDecoration(
              color: darkSurface ? palette.softSurface : palette.mutedSurface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: palette.subtleBorder, width: 0.9),
            ),
            child: Text(
              entry.body,
              key: ValueKey('companion-diary-detail-body-${entry.id}'),
              style: TextStyle(
                color: bodyColor,
                fontSize: 13.4,
                fontWeight: FontWeight.w700,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showCompanionDiaryDeleteConfirmDialog(
  BuildContext context,
  UserCompanionDiaryEntry entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = AppPaletteTheme.of(dialogContext);
      final darkSurface = palette == AppColorPalette.blackMap;
      final largeText = MediaQuery.textScalerOf(dialogContext).scale(1) >= 1.3;
      return ParchmentDialog(
        title: '다이어리를 삭제할까요?',
        subtitle: '남긴 다이어리를 삭제합니다.',
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
          maxLines: largeText ? null : 2,
          overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            color: darkSurface ? palette.text : AppColors.ink500,
            fontSize: 13.2,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

String formatCompanionDiaryEntryDate(DateTime date) {
  return '${date.month}월 ${date.day}일';
}
