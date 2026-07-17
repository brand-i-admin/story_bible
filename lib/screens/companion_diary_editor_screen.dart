import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_companion_diary_entry.dart';
import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CompanionDiaryDraft {
  const CompanionDiaryDraft({required this.title, required this.body});

  final String title;
  final String body;
}

Future<CompanionDiaryDraft?> openCompanionDiaryEditorPage(
  BuildContext context, {
  required DateTime entryDate,
  UserCompanionDiaryEntry? initialEntry,
}) {
  return Navigator.of(context).push<CompanionDiaryDraft>(
    MaterialPageRoute<CompanionDiaryDraft>(
      builder: (_) => CompanionDiaryEditorScreen(
        entryDate: entryDate,
        initialEntry: initialEntry,
      ),
    ),
  );
}

class CompanionDiaryEditorScreen extends StatefulWidget {
  const CompanionDiaryEditorScreen({
    super.key,
    required this.entryDate,
    this.initialEntry,
  });

  final DateTime entryDate;
  final UserCompanionDiaryEntry? initialEntry;

  @override
  State<CompanionDiaryEditorScreen> createState() =>
      _CompanionDiaryEditorScreenState();
}

class _CompanionDiaryEditorScreenState
    extends State<CompanionDiaryEditorScreen> {
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
    final palette = AppPaletteTheme.of(context);
    final isEditing = widget.initialEntry != null;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: palette.pageGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _DiaryEditorHeader(
                title: isEditing ? '다이어리 수정' : '다이어리 작성',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x7,
                        AppSpacing.x8,
                        AppSpacing.x7,
                        AppSpacing.x5,
                      ),
                      sliver: SliverList.list(
                        children: [
                          Text(
                            _formatFullDate(widget.entryDate),
                            style: AppTextStyles.h3.copyWith(
                              color: palette.text,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x8),
                          _DiaryTextField(
                            key: const ValueKey('companion-diary-title-field'),
                            controller: _titleController,
                            hintText: '제목 (선택)',
                            maxLength: 80,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: AppSpacing.x5),
                          _DiaryTextField(
                            key: const ValueKey('companion-diary-body-field'),
                            controller: _bodyController,
                            hintText: '오늘 삶에서 하나님과 함께한 순간을\n기록해 보세요.',
                            maxLength: 1000,
                            minLines: 9,
                            maxLines: 14,
                            keyboardType: TextInputType.multiline,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: AppSpacing.x6),
                          const _DiaryReflectionPrompts(),
                          const SizedBox(height: AppSpacing.x7),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 17,
                                color: palette.mutedText,
                              ),
                              const SizedBox(width: AppSpacing.x2),
                              Flexible(
                                child: Text(
                                  '이 다이어리는 나만 볼 수 있어요.',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.subtitle.copyWith(
                                    color: palette.mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x7,
                  AppSpacing.x3,
                  AppSpacing.x7,
                  AppSpacing.x7,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('companion-diary-save-button'),
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: palette.actionBottom,
                      foregroundColor: AppColors.fgOnDark,
                      disabledBackgroundColor: palette.mutedSurface,
                      disabledForegroundColor: palette.mutedText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                      ),
                      textStyle: AppTextStyles.buttonLabel.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    child: Text(isEditing ? '수정 저장' : '기록 저장'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSubmit => _bodyController.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) {
      return;
    }
    final title = _titleController.text.trim();
    Navigator.of(context).pop(
      CompanionDiaryDraft(
        title: title.isEmpty ? '제목 없는 다이어리' : title,
        body: _bodyController.text.trim(),
      ),
    );
  }
}

class _DiaryEditorHeader extends StatelessWidget {
  const _DiaryEditorHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3,
        AppSpacing.x3,
        AppSpacing.x3,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '이전',
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded),
            color: palette.text,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2.copyWith(
                color: palette.text,
                fontSize: 19,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _DiaryTextField extends StatelessWidget {
  const _DiaryTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.maxLength,
    required this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final ValueChanged<String> onChanged;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return TextField(
      controller: controller,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      style: AppTextStyles.body.copyWith(
        color: palette.text,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTextStyles.hint.copyWith(color: palette.mutedText),
        counterStyle: AppTextStyles.counter.copyWith(color: palette.mutedText),
        filled: true,
        fillColor: palette.cardSurface,
        contentPadding: const EdgeInsets.all(AppSpacing.x7),
        border: _fieldBorder(palette.subtleBorder),
        enabledBorder: _fieldBorder(palette.subtleBorder),
        focusedBorder: _fieldBorder(palette.primaryDeep, width: 1.5),
      ),
      onChanged: onChanged,
    );
  }

  OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _DiaryReflectionPrompts extends StatelessWidget {
  const _DiaryReflectionPrompts();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.primary.withValues(alpha: 0.07),
          palette.cardSurface,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: palette.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: palette.primaryDeep,
              ),
              const SizedBox(width: AppSpacing.x3),
              Text(
                '기록을 돕는 질문',
                style: AppTextStyles.sectionTitle.copyWith(
                  color: palette.primaryDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x5),
          const _DiaryPromptRow(
            icon: Icons.star_outline_rounded,
            label: '오늘 감사한 일',
          ),
          const _DiaryPromptRow(
            icon: Icons.volunteer_activism_outlined,
            label: '기도한 내용',
          ),
          const _DiaryPromptRow(
            icon: Icons.menu_book_outlined,
            label: '말씀을 통해 떠오른 생각',
          ),
          const _DiaryPromptRow(
            icon: Icons.schedule_rounded,
            label: '오늘의 하루 돌아보기',
            bottomSpacing: false,
          ),
        ],
      ),
    );
  }
}

class _DiaryPromptRow extends StatelessWidget {
  const _DiaryPromptRow({
    required this.icon,
    required this.label,
    this.bottomSpacing = true,
  });

  final IconData icon;
  final String label;
  final bool bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing ? AppSpacing.x4 : 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.primaryDeep),
          const SizedBox(width: AppSpacing.x4),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatFullDate(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.year}년 ${date.month}월 ${date.day}일 '
      '${weekdays[date.weekday - 1]}요일';
}
