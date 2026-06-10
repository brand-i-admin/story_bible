import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

enum ParchmentDialogActionStyle { primary, secondary, danger }

class ParchmentDialog extends StatelessWidget {
  const ParchmentDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.maxWidth = 500,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 16),
    this.showCloseButton = false,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final EdgeInsets padding;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: _surfaceDecoration(),
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.brownEdge.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.ink700,
                            fontSize: 18.5,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle!.trim(),
                            style: const TextStyle(
                              color: AppColors.ink200,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton) ...[
                    const SizedBox(width: 12),
                    _ParchmentDialogCloseButton(
                      onTap: onClose ?? () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ParchmentDialogActionButton extends StatelessWidget {
  const ParchmentDialogActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.style = ParchmentDialogActionStyle.primary,
  });

  final String label;
  final VoidCallback? onTap;
  final ParchmentDialogActionStyle style;

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == ParchmentDialogActionStyle.primary;
    final isDanger = style == ParchmentDialogActionStyle.danger;
    final isEnabled = onTap != null;
    final background = isPrimary
        ? const [AppColors.goldLight, AppColors.goldDeep]
        : isDanger
        ? const [AppColors.dangerTop, AppColors.dangerBot]
        : const [AppColors.parchmentLight, AppColors.parchmentMid];
    final borderColor = isPrimary
        ? AppColors.goldHi
        : isDanger
        ? AppColors.dangerRim
        : AppColors.borderFloating;
    final foreground = isPrimary || isDanger
        ? AppColors.parchmentCream
        : AppColors.ink350;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 84, minHeight: 40),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: background,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: !isEnabled
                      ? const Color(0x00000000)
                      : (isPrimary || isDanger)
                      ? const Color(0x22000000)
                      : const Color(0x14000000),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Opacity(
                opacity: isEnabled ? 1 : 0.45,
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ParchmentDialogTextField extends StatelessWidget {
  const ParchmentDialogTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.maxLength,
    this.autofocus = true,
    this.textCapitalization = TextCapitalization.none,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int? maxLength;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        color: AppColors.ink600,
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.ink150,
          fontSize: 13.6,
          fontWeight: FontWeight.w600,
        ),
        counterStyle: const TextStyle(
          color: AppColors.ink150,
          fontSize: 10.4,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: AppColors.parchmentCream,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.borderFloating,
            width: 1.1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.borderFloating,
            width: 1.1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.brownWarm2, width: 1.5),
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class _ParchmentDialogCloseButton extends StatelessWidget {
  const _ParchmentDialogCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x90FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderFloating, width: 1),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.ink300,
            size: 19,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _surfaceDecoration() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.dialogTopHighlight, AppColors.parchmentMid],
    ),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppColors.borderModalDialog, width: 1.2),
    boxShadow: const [
      BoxShadow(
        color: Color(0x26000000),
        blurRadius: 24,
        offset: Offset(0, 14),
      ),
    ],
  );
}
