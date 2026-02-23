import 'package:flutter/material.dart';

import '../models/era.dart';
import 'game_ui_skin.dart';

class EraSelector extends StatelessWidget {
  const EraSelector({
    super.key,
    required this.eras,
    required this.selectedEraId,
    required this.onSelect,
    required this.selectedTestament,
    required this.onSelectTestament,
  });

  final List<Era> eras;
  final String? selectedEraId;
  final ValueChanged<String> onSelect;
  final String selectedTestament;
  final ValueChanged<String> onSelectTestament;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: tabBarDecoration(),
      clipBehavior: Clip.hardEdge,
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 94,
                height: 36,
                child: _TestamentDropdown(
                  selectedTestament: selectedTestament,
                  onSelectTestament: onSelectTestament,
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                '|',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF6F5535),
                ),
              ),
              const SizedBox(width: 4),
              ...eras.map((era) {
                final selected = era.id == selectedEraId;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: SizedBox(
                    height: 42,
                    child: GestureDetector(
                      onTap: () => onSelect(era.id),
                      child: Container(
                        decoration: tabItemDecoration(selected: selected),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          era.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFDF8EE),
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                color: Color(0xAA000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestamentDropdown extends StatelessWidget {
  const _TestamentDropdown({
    required this.selectedTestament,
    required this.onSelectTestament,
  });

  final String selectedTestament;
  final ValueChanged<String> onSelectTestament;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 94,
      height: 36,
      child: DecoratedBox(
        decoration: statesButtonDecoration(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedTestament == 'new' ? 'new' : 'old',
              isDense: true,
              isExpanded: true,
              iconSize: 12,
              borderRadius: BorderRadius.circular(10),
              dropdownColor: const Color(0xFF4E3A26),
              iconEnabledColor: const Color(0xFFFDF8EE),
              style: const TextStyle(
                color: Color(0xFFFDF8EE),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                shadows: [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              items: const [
                DropdownMenuItem(
                  value: 'old',
                  child: Text(
                    '구약',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'new',
                  child: Text(
                    '신약',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSelectTestament(value);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
