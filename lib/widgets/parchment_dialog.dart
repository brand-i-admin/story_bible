import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                    color: const Color(0x339A7A4C),
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
                            color: Color(0xFF3F2A17),
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
                              color: Color(0xFF8A6A46),
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
        ? const [Color(0xFFD89A47), Color(0xFFB96B2D)]
        : isDanger
        ? const [Color(0xFFD97C60), Color(0xFFB4583B)]
        : const [Color(0xFFF8F0E2), Color(0xFFEEDDC1)];
    final borderColor = isPrimary
        ? const Color(0xFFF2D8A6)
        : isDanger
        ? const Color(0xFFF2C2B3)
        : const Color(0xBC9A7A4C);
    final foreground = isPrimary || isDanger
        ? const Color(0xFFFDF8EE)
        : const Color(0xFF5E4528);

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
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        color: Color(0xFF402B18),
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9B805D),
          fontSize: 13.6,
          fontWeight: FontWeight.w600,
        ),
        counterStyle: const TextStyle(
          color: Color(0xFF9B805D),
          fontSize: 10.4,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: const Color(0xFFF9F2E7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xB88E6F48), width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xB88E6F48), width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFB87731), width: 1.5),
        ),
      ),
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
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: Color(0xFF6E512C),
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
      colors: [Color(0xFFFBF5EA), Color(0xFFF2E5CC)],
    ),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xC29E7A4C), width: 1.2),
    boxShadow: const [
      BoxShadow(
        color: Color(0x26000000),
        blurRadius: 24,
        offset: Offset(0, 14),
      ),
    ],
  );
}
