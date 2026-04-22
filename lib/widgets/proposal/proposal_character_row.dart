import 'package:flutter/material.dart';

/// 제안 작성 Step 4 맨 위에 띄우는 "이 이야기에 등장할 인물" 요약 카드.
///
/// 선택된 인물들의 아바타(supabase storage public URL 또는 로컬 asset) 와
/// 이름을 가로 스크롤 가능한 나열로 보여준다. 장면 이미지 생성 시 어떤 인물
/// 참조 이미지가 AI 에게 전달되는지 사용자가 먼저 확인할 수 있게 함이 목적.
///
/// 의도적으로 input 은 받지 않는다 — 인물 편집은 Step 2 에서 이미 끝났고,
/// 이 시점엔 확정된 상태.
class ProposalCharacterRow extends StatelessWidget {
  const ProposalCharacterRow({super.key, required this.characters});

  /// 표시할 인물 목록. 코드/이름/아바타 URL(nullable) 로 단순화.
  final List<ProposalCharacterRowItem> characters;

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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 이미지 생성에 참조할 인물',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '아래 아바타가 각 장면 이미지에 "이 사람" 으로 일관되게 그려집니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: characters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _CharacterChip(item: characters[i]),
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
  const _CharacterChip({required this.item});
  final ProposalCharacterRowItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = item.avatarUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: avatarUrl == null
              ? Center(
                  child: Text(
                    _initial(item.name),
                    style: theme.textTheme.titleMedium?.copyWith(
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
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
