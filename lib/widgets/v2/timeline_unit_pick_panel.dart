import 'package:flutter/material.dart';

import '../../models/story_event.dart';
import '../../theme/tokens.dart';

double timelineUnitPickPanelSheetHeightFor(BuildContext context) {
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  final extra = ((textScale - 1) * 125).clamp(0.0, 56.0).toDouble();
  return 230 + extra;
}

class TimelineUnitPickPanel extends StatelessWidget {
  const TimelineUnitPickPanel({
    super.key,
    required this.events,
    required this.selectedUnitCodes,
    required this.onToggleUnit,
    required this.onSelectAll,
    required this.onClearAll,
    this.bottomInset = 0,
  });

  final List<StoryEvent> events;
  final Set<String> selectedUnitCodes;
  final ValueChanged<String> onToggleUnit;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = _timelineUnits(events);
    if (units.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Text(
            '선택한 시대에 표시할 구간이 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const cardGap = 8.0;
        const visibleCards = 3.5;
        final allSelected = units.every(
          (unit) => selectedUnitCodes.contains(unit.code),
        );
        final cardWidth =
            ((constraints.maxWidth -
                        horizontalPadding * 2 -
                        cardGap * (visibleCards - 1)) /
                    visibleCards)
                .clamp(86.0, 124.0)
                .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                horizontalPadding,
                6,
                horizontalPadding,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '구간 선택',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.ink700,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('timeline-unit-toggle-all'),
                    onPressed: allSelected ? onClearAll : onSelectAll,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      foregroundColor: allSelected
                          ? AppColors.greenBot
                          : AppColors.ink600,
                      backgroundColor: allSelected
                          ? AppColors.greenTint2
                          : AppColors.parchmentCream,
                      side: BorderSide(
                        color: allSelected
                            ? AppColors.greenBot
                            : AppColors.borderCard,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: Text(allSelected ? '전체 해제' : '전체 선택'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  12 + bottomInset,
                ),
                itemCount: units.length,
                separatorBuilder: (_, _) => const SizedBox(width: cardGap),
                itemBuilder: (context, index) {
                  final unit = units[index];
                  return Align(
                    alignment: Alignment.topLeft,
                    child: _TimelineUnitCard(
                      key: ValueKey('timeline-unit-card-${unit.code}'),
                      unit: unit,
                      selected: selectedUnitCodes.contains(unit.code),
                      width: cardWidth,
                      onTap: () => onToggleUnit(unit.code),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineUnit {
  const _TimelineUnit({
    required this.code,
    required this.title,
    required this.order,
    required this.events,
  });

  final String code;
  final String title;
  final int order;
  final List<StoryEvent> events;

  static const int _maxSubtitleCharacters = 35;
  static const Map<String, String> _curatedUnitDescriptions = {
    'primeval_creation_mission': '세상을 창조하시고 사람에게 처음 사명을 맡기십니다',
    'primeval_outside_eden': '에덴 밖 죄와 심판 속에서도 은혜가 이어집니다',
    'patriarch_abraham_isaac_promise': '아브라함과 이삭의 믿음 안에 약속이 이어집니다',
    'patriarch_jacob_israel': '언약의 길에서 야곱이 새 이름으로 빚어집니다',
    'patriarch_joseph_egypt': '요셉의 고난을 통해 애굽 구원의 길이 열립니다',
    'exodus_egypt_red_sea': '애굽의 압제에서 홍해 구원까지 함께 따라갑니다',
    'exodus_wilderness_covenant': '광야에서 언약 백성으로 살아가도록 훈련됩니다',
    'exodus_canaan_joshua': '가나안에 들어가 여호수아와 언약을 선택합니다',
    'judges_deliverers_cycles': '사사들을 통해 반복되는 위기와 구원을 봅니다',
    'judges_ruth_boaz': '룻과 보아스의 기업 무름 속 은혜를 따라갑니다',
    'judges_samuel_transition': '사무엘을 통해 왕정으로 향하는 문이 열립니다',
    'monarchy_saul_rise_fall': '이스라엘의 사울 왕국 시작과 몰락을 따라봅니다',
    'monarchy_david_covenant_fracture': '다윗 왕국의 언약과 집안의 균열을 함께 봅니다',
    'monarchy_solomon_temple_fall': '솔로몬의 지혜와 성전, 타락의 흐름을 봅니다',
    'divided_split_early_evil': '왕국 분열 뒤 초기 왕조의 악이 뿌리내립니다',
    'divided_elijah_ahab_word': '엘리야가 아합 집 앞에서 참 말씀을 전합니다',
    'divided_elisha_jehu_judgment': '엘리사의 표징과 예후의 심판을 함께 따라봅니다',
    'divided_two_kingdoms_north_fall': '두 왕국이 흔들리다 북이스라엘이 끝내 무너집니다',
    'divided_judah_final_fall': '남유다가 마지막 경고와 회복 뒤 결국 멸망합니다',
    'exile_hope_temple_restored': '포로지의 소망에서 성전 회복까지 함께 이어집니다',
    'exile_esther_reversal': '에스더를 통해 백성의 죽음 위기가 뒤집힙니다',
    'exile_ezra_nehemiah_community': '말씀과 성벽을 따라 공동체가 다시 세워집니다',
    'birth_early_ministry': '탄생과 세례를 지나 예수님의 사역 길이 열립니다',
    'galilee_ministry': '갈릴리에서 치유와 가르침의 사역이 펼쳐집니다',
    'journey_teaching_to_jerusalem': '예루살렘을 향한 길에서 제자들이 깊이 배웁니다',
    'passion_week': '고난주간에 십자가의 길과 새 언약이 드러납니다',
    'resurrection_ascension': '부활하신 예수님이 제자들에게 사명을 맡기십니다',
    'jerusalem_church_expansion': '성령 안에서 교회가 태어나 복음이 멀리 퍼집니다',
    'paul_first_journey': '바울과 바나바가 첫 전도 여행의 길을 열어갑니다',
    'paul_second_journey': '마게도냐와 헬라로 복음의 길이 더 넓어집니다',
    'paul_third_journey': '교회들을 굳게 세우며 말씀 사역이 깊어집니다',
    'paul_arrest_rome_witness': '체포와 재판 속에서도 로마까지 복음이 갑니다',
    'scattered_faith_foundations': '흩어진 성도들이 믿음의 기초를 굳게 붙듭니다',
    'paul_churches_problems_hope': '바울이 교회의 문제와 소망을 편지로 다룹니다',
    'roman_prison_churches': '감옥에서도 복음은 교회를 세우며 계속 전해집니다',
    'next_generation_suffering_church': '다음 세대와 고난 속 교회를 끝까지 세웁니다',
    'patmos_seven_churches': '밧모섬 환상으로 일곱 교회를 다시 깨우십니다',
    'revelation_safe_vision_flow': '계시록의 큰 환상이 새 창조 소망으로 이어집니다',
  };

  String get subtitle {
    if (events.isEmpty) {
      return '사건 없음';
    }
    final curated = _curatedUnitDescriptions[code];
    if (curated != null) {
      return _fitSubtitle(curated);
    }
    if (events.length == 1) {
      return _fitSubtitle('$title 이야기를 봅니다');
    }
    return _fitSubtitle('$title 흐름을 이어 봅니다');
  }

  String get numberedTitle => '$order. $title';

  static String _asSentence(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (RegExp(r'[.!?。！？]$').hasMatch(trimmed)) {
      return trimmed;
    }
    return '$trimmed.';
  }

  static String _fitSubtitle(String value) {
    final hasTerminalPunctuation = RegExp(r'[.!?。！？]$').hasMatch(value.trim());
    final maxCharacters = hasTerminalPunctuation
        ? _maxSubtitleCharacters
        : _maxSubtitleCharacters - 1;
    return _asSentence(_shortenPhrase(value, maxCharacters));
  }

  static String _shortenPhrase(String value, int maxCharacters) {
    var normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    normalized = normalized.replaceFirst(RegExp(r'[.!?。！？]+$'), '');
    if (_charLength(normalized) <= maxCharacters) {
      return normalized;
    }
    final chars = normalized.runes.toList();
    var cut = String.fromCharCodes(chars.take(maxCharacters)).trimRight();
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace >= (maxCharacters * 0.68).floor()) {
      cut = cut.substring(0, lastSpace).trimRight();
    }
    return cut.replaceFirst(RegExp(r'[,.，、]+$'), '').trimRight();
  }

  static int _charLength(String value) => value.runes.length;
}

List<_TimelineUnit> _timelineUnits(List<StoryEvent> events) {
  final byCode = <String, List<StoryEvent>>{};
  for (final event in events) {
    byCode.putIfAbsent(event.unitCode, () => <StoryEvent>[]).add(event);
  }
  final units = <_TimelineUnit>[];
  for (final entry in byCode.entries) {
    final unitEvents = [...entry.value]
      ..sort((a, b) {
        final cmp = a.globalRank.compareTo(b.globalRank);
        if (cmp != 0) return cmp;
        return a.storyIndex.compareTo(b.storyIndex);
      });
    final first = unitEvents.first;
    units.add(
      _TimelineUnit(
        code: first.unitCode,
        title: first.unitTitle,
        order: first.unitOrder,
        events: unitEvents,
      ),
    );
  }
  units.sort((a, b) {
    final cmp = a.order.compareTo(b.order);
    if (cmp != 0) return cmp;
    return a.title.compareTo(b.title);
  });
  return units;
}

class _TimelineUnitCard extends StatelessWidget {
  const _TimelineUnitCard({
    super.key,
    required this.unit,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final _TimelineUnit unit;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  static double _cardHeightFor(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final extra = ((textScale - 1) * 130).clamp(0.0, 56.0).toDouble();
    return 136 + extra;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardHeight = _cardHeightFor(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    const selectedColor = AppColors.greenBot;
    final bodyColor = selected ? AppColors.ink600 : AppColors.ink350;
    final titleText = Text(
      unit.numberedTitle,
      maxLines: largeText ? null : 3,
      overflow: largeText ? TextOverflow.visible : TextOverflow.clip,
      softWrap: true,
      style: theme.textTheme.labelLarge?.copyWith(
        color: AppColors.ink800,
        fontSize: 11.2,
        fontWeight: FontWeight.w800,
        height: 1.12,
      ),
    );
    final countText = Text(
      '${unit.events.length}개 이야기',
      style: theme.textTheme.labelSmall?.copyWith(
        color: selectedColor,
        fontSize: 10.6,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    );
    final subtitleText = Text(
      unit.subtitle,
      maxLines: largeText ? null : 4,
      overflow: largeText ? TextOverflow.visible : TextOverflow.clip,
      softWrap: true,
      style: theme.textTheme.bodySmall?.copyWith(
        color: bodyColor,
        fontSize: 9.4,
        height: 1.16,
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: largeText ? MainAxisSize.min : MainAxisSize.max,
      children: [
        largeText ? titleText : Flexible(fit: FlexFit.loose, child: titleText),
        const SizedBox(height: 2),
        countText,
        const SizedBox(height: AppSpacing.x1),
        largeText ? subtitleText : Expanded(child: subtitleText),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: SizedBox(
          width: width,
          height: cardHeight,
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: selected ? AppColors.greenTint2 : AppColors.parchmentCard,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: selected ? selectedColor : AppColors.borderCard,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected ? AppShadows.green : AppShadows.sm,
            ),
            child: largeText ? SingleChildScrollView(child: content) : content,
          ),
        ),
      ),
    );
  }
}
