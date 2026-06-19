// 부모 라이브러리: lib/widgets/story_selection_panel.dart
//
// 시대/인물/이야기 선택 카드와 카드 셸, 인덱스 배지, 인물 도트, 초상 아바타
// 등 카드형 UI를 모은 파트 파일.
part of '../story_selection_panel.dart';

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
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
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFAE6D37), Color(0xFF87502A)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE7D2B2), Color(0xFFDDC29E)],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF4D58A)
                  : const Color(0xFFB78A63),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.12 : 0.07),
                blurRadius: selected ? 8 : 4,
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
            child: Text.rich(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              TextSpan(
                children: [
                  TextSpan(
                    text: era.name,
                    style: TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.parchmentCream
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
    required this.eventCount,
    required this.onTap,
  });

  final Character character;
  final bool selected;
  final Color accentColor;
  final int eventCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final identityLabel = _identityLabelFor(character);
    return _CardShell(
      selected: selected,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _PortraitAvatar(
                character: character,
                selected: selected,
                size: 46,
              ),
              Positioned(
                left: -2,
                top: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                    border: Border.all(color: const Color(0xFFF6E8CB)),
                  ),
                ),
              ),
              Positioned(
                right: -9,
                top: 2,
                child: _EventCountBadge(count: eventCount, selected: selected),
              ),
              if (selected)
                const Positioned(
                  right: -4,
                  bottom: -2,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFF7D881),
                    size: 14,
                    shadows: [Shadow(color: Color(0xFF3A2308), blurRadius: 2)],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            character.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected
                  ? AppColors.parchmentCream
                  : const Color(0xFF5C3A20),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            identityLabel,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.1,
              height: 1.08,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFFF4E6CD)
                  : const Color(0xFF75563C),
            ),
          ),
        ],
      ),
    );
  }

  String _identityLabelFor(Character character) {
    final tagline = character.tagline?.trim() ?? '';
    if (tagline.isNotEmpty) {
      return _wrapIdentityLabel(tagline);
    }
    final description = character.description?.trim() ?? '';
    if (description.isEmpty) {
      return '성경 인물';
    }
    return _wrapIdentityLabel(description.split(RegExp(r'[.。]')).first.trim());
  }

  String _wrapIdentityLabel(String label) {
    const maxUnitsPerLine = 6;
    final words = label
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty);
    final lines = <String>[];
    var currentLine = '';
    for (final word in words) {
      final nextLine = currentLine.isEmpty ? word : '$currentLine $word';
      if (currentLine.isNotEmpty && _labelUnits(nextLine) > maxUnitsPerLine) {
        lines.add(currentLine);
        currentLine = word;
      } else {
        currentLine = nextLine;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    return lines.join('\n');
  }

  int _labelUnits(String value) {
    return value.runes
        .where((rune) => String.fromCharCode(rune).trim().isNotEmpty)
        .length;
  }
}

class _EventCountBadge extends StatelessWidget {
  const _EventCountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF7D881) : const Color(0xFF7A5F35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? const Color(0xFF5A3519) : const Color(0xFFF6E8CB),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.4,
          height: 1,
          fontWeight: FontWeight.w900,
          color: selected ? const Color(0xFF5A3519) : AppColors.parchmentCream,
        ),
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
