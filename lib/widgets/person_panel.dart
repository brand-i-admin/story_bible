import 'package:flutter/material.dart';

import '../models/person.dart';
import '../theme/tokens.dart';
import 'game_ui_skin.dart';

enum PersonSortMode { alphabetical, eraOrder }

class PersonPanel extends StatelessWidget {
  const PersonPanel({
    super.key,
    required this.persons,
    required this.selectedPersonIds,
    required this.onToggle,
    required this.colorForPerson,
    required this.sortMode,
    required this.onSortModeChanged,
  });

  final List<Person> persons;
  final Set<String> selectedPersonIds;
  final ValueChanged<String> onToggle;
  final Color Function(String personId) colorForPerson;
  final PersonSortMode sortMode;
  final ValueChanged<PersonSortMode> onSortModeChanged;

  @override
  Widget build(BuildContext context) {
    final sortedPersons = [...persons]
      ..sort((a, b) {
        if (sortMode == PersonSortMode.eraOrder) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          if (byOrder != 0) {
            return byOrder;
          }
          final byName = a.name.compareTo(b.name);
          if (byName != 0) {
            return byName;
          }
          return a.code.compareTo(b.code);
        }
        final byName = a.name.compareTo(b.name);
        if (byName != 0) {
          return byName;
        }
        return a.code.compareTo(b.code);
      });
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: panelFrameDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelPadding = panelContentPaddingForSize(constraints.biggest);
          return Padding(
            padding: panelPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: statesButtonLabel(
                            text: '인물 선택',
                            width: 156,
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 78,
                        height: 36,
                        child: DecoratedBox(
                          decoration: statesButtonDecoration(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<PersonSortMode>(
                                value: sortMode,
                                isDense: true,
                                isExpanded: true,
                                iconSize: 12,
                                dropdownColor: const Color(0xFF4E3A26),
                                borderRadius: BorderRadius.circular(10),
                                iconEnabledColor: AppColors.parchmentCream,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.parchmentCream,
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
                                    value: PersonSortMode.alphabetical,
                                    child: Text(
                                      '가나다순',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: PersonSortMode.eraOrder,
                                    child: Text(
                                      '시대순',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    onSortModeChanged(value);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.45)),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    itemCount: sortedPersons.length,
                    itemBuilder: (context, index) {
                      final person = sortedPersons[index];
                      final selected = selectedPersonIds.contains(person.id);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2.5,
                        ),
                        child: GestureDetector(
                          onTap: () => onToggle(person.id),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 60),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: tabItemDecoration(selected: selected),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: colorForPerson(person.id),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF8D4E05)
                                          : const Color(0xFFC9A06B),
                                      width: selected ? 2 : 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.16,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child:
                                        person.avatarAssetPath.trim().isNotEmpty
                                        ? Image.asset(
                                            person.avatarAssetPath,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _AvatarFallback(
                                                  name: person.name,
                                                  selected: selected,
                                                ),
                                          )
                                        : _AvatarFallback(
                                            name: person.name,
                                            selected: selected,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        person.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppColors.parchmentCream,
                                          shadows: [
                                            Shadow(
                                              color: Color(0x99000000),
                                              blurRadius: 3,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        person.tagline ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFF4E9D2),
                                          shadows: [
                                            Shadow(
                                              color: Color(0x88000000),
                                              blurRadius: 2,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1);
    return Container(
      color: selected ? const Color(0xFFD58E2D) : const Color(0xFFE3CDAA),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.parchmentCream,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(
              color: Color(0x99000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
