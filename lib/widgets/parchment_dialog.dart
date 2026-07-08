import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_color_palette.dart';
import '../theme/surfaces.dart';
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
    final palette = AppPaletteTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: _surfaceDecoration(context),
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
                    color: AppColors.oceanBot.withValues(alpha: 0.26),
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
                          style: TextStyle(
                            color: palette.text,
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
                            style: TextStyle(
                              color: palette.mutedText,
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
    final palette = AppPaletteTheme.of(context);
    final isPrimary = style == ParchmentDialogActionStyle.primary;
    final isDanger = style == ParchmentDialogActionStyle.danger;
    final isEnabled = onTap != null;
    final background = isPrimary
        ? [palette.actionTop, palette.actionBottom]
        : isDanger
        ? const [AppColors.dangerTop, AppColors.dangerBot]
        : [palette.softSurface, palette.cardSurface];
    final borderColor = isPrimary
        ? palette.actionBorder
        : isDanger
        ? AppColors.dangerRim
        : palette.subtleBorder;
    final foreground = isPrimary || isDanger
        ? AppColors.parchmentCream
        : palette.text;

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
    final palette = AppPaletteTheme.of(context);
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
      style: TextStyle(
        color: palette.text,
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: palette.mutedText,
          fontSize: 13.6,
          fontWeight: FontWeight.w600,
        ),
        counterStyle: TextStyle(
          color: palette.mutedText,
          fontSize: 10.4,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: palette.cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.subtleBorder, width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.subtleBorder, width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.primaryDeep, width: 1.5),
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
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.softSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.subtleBorder, width: 1),
          ),
          child: Icon(Icons.close_rounded, color: palette.mutedText, size: 19),
        ),
      ),
    );
  }
}

BoxDecoration _surfaceDecoration(BuildContext context) {
  return AppSurfaces.modal(palette: AppPaletteTheme.of(context));
}
