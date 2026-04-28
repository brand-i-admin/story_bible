// 부모 라이브러리: lib/widgets/story_selection_panel.dart
//
// 시대/인물/이야기 선택 카드와 카드 셸, 인덱스 배지, 인물 도트, 초상 아바타
// 등 카드형 UI를 모은 파트 파일.
part of '../story_selection_panel.dart';

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    this.completed = false,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final bool completed;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected && completed
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4A9D61), Color(0xFF2E6F45)],
                  )
                : selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFAE6D37), Color(0xFF87502A)],
                  )
                : completed
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE3F3DC), Color(0xFFCFE8C6)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE7D2B2), Color(0xFFDDC29E)],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected && completed
                  ? const Color(0xFFD4F0C9)
                  : selected
                  ? const Color(0xFFF4D58A)
                  : completed
                  ? const Color(0xFF7EB07A)
                  : const Color(0xFFB78A63),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: selected || completed ? 0.12 : 0.07,
                ),
                blurRadius: selected || completed ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EraCompactCard extends StatelessWidget {
  const _EraCompactCard({
    required this.index,
    required this.era,
    required this.selected,
    required this.onTap,
    this.dateLabel,
  });

  final int index;
  final Era era;
  final bool selected;
  final VoidCallback onTap;
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          _IndexBadge(label: '$index'),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: era.name,
                    style: TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFFFDF8EE)
                          : const Color(0xFF5C3A20),
                    ),
                  ),
                  if (dateLabel != null)
                    TextSpan(
                      text: ' ($dateLabel)',
                      style: TextStyle(
                        fontSize: 11.6,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFFF4E6CD)
                            : const Color(0xFF75563C),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterCompactCard extends StatelessWidget {
  const _CharacterCompactCard({
    required this.character,
    required this.selected,
    required this.accentColor,
    required this.description,
    required this.onTap,
  });

  final Character character;
  final bool selected;
  final Color accentColor;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _PortraitAvatar(
                character: character,
                selected: selected,
                size: 60,
              ),
              Positioned(
                left: -2,
                top: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                    border: Border.all(color: const Color(0xFFF6E8CB)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? const Color(0xFFFDF8EE)
                              : const Color(0xFF5C3A20),
                        ),
                      ),
                    ),
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFF7D881),
                          size: 16,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.2,
                    height: 1.18,
                    color: selected
                        ? const Color(0xFFF4E6CD)
                        : const Color(0xFF75563C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCompactCard extends StatelessWidget {
  const _StoryCompactCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.isCompleted,
    required this.highlightedCharacterCodes,
    required this.colorForCharacter,
    required this.nameForCharacter,
    required this.onTap,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isCompleted;
  final List<String> highlightedCharacterCodes;
  final Color Function(String characterCode) colorForCharacter;
  final String Function(String characterCode) nameForCharacter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      selected: selected,
      completed: isCompleted,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: isCompleted
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF92E3A3),
                    size: 18,
                  )
                : _IndexBadge(label: '$index'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.6,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    color: selected
                        ? const Color(0xFFFDF8EE)
                        : isCompleted
                        ? const Color(0xFF2F5D3B)
                        : const Color(0xFF5C3A20),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.3,
                    height: 1.18,
                    color: selected
                        ? const Color(0xFFF4E6CD)
                        : isCompleted
                        ? const Color(0xFF52725B)
                        : const Color(0xFF75563C),
                  ),
                ),
              ],
            ),
          ),
          if (highlightedCharacterCodes.isNotEmpty) ...[
            const SizedBox(width: 6),
            _CharacterNamePills(
              characterCodes: highlightedCharacterCodes,
              colorForCharacter: colorForCharacter,
              nameForCharacter: nameForCharacter,
            ),
          ],
        ],
      ),
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF4DA91),
        border: Border.all(color: const Color(0xFF7A4B21)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF5A3519),
        ),
      ),
    );
  }
}

/// 이야기 카드 우측 상단의 "등장 인물" 라벨 스택.
///
/// 기존 `_CharacterDots` (작은 색 점) 을 대체. 인물별로 배정된 색을 pill 배경으로
/// 쓰고, 그 위에 인물 이름을 작은 흰색 bold 텍스트로 얹는다. 카드 폭 제한 때문에
/// 최대 3명까지만 표시하고 초과분은 "+N" 으로 요약.
class _CharacterNamePills extends StatelessWidget {
  const _CharacterNamePills({
    required this.characterCodes,
    required this.colorForCharacter,
    required this.nameForCharacter,
  });

  final List<String> characterCodes;
  final Color Function(String characterCode) colorForCharacter;
  final String Function(String characterCode) nameForCharacter;

  @override
  Widget build(BuildContext context) {
    const maxShown = 3;
    final visible = characterCodes.take(maxShown).toList(growable: false);
    final overflow = characterCodes.length - visible.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final code in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _NamePill(
              color: colorForCharacter(code),
              label: nameForCharacter(code),
            ),
          ),
        if (overflow > 0)
          _NamePill(color: const Color(0xFF8E7B61), label: '+$overflow'),
      ],
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 76),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _PortraitAvatar extends StatelessWidget {
  const _PortraitAvatar({
    required this.character,
    required this.selected,
    this.size = 42,
  });

  final Character character;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 로컬 번들에 자산이 없으면 (신규 승인 캐릭터) Storage URL 로 fallback.
    // CharacterAvatar 의 정책과 동일.
    return _PortraitAvatarBody(
      character: character,
      selected: selected,
      size: size,
    );
  }
}

class _PortraitAvatarBody extends ConsumerWidget {
  const _PortraitAvatarBody({
    required this.character,
    required this.selected,
    required this.size,
  });

  final Character character;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarPath = character.avatarAssetPath.trim();
    final storagePath = character.avatarStoragePath?.trim();
    final fallbackText = character.name.trim().isEmpty
        ? '?'
        : character.name.trim().substring(0, 1);
    final fallback = _AvatarFallback(name: fallbackText, selected: selected);

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
          final bucket = storagePath.substring(0, slash);
          final p = storagePath.substring(slash + 1);
          storageUrl = client.storage.from(bucket).getPublicUrl(p);
        }
      } catch (_) {
        storageUrl = null;
      }
    }

    Widget child;
    if (avatarPath.isNotEmpty) {
      // canonical 로컬 thumb (인물 머리 상단 1/3 비율) — height*2 위쪽 자르기.
      child = ColoredBox(
        color: Colors.white,
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size,
            height: size * 2,
            child: Image.asset(
              avatarPath,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) {
                if (storageUrl == null) return fallback;
                return _StorageAvatar(url: storageUrl, fallback: fallback);
              },
            ),
          ),
        ),
      );
    } else if (storageUrl != null) {
      // 로컬 자산 없음 → Storage 원본 (정사각 정중앙 cover).
      child = _StorageAvatar(url: storageUrl, fallback: fallback);
    } else {
      child = fallback;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF8D4E05) : const Color(0xFFC9A06B),
          width: selected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: child),
    );
  }
}

class _StorageAvatar extends StatelessWidget {
  const _StorageAvatar({required this.url, required this.fallback});
  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    // Imagen 1024×1024 인물 정중앙 → 상반신만 보이도록 topCenter 기준 1.5× 확대.
    return ColoredBox(
      color: Colors.white,
      child: Transform.scale(
        scale: 1.5,
        alignment: Alignment.topCenter,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, error, _) {
            debugPrint('[portrait] storage failed url=$url error=$error');
            return fallback;
          },
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const ColoredBox(color: Color(0xFFE7D2B2)),
        ),
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
    return Container(
      color: selected ? const Color(0xFF8C6337) : const Color(0xFFA98657),
      alignment: Alignment.center,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// Step 3 상단 툴바 — 전체 선택 / 전체 해제 버튼과 선택 카운터.
///
/// 버튼은 의미 없는 상태(이미 전체 선택됨 → 전체 선택 비활성)에서 null 을
/// 받아 disabled. 선택 카운터 `N / M` 표시.
class _StoryBulkActionsBar extends StatelessWidget {
  const _StoryBulkActionsBar({
    required this.total,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  final int total;
  final int selectedCount;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeselectAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          _BulkActionChip(
            label: '전체 선택',
            icon: Icons.done_all_rounded,
            onTap: onSelectAll,
          ),
          const SizedBox(width: 6),
          _BulkActionChip(
            label: '전체 해제',
            icon: Icons.remove_done_rounded,
            onTap: onDeselectAll,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF4DA91),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF7A4B21)),
            ),
            child: Text(
              '$selectedCount / $total',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5A3519),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkActionChip extends StatelessWidget {
  const _BulkActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFFE7D2B2)
                : const Color(0xFFE7D2B2).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFB78A63)
                  : const Color(0xFFB78A63).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled
                    ? const Color(0xFF5C3A20)
                    : const Color(0xFF5C3A20).withValues(alpha: 0.4),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: enabled
                      ? const Color(0xFF5C3A20)
                      : const Color(0xFF5C3A20).withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
