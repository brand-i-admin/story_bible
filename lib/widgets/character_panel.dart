import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import 'game_ui_skin.dart';

enum CharacterSortMode { alphabetical, eraOrder }

class CharacterPanel extends ConsumerWidget {
  const CharacterPanel({
    super.key,
    required this.characters,
    required this.selectedCharacterCodes,
    required this.onToggle,
    required this.colorForCharacter,
    required this.sortMode,
    required this.onSortModeChanged,
  });

  final List<Character> characters;
  final Set<String> selectedCharacterCodes;
  final ValueChanged<String> onToggle;
  final Color Function(String characterCode) colorForCharacter;
  final CharacterSortMode sortMode;
  final ValueChanged<CharacterSortMode> onSortModeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storyControllerProvider);
    final eventCountByCode = _eventCountByCharacterCode(state);
    final sortedCharacters = _sortedCharacters();
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
                _CharacterPanelHeader(
                  sortMode: sortMode,
                  onSortModeChanged: onSortModeChanged,
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.45)),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    itemCount: sortedCharacters.length,
                    itemBuilder: (context, index) {
                      final character = sortedCharacters[index];
                      final selected = selectedCharacterCodes.contains(
                        character.code,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2.5,
                        ),
                        child: _CharacterTile(
                          character: character,
                          selected: selected,
                          eventCount: eventCountByCode[character.code],
                          accentColor: colorForCharacter(character.code),
                          onTap: () => onToggle(character.code),
                          ref: ref,
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

  Map<String, int> _eventCountByCharacterCode(StoryState state) {
    final eventCountByCode = <String, int>{};
    for (final event in state.events) {
      for (final code in event.characterCodes) {
        eventCountByCode[code] = (eventCountByCode[code] ?? 0) + 1;
      }
    }
    return eventCountByCode;
  }

  List<Character> _sortedCharacters() {
    final sortedCharacters = [...characters];
    sortedCharacters.sort((a, b) {
      if (sortMode == CharacterSortMode.eraOrder) {
        final byOrder = a.displayOrder.compareTo(b.displayOrder);
        if (byOrder != 0) return byOrder;
      }
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return a.code.compareTo(b.code);
    });
    return sortedCharacters;
  }
}

class _CharacterPanelHeader extends StatelessWidget {
  const _CharacterPanelHeader({
    required this.sortMode,
    required this.onSortModeChanged,
  });

  final CharacterSortMode sortMode;
  final ValueChanged<CharacterSortMode> onSortModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  child: DropdownButton<CharacterSortMode>(
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
                        value: CharacterSortMode.alphabetical,
                        child: Text(
                          '가나다순',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: CharacterSortMode.eraOrder,
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
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.selected,
    required this.eventCount,
    required this.accentColor,
    required this.onTap,
    required this.ref,
  });

  final Character character;
  final bool selected;
  final int? eventCount;
  final Color accentColor;
  final VoidCallback onTap;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: tabItemDecoration(selected: selected),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            _CharacterTileAvatar(
              character: character,
              selected: selected,
              ref: ref,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CharacterTileText(
                character: character,
                eventCount: eventCount,
                accentColor: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterTileAvatar extends StatelessWidget {
  const _CharacterTileAvatar({
    required this.character,
    required this.selected,
    required this.ref,
  });

  final Character character;
  final bool selected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF8D4E05) : const Color(0xFFC9A06B),
          width: selected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: _PanelAvatarImage(
          character: character,
          selected: selected,
          ref: ref,
        ),
      ),
    );
  }
}

class _CharacterTileText extends StatelessWidget {
  const _CharacterTileText({
    required this.character,
    required this.eventCount,
    required this.accentColor,
  });

  final Character character;
  final int? eventCount;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          character.name,
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
        Row(
          children: [
            if (eventCount != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$eventCount 사건',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                character.tagline ?? '',
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
            ),
          ],
        ),
      ],
    );
  }
}

/// 좌측 인물 패널의 42×42 아바타. CharacterAvatar 와 거의 같지만 선택 여부에
/// 따른 fallback 색(D58E2D vs E3CDAA) 을 유지하기 위해 별도 위젯으로 둔다.
///
/// 1순위 로컬 번들 → 2순위 Supabase Storage → 3순위 이니셜.
class _PanelAvatarImage extends StatelessWidget {
  const _PanelAvatarImage({
    required this.character,
    required this.selected,
    required this.ref,
  });

  final Character character;
  final bool selected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final hasLocal = character.hasLocalAvatar;
    final assetPath = hasLocal ? character.avatarAssetPath.trim() : '';
    final storagePath = character.avatarStoragePath?.trim();
    final fallback = _AvatarFallback(name: character.name, selected: selected);

    String? storageUrl;
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        final client = ref.read(supabaseClientProvider);
        final slash = storagePath.indexOf('/');
        if (slash < 0) {
          storageUrl = client.storage
              .from('characters')
              .getPublicUrl(storagePath);
        } else {
          storageUrl = client.storage
              .from(storagePath.substring(0, slash))
              .getPublicUrl(storagePath.substring(slash + 1));
        }
      } catch (_) {
        storageUrl = null;
      }
    }

    if (assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (storageUrl == null) return fallback;
          return _network(storageUrl, fallback);
        },
      );
    }
    if (storageUrl != null) {
      return _network(storageUrl, fallback);
    }
    return fallback;
  }

  Widget _network(String url, Widget fallback) {
    // Imagen 1024×1024 정중앙 → 상반신 위주로 1.5× 확대 (canonical thumb 와 톤 맞춤).
    return Transform.scale(
      scale: 1.5,
      alignment: Alignment.topCenter,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, w, p) =>
            p == null ? w : const ColoredBox(color: Color(0xFFE7D2B2)),
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
