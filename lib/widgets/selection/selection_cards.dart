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
                              ? AppColors.parchmentCream
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

/// step 3 사건 선택 카드 — 그림 1 디자인.
/// 원형 썸네일(SceneAssetLoader 첫 장면) + 제목 + 위치·연도(같은 줄) + 인물 라벨(아바타+이름).
class _StoryCompactCard extends StatelessWidget {
  const _StoryCompactCard({
    required this.index,
    required this.event,
    required this.selected,
    required this.isCompleted,
    required this.highlightedCharacterCodes,
    required this.charactersByCode,
    required this.sceneAssetLoader,
    required this.onTap,
  });

  final int index;
  final StoryEvent event;
  final bool selected;
  final bool isCompleted;
  final List<String> highlightedCharacterCodes;

  /// code → Character 매핑 (아바타 표시용).
  final Map<String, Character> charactersByCode;
  final SceneAssetLoader sceneAssetLoader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = selected
        ? AppColors.parchmentCream
        : isCompleted
        ? const Color(0xFF2F5D3B)
        : const Color(0xFF5C3A20);
    final placeName = event.placeName;
    final startYear = event.startYear;
    final yearLabel = startYear == null
        ? null
        : (startYear < 0 ? 'B.C. ${-startYear}' : 'A.D. $startYear');

    return _CardShell(
      selected: selected,
      completed: isCompleted,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 원형 썸네일 + 좌상단 인덱스 배지
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: Container(
                  width: 60,
                  height: 60,
                  color: const Color(0xFFF1E4C8),
                  alignment: Alignment.center,
                  child: _StoryCardThumbnail(
                    event: event,
                    loader: sceneAssetLoader,
                  ),
                ),
              ),
              Positioned(
                top: -4,
                left: -4,
                child: isCompleted
                    ? Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF49A357),
                          size: 18,
                        ),
                      )
                    : _IndexBadge(label: '$index'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 제목
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          // 지역 + 연도 같은 줄
          if ((placeName != null && placeName.isNotEmpty) || yearLabel != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (placeName != null && placeName.isNotEmpty) ...[
                  Icon(
                    Icons.location_on,
                    size: 10,
                    color: selected
                        ? const Color(0xFFF4E6CD)
                        : const Color(0xFF8C6743),
                  ),
                  const SizedBox(width: 1),
                  Flexible(
                    child: Text(
                      placeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFFF4E6CD)
                            : const Color(0xFF8C6743),
                      ),
                    ),
                  ),
                ],
                if (placeName != null &&
                    placeName.isNotEmpty &&
                    yearLabel != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '·',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFFF4E6CD)
                            : const Color(0xFF8C6743),
                      ),
                    ),
                  ),
                if (yearLabel != null)
                  Text(
                    yearLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFFF4E6CD)
                          : const Color(0xFF8C6743),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 4),
          // 인물 라벨 — 작은 아바타 + 이름
          if (highlightedCharacterCodes.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final code in highlightedCharacterCodes.take(3))
                  _CharacterPillWithAvatar(
                    character: charactersByCode[code],
                    name: charactersByCode[code]?.name ?? code,
                    selected: selected,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 카드 썸네일 — SceneAssetLoader 로 첫 장면 이미지 비동기 로드.
/// 자세히 보기 팝업이 사용하는 동일 로직(loadForEvent) 으로 첫 결과 사용.
class _StoryCardThumbnail extends StatelessWidget {
  const _StoryCardThumbnail({required this.event, required this.loader});
  final StoryEvent event;
  final SceneAssetLoader loader;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: loader.loadForEvent(event),
      builder: (_, snap) {
        const placeholder = Icon(
          Icons.menu_book,
          color: Color(0xFF8C6743),
          size: 22,
        );
        if (!snap.hasData || snap.data!.isEmpty) return placeholder;
        final path = snap.data!.first;
        if (path.startsWith('http')) {
          return Image.network(
            path,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );
        }
        return Image.asset(
          path,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        );
      },
    );
  }
}

class _CharacterPillWithAvatar extends StatelessWidget {
  const _CharacterPillWithAvatar({
    required this.character,
    required this.name,
    required this.selected,
  });
  final Character? character;
  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFF4E6CD).withValues(alpha: 0.4)
            : const Color(0xFF3F8FB6).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (character != null)
            ClipOval(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CharacterAvatar(character: character!, size: 14),
              ),
            )
          else
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF3F8FB6),
              ),
            ),
          const SizedBox(width: 3),
          Text(
            name,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF2A6F92),
            ),
          ),
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
