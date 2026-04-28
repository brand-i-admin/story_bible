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

class _PersonCompactCard extends StatelessWidget {
  const _PersonCompactCard({
    required this.person,
    required this.selected,
    required this.accentColor,
    required this.description,
    required this.onTap,
  });

  final Person person;
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
              _PortraitAvatar(person: person, selected: selected, size: 60),
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
                        person.name,
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
    required this.highlightedPersonIds,
    required this.colorForPerson,
    required this.onTap,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isCompleted;
  final List<String> highlightedPersonIds;
  final Color Function(String personId) colorForPerson;
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
          if (highlightedPersonIds.isNotEmpty) ...[
            const SizedBox(width: 6),
            _PersonDots(
              personIds: highlightedPersonIds,
              colorForPerson: colorForPerson,
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

class _PersonDots extends StatelessWidget {
  const _PersonDots({required this.personIds, required this.colorForPerson});

  final List<String> personIds;
  final Color Function(String personId) colorForPerson;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: personIds
          .take(3)
          .map((personId) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorForPerson(personId),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _PortraitAvatar extends StatelessWidget {
  const _PortraitAvatar({
    required this.person,
    required this.selected,
    this.size = 42,
  });

  final Person person;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarPath = person.avatarAssetPath.trim();
    final fallbackText = person.name.trim().isEmpty
        ? '?'
        : person.name.trim().substring(0, 1);

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
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _AvatarFallback(name: fallbackText, selected: selected)
            : ColoredBox(
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
                      errorBuilder: (_, __, ___) => _AvatarFallback(
                        name: fallbackText,
                        selected: selected,
                      ),
                    ),
                  ),
                ),
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
