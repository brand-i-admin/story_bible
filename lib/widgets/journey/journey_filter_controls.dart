import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';

class JourneySearchField extends StatelessWidget {
  const JourneySearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.controlKey,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: palette.cardSurface,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: TextField(
        key: controlKey,
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        cursorColor: palette.primaryDeep,
        style: TextStyle(
          color: palette.text,
          fontSize: AppFontSizes.base,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: palette.mutedText,
            fontSize: AppFontSizes.base,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.primaryDeep,
            size: 21,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '검색어 지우기',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: palette.mutedText,
                    size: 19,
                  ),
                ),
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            borderSide: BorderSide(color: palette.subtleBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            borderSide: BorderSide(color: palette.selectedBorder, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class JourneySearchEmptyState extends StatelessWidget {
  const JourneySearchEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x7),
      decoration: BoxDecoration(
        color: palette.mutedSurface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      alignment: Alignment.center,
      child: Text(
        '검색 결과가 없어요.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.mutedText,
          fontSize: AppFontSizes.base,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class JourneySegmentButton extends StatelessWidget {
  const JourneySegmentButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.controlKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      key: controlKey,
      color: selected ? palette.utilitySelectedBackground : palette.cardSurface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x2,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? palette.selectedBorder : palette.subtleBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: selected ? palette.activeTextOnAccent : palette.text,
                fontSize: AppFontSizes.base,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JourneyDropdownOption<T> {
  const JourneyDropdownOption({required this.value, required this.label});

  final T value;
  final String label;
}

class JourneySortDropdown<T> extends StatelessWidget {
  const JourneySortDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.controlKey,
  });

  final T value;
  final List<JourneyDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      key: controlKey,
      color: palette.cardSurface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.only(
          left: AppSpacing.x3,
          right: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: palette.selectedBorder, width: 1.2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            dropdownColor: palette.cardSurface,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: palette.primaryDeep,
              size: 18,
            ),
            style: TextStyle(
              color: palette.text,
              fontSize: AppFontSizes.base,
              fontWeight: FontWeight.w700,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem<T>(
                  value: option.value,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(option.label, maxLines: 1, softWrap: false),
                  ),
                ),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}
