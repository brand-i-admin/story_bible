import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../theme/era_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../story_home_styles.dart';

/// 시대 선택 칩 — 구약/신약 두 줄. HomeIntroPanel 과 ProfileTabPage 의
/// "장소로 시작" 탭이 공유한다.
///
/// 비선택 시 시대 고유 색([EraColors.forCode]) 점 + 아이콘 노출, 선택 시
/// 갈색 그라데이션 활성 표시. 같은 시대 색은 지도 폴리곤에도 사용된다.
class EraPickRows extends StatelessWidget {
  const EraPickRows({
    super.key,
    required this.eras,
    required this.selectedEraId,
    required this.onSelectEra,
    this.gap = 8,
    this.trailingScrollPadding = 0,
  });

  final List<Era> eras;
  final String? selectedEraId;
  final ValueChanged<String> onSelectEra;

  /// 두 row 사이 세로 간격.
  final double gap;

  /// 스크롤 끝에서 마지막 칩이 패널 둥근 모서리에 붙지 않도록 남기는 여백.
  final double trailingScrollPadding;

  @override
  Widget build(BuildContext context) {
    final old = _filterAndSort(eras, isNew: false);
    final newT = _filterAndSort(eras, isNew: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EraPickRow(
          label: '구약',
          eras: old,
          selectedEraId: selectedEraId,
          onSelectEra: onSelectEra,
          trailingScrollPadding: trailingScrollPadding,
        ),
        SizedBox(height: gap),
        EraPickRow(
          label: '신약',
          eras: newT,
          selectedEraId: selectedEraId,
          onSelectEra: onSelectEra,
          trailingScrollPadding: trailingScrollPadding,
        ),
      ],
    );
  }

  static List<Era> _filterAndSort(List<Era> all, {required bool isNew}) {
    bool isNt(Era e) {
      final t = e.testament.toLowerCase().trim();
      return t == 'new' || t == 'nt' || t == 'new_testament';
    }

    final filtered =
        all.where((e) => isNt(e) == isNew && !isHiddenEraCode(e.code)).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return filtered;
  }
}

/// 한 row (구약 또는 신약) — 좌측 라벨 + 가로 스크롤 칩 리스트.
class EraPickRow extends StatelessWidget {
  const EraPickRow({
    super.key,
    required this.label,
    required this.eras,
    required this.selectedEraId,
    required this.onSelectEra,
    this.trailingScrollPadding = 0,
  });

  final String label;
  final List<Era> eras;
  final String? selectedEraId;
  final ValueChanged<String> onSelectEra;
  final double trailingScrollPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '$label:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: trailingScrollPadding > 0
                ? EdgeInsetsDirectional.only(end: trailingScrollPadding)
                : null,
            child: Row(
              children: [
                for (var i = 0; i < eras.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _EraChip(
                    era: eras[i],
                    selected: selectedEraId == eras[i].id,
                    onTap: () => onSelectEra(eras[i].id),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EraChip extends StatelessWidget {
  const _EraChip({
    required this.era,
    required this.selected,
    required this.onTap,
  });
  final Era era;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eraColor = EraColors.forCode(era.code);
    final iconData = eraIconFor(era.code);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        splashColor: AppColors.brownWarm.withValues(alpha: 0.18),
        highlightColor: AppColors.brownWarm.withValues(alpha: 0.10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x2,
          ),
          decoration: softButtonDecoration(selected: selected),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!selected) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: eraColor,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Icon(
                iconData,
                size: 14,
                color: selected ? AppColors.parchmentCream : eraColor,
              ),
              const SizedBox(width: 4),
              Text(
                _shortEraLabel(era),
                style: AppTextStyles.chipLabel.copyWith(
                  fontSize: 11.5,
                  color: selected ? AppColors.parchmentCream : AppColors.ink800,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.check_circle,
                  size: 13,
                  color: AppColors.parchmentCream,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _shortEraLabel(Era era) {
  switch (era.code) {
    case 'era_patriarch':
      return '족장';
    case 'era_exodus':
      return '출애굽';
    case 'era_judges':
      return '사사';
    case 'era_monarchy':
      return '통일 왕국';
    case 'era_divided_kingdom':
      return '분열왕국';
    case 'era_exile_return':
      return '포로 및 포로 후기';
    case 'era_nt_apostolic':
      return '사도';
    case 'era_nt_post_apostolic':
      return '후기 사도';
  }

  return era.name
      .replaceFirst(RegExp(r'의 시대$'), '')
      .replaceFirst(RegExp(r' 시대$'), '');
}

/// 시대 코드 → Material 아이콘 매핑. 향후 일러스트 PNG 로 교체할 때 한 곳만 수정.
IconData eraIconFor(String code) {
  switch (code) {
    case 'era_primeval':
      return Icons.terrain;
    case 'era_patriarch':
      return Icons.holiday_village;
    case 'era_exodus':
      return Icons.directions_walk;
    case 'era_judges':
      return Icons.shield;
    case 'era_monarchy':
      return Icons.workspace_premium;
    case 'era_divided_kingdom':
      return Icons.call_split;
    case 'era_exile_return':
      return Icons.location_city;
    case 'era_nt_public_ministry':
      return Icons.auto_awesome;
    case 'era_nt_apostolic':
      return Icons.sailing;
    case 'era_nt_post_apostolic':
      return Icons.menu_book;
    case 'era_nt_consummation':
      return Icons.local_fire_department;
    default:
      return Icons.public;
  }
}
