import 'package:flutter/material.dart';

import 'image_zoom_dialog.dart';

/// 제안 작성 Step 4 맨 위에 띄우는 "이 이야기에 등장할 인물" 요약 카드.
///
/// 좌우 2-col 레이아웃:
///  - 왼쪽 col: 헤더 + 설명 텍스트
///  - 오른쪽 col: 큰 아바타 (가로 스크롤). 클릭 시 [showImageZoomDialog] 으로 확대.
///
/// 의도적으로 input 은 받지 않는다 — 인물 편집은 Step 2 에서 이미 끝났고,
/// 이 시점엔 확정된 상태.
class ProposalCharacterRow extends StatelessWidget {
  const ProposalCharacterRow({super.key, required this.characters});

  /// 표시할 인물 목록. 코드/이름/아바타 URL(nullable) 로 단순화.
  final List<ProposalCharacterRowItem> characters;

  /// 우측 큰 아바타의 고정 사이즈(정사각형). 컨테이너 최소 높이도 이 값에
  /// 라벨 높이를 더한 만큼이 된다.
  static const double _avatarBoxSize = 140;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (characters.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '등장 인물이 선택되지 않았습니다. 이전 단계에서 인물을 먼저 골라주세요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI 이미지 생성에 참조할 인물',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '아래 아바타가 각 장면 이미지에 "이 사람" 으로 일관되게 그려집니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '아바타를 누르면 크게 볼 수 있어요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 우측: 큰 아바타 가로 리스트 — 정사각형 box 높이가 컨테이너 높이를 결정.
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _avatarBoxSize * 2 + 32,
            ),
            child: SizedBox(
              height: _avatarBoxSize + 24, // 아바타 + 이름 라벨
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < characters.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      _CharacterChip(item: characters[i], size: _avatarBoxSize),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProposalCharacterRowItem {
  const ProposalCharacterRowItem({
    required this.code,
    required this.name,
    this.avatarUrl,
  });

  final String code;
  final String name;
  final String? avatarUrl;
}

class _CharacterChip extends StatelessWidget {
  const _CharacterChip({required this.item, required this.size});
  final ProposalCharacterRowItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final avatarUrl = item.avatarUrl;
    final tappable = avatarUrl != null;
    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.2),
      ),
      child: avatarUrl == null
          ? Center(
              child: Text(
                _initial(item.name),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  _initial(item.name),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: tappable
                ? () => showImageZoomDialog(context, url: avatarUrl)
                : null,
            child: avatar,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size + 8),
          child: Text(
            item.name,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first;
  }
}
