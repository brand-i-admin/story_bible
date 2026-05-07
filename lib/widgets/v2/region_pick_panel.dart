import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../models/landmark.dart';

/// 지역 모드 1단계 — 선택된 시대(들)에 해당하는 region 후보를 시트 안에서도
/// 고를 수 있게 표시. 사용자는 지도에서 마커를 누르거나 여기서 카드를 누르거나
/// 둘 다 가능.
class RegionPickPanel extends StatelessWidget {
  const RegionPickPanel({
    super.key,
    required this.regions,
    required this.allEras,
    required this.selectedEraIds,
    required this.selectedLandmarkId,
    required this.onSelect,
  });

  final List<Landmark> regions;
  final List<Era> allEras;
  final Set<String> selectedEraIds;
  final String? selectedLandmarkId;
  final ValueChanged<Landmark> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedEraCodes = allEras
        .where((e) => selectedEraIds.contains(e.id))
        .map((e) => e.code)
        .toSet();

    // 시대 그룹별로 묶어 보여 준다 (시대 순서 유지). 한 region 이 여러 시대에
    // 걸쳐 있으면 가장 첫 번째 시대 그룹에만 표시.
    final orderedEras = [...allEras]
      ..sort((a, b) {
        final cmpT = _testamentRank(
          a.testament,
        ).compareTo(_testamentRank(b.testament));
        if (cmpT != 0) return cmpT;
        return a.displayOrder.compareTo(b.displayOrder);
      });

    final used = <String>{};
    final byEra = <Era, List<Landmark>>{};
    for (final era in orderedEras) {
      if (!selectedEraIds.contains(era.id)) continue;
      final list = <Landmark>[];
      for (final r in regions) {
        if (used.contains(r.id)) continue;
        if (r.eraCodes.isEmpty || r.eraCodes.contains(era.code)) {
          list.add(r);
          used.add(r.id);
        }
      }
      list.sort((a, b) => b.displayPriority.compareTo(a.displayPriority));
      if (list.isNotEmpty) byEra[era] = list;
    }

    if (regions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '선택한 시대에 해당하는 지역이 없습니다.\n시대를 더 추가해 보세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        // v3 — '여행할 지역을 골라주세요' 헤더 + 안내문 제거. 단계 이동은 우측
        // 상단 stepper 가 담당하고, region 카드 자체로 의도가 명확.
        for (final entry in byEra.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.key.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.value.length}곳',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (_, constraints) {
              // 2개씩 한 줄에 표시 — 부모 폭에서 spacing 8 빼고 절반.
              final cardWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in entry.value)
                    _RegionCard(
                      landmark: r,
                      selected: r.id == selectedLandmarkId,
                      onTap: () => onSelect(r),
                      width: cardWidth,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (selectedEraCodes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '⚠️ 시대가 선택되지 않았습니다. 홈에서 시대를 먼저 켜주세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

int _testamentRank(String t) {
  switch (t.toLowerCase().trim()) {
    case 'new':
    case 'nt':
    case 'new_testament':
      return 1;
    default:
      return 0;
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.landmark,
    required this.selected,
    required this.onTap,
    required this.width,
  });
  final Landmark landmark;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text(landmark.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      landmark.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if ((landmark.description ?? '').isNotEmpty)
                      Text(
                        landmark.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
