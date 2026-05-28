part of 'story_home_screen.dart';

enum _SelectionMode { character, region }

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

/// 지도 상단의 랜드마크 카테고리 필터 칩 가로 스크롤 바.
/// 비어 있으면 모든 카테고리 통과(전체 표시), 한 칩 누르면 그 카테고리만.
class _LandmarkCategoryChipsBar extends StatefulWidget {
  const _LandmarkCategoryChipsBar({
    required this.state,
    required this.onToggle,
    required this.onClear,
    required this.onLandmarkTap,
  });

  final StoryState state;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;
  final ValueChanged<Landmark> onLandmarkTap;

  // 키 = DB category, 값 = (이모지, 한국어 라벨).
  static const Map<String, (String, String)> _catMeta = {
    'region': ('🌍', '지역'),
    'city': ('🏛️', '도시'),
    'mountain': ('⛰️', '산'),
    'water': ('🌊', '물·강'),
    'river': ('💧', '강'),
    'sea': ('🌊', '바다'),
    'island': ('🏝️', '섬'),
    'wilderness': ('🏜️', '광야'),
    'campsite': ('⛺', '진영'),
    'palace': ('👑', '궁전'),
    'holy_site': ('🕊️', '거룩한 곳'),
    'temple': ('⛪', '성전'),
    'tomb': ('⚰️', '무덤'),
    'monument': ('🪨', '기념비'),
    'prison': ('⛓️', '감옥'),
    'battle': ('⚔️', '전투'),
    'city_gate': ('🚪', '성문'),
  };

  @override
  State<_LandmarkCategoryChipsBar> createState() =>
      _LandmarkCategoryChipsBarState();
}

class _LandmarkCategoryChipsBarState extends State<_LandmarkCategoryChipsBar> {
  /// 현재 inline 으로 펼쳐진 카테고리. null 이면 dropdown 닫힘. 필터의
  /// selectedLandmarkCategories 와는 별개 — 토글 끄기 시에는 dropdown 안 펼쳐짐.
  String? _expandedCat;

  /// 칩별 GlobalKey — dropdown 이 그 칩 RenderBox 좌표를 읽어
  /// viewport 안으로 clamp 되도록 위치 계산.
  final Map<String, GlobalKey> _chipKeys = {};

  /// Overlay 에 dropdown 을 렌더해 부모 Positioned hit-test 영역 제약을 우회.
  final OverlayPortalController _portalController = OverlayPortalController();

  /// 현재 build 컨텍스트에서 사용한 dropdown payload 를 overlay child 빌더가
  /// 참조하도록 캐시. expanded 가 바뀔 때마다 setState 로 재할당.
  _DropdownPayload? _dropdownPayload;

  GlobalKey _keyFor(String cat) =>
      _chipKeys.putIfAbsent(cat, () => GlobalKey());

  void _onChipTap(String cat) {
    final wasActive = widget.state.selectedLandmarkCategories.contains(cat);
    widget.onToggle(cat);
    setState(() {
      // 활성 → 비활성: dropdown 안 열고 닫는다.
      // 비활성 → 활성: 그 카테고리 dropdown 펼친다.
      // 다른 카테고리에서 새 카테고리로 전환: 새 카테고리 dropdown 펼친다.
      _expandedCat = wasActive ? null : cat;
    });
  }

  void _onClearAll() {
    widget.onClear();
    setState(() => _expandedCat = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 그 시대 랜드마크의 카테고리별 카운트.
    final eraCode = state.eras
        .where((e) => e.id == state.selectedEraId)
        .firstOrNull
        ?.code;
    if (eraCode == null) return const SizedBox.shrink();

    final countByCategory = <String, int>{};
    final landmarksByCategory = <String, List<Landmark>>{};
    var totalCount = 0;
    for (final l in state.landmarks) {
      if (l.isRegion) continue; // region 은 폴리곤이라 카테고리 칩에 없음
      if (!l.eraCodes.contains(eraCode)) continue;
      // v3 — landmarks 테이블 'category' 컬럼은 옛 v1 잔존. 새 데이터는 'kind'
      // 가 카테고리 역할 (mountain/city/river/...).
      final cat = (l.category != null && l.category!.isNotEmpty)
          ? l.category!
          : l.kind;
      if (cat.isEmpty) continue;
      countByCategory[cat] = (countByCategory[cat] ?? 0) + 1;
      (landmarksByCategory[cat] ??= <Landmark>[]).add(l);
      totalCount++;
    }
    if (totalCount == 0) return const SizedBox.shrink();
    // _catMeta 순서대로 정렬, 메타에 없는 새 카테고리는 끝에.
    const meta = _LandmarkCategoryChipsBar._catMeta;
    final ordered = [
      ...meta.keys.where(countByCategory.containsKey),
      ...countByCategory.keys.where((c) => !meta.containsKey(c)),
    ];

    final selected = state.selectedLandmarkCategories;
    final expanded = _expandedCat;
    // expanded 가 현재 시대에 더 이상 없는 카테고리가 됐으면 자동 닫기.
    final expandedItems = (expanded != null)
        ? landmarksByCategory[expanded]
        : null;

    // dropdown payload 갱신 + portal 노출 토글
    final hasDropdown =
        expanded != null && expandedItems != null && expandedItems.isNotEmpty;
    if (hasDropdown) {
      _dropdownPayload = _DropdownPayload(
        targetKey: _keyFor(expanded),
        emoji: meta[expanded]?.$1 ?? '📍',
        label: meta[expanded]?.$2 ?? expanded,
        items: expandedItems,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_portalController.isShowing) _portalController.show();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_portalController.isShowing) _portalController.hide();
      });
    }

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (ctx) {
        final payload = _dropdownPayload;
        if (payload == null) return const SizedBox.shrink();
        // chip RenderBox 의 글로벌 좌표를 읽어 dropdown 위치를 계산하고,
        // viewport 안으로 clamp — chip 이 화면 우측 끝 가까이 있어도
        // dropdown 이 잘리지 않도록.
        final box =
            payload.targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) return const SizedBox.shrink();
        final chipPos = box.localToGlobal(Offset.zero);
        final chipSize = box.size;
        final screen = MediaQuery.of(ctx).size;
        const dropdownWidth = 260.0;
        const screenPadding = 8.0;
        final preferredLeft = chipPos.dx;
        final left = preferredLeft.clamp(
          screenPadding,
          screen.width - dropdownWidth - screenPadding,
        );
        final top = chipPos.dy + chipSize.height + 6;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: SizedBox(
                width: dropdownWidth,
                child: _LandmarkCategoryDropdown(
                  categoryEmoji: payload.emoji,
                  categoryLabel: payload.label,
                  items: payload.items,
                  onClose: () => setState(() => _expandedCat = null),
                  onLandmarkTap: (lm) {
                    // dropdown 에서 랜드마크를 누르면 dropdown 을 닫고
                    // 부모 콜백 (포커스 + 설명 팝업) 을 호출.
                    setState(() => _expandedCat = null);
                    widget.onLandmarkTap(lm);
                  },
                ),
              ),
            ),
          ],
        );
      },
      child: SizedBox(
        height: 28,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            _CategoryChip(
              label: '전체',
              emoji: '✨',
              count: totalCount,
              active: selected.isEmpty,
              onTap: _onClearAll,
            ),
            for (final cat in ordered) ...[
              const SizedBox(width: 6),
              _CategoryChip(
                key: _keyFor(cat),
                label: meta[cat]?.$2 ?? cat,
                emoji: meta[cat]?.$1 ?? '📍',
                count: countByCategory[cat]!,
                active: selected.contains(cat),
                onTap: () => _onChipTap(cat),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// dropdown 의 overlay child 가 참조할 데이터 묶음.
class _DropdownPayload {
  const _DropdownPayload({
    required this.targetKey,
    required this.emoji,
    required this.label,
    required this.items,
  });
  final GlobalKey targetKey;
  final String emoji;
  final String label;
  final List<Landmark> items;
}

/// 카테고리 칩 바로 아래에 펼쳐지는 inline dropdown — 그 카테고리에 들어있는
/// 실제 랜드마크들을 한눈에 보여 준다. 칩 아이콘과 마커 emoji 가 다를 수 있어서
/// (예: 일곱 교회 ✉️) "도시 5" 안에 무엇이 있는지 확인용.
class _LandmarkCategoryDropdown extends StatelessWidget {
  const _LandmarkCategoryDropdown({
    required this.categoryEmoji,
    required this.categoryLabel,
    required this.items,
    required this.onClose,
    required this.onLandmarkTap,
  });

  final String categoryEmoji;
  final String categoryLabel;
  final List<Landmark> items;
  final VoidCallback onClose;
  final ValueChanged<Landmark> onLandmarkTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBF5E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF8C6743), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ConstrainedBox(
          // 너무 길어지지 않게 max 높이 제한 — 안에 스크롤.
          constraints: const BoxConstraints(maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더 — 라벨 + 갯수 + 닫기 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
                child: Row(
                  children: [
                    Text(
                      categoryEmoji,
                      style: const TextStyle(fontSize: 18, height: 1.0),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$categoryLabel · ${items.length}곳',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF332A1D),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('닫기', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5A4326),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x22000000)),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final lm = items[i];
                    final desc = (lm.description ?? '').trim();
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onLandmarkTap(lm),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                lm.emoji,
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lm.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF332A1D),
                                      ),
                                    ),
                                    if (desc.isNotEmpty)
                                      Text(
                                        desc,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          height: 1.35,
                                          color: Color(0xFF6B5430),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Color(0xFF8C6743),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizChoiceCard extends StatelessWidget {
  const _QuizChoiceCard({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFEFD9A2) : const Color(0xFFFAF1DD);
    final border = selected ? const Color(0xFFB58A47) : const Color(0xFFD9C18B);
    final badgeBg = selected
        ? const Color(0xFFB58A47)
        : const Color(0xFFE5D2A8);
    final badgeFg = selected ? Colors.white : const Color(0xFF5A4326);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: badgeFg,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: const Color(0xFF332A1D),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Color(0xFFB58A47),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizResultDialog extends StatelessWidget {
  const _QuizResultDialog({
    required this.event,
    required this.questions,
    required this.selectedAnswers,
    required this.score,
    required this.confusedCount,
  });

  final StoryEvent event;
  final List<QuizQuestion> questions;
  final List<int?> selectedAnswers;
  final int score;
  final int confusedCount;

  @override
  Widget build(BuildContext context) {
    final total = questions.length;
    final wrong = total - score - confusedCount;
    final didPass = score == total;
    final headerColor = didPass
        ? const Color(0xFF1F7A3A)
        : const Color(0xFFB58A47);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6EAD8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB58A47), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    didPass ? Icons.emoji_events : Icons.fact_check_outlined,
                    color: headerColor,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      didPass ? '모두 정답!' : '결과 확인',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: headerColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF1DD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD9C18B)),
                ),
                child: Row(
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF5A4326),
                        ),
                        children: [
                          TextSpan(
                            text: '$score',
                            style: TextStyle(fontSize: 28, color: headerColor),
                          ),
                          const TextSpan(
                            text: ' / ',
                            style: TextStyle(fontSize: 18),
                          ),
                          TextSpan(
                            text: '$total',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _ScorePill(
                            label: '정답',
                            count: score,
                            color: const Color(0xFF1F7A3A),
                          ),
                          _ScorePill(
                            label: '오답',
                            count: wrong < 0 ? 0 : wrong,
                            color: const Color(0xFFB0392F),
                          ),
                          if (confusedCount > 0)
                            _ScorePill(
                              label: '헷갈림',
                              count: confusedCount,
                              color: const Color(0xFFB58A47),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < questions.length; i++)
                        _QuizReviewItem(
                          index: i,
                          question: questions[i],
                          userAnswer: selectedAnswers[i],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB58A47),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _QuizReviewItem extends StatelessWidget {
  const _QuizReviewItem({
    required this.index,
    required this.question,
    required this.userAnswer,
  });

  final int index;
  final QuizQuestion question;
  final int? userAnswer;

  @override
  Widget build(BuildContext context) {
    final isCorrect = userAnswer == question.answerIndex;
    final isConfused = question.isConfusedChoiceIndex(userAnswer);
    final accent = isCorrect
        ? const Color(0xFF1F7A3A)
        : isConfused
        ? const Color(0xFFB58A47)
        : const Color(0xFFB0392F);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9C18B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrect ? Icons.check : Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Q${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Color(0xFF5A4326),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect
                    ? '정답'
                    : isConfused
                    ? '헷갈렸어요'
                    : '오답',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question.question,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: Color(0xFF332A1D),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var ci = 0; ci < question.choices.length; ci++)
            _ReviewChoiceRow(
              index: ci,
              text: question.choices[ci],
              isCorrect: ci == question.answerIndex,
              isUserPick: ci == userAnswer,
            ),
          if ((question.explanation ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE0C5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCBB58A).withValues(alpha: 0.6),
                ),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF5A4326),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(
                      text: '해설  ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    TextSpan(text: question.explanation!.trim()),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.emoji,
    required this.active,
    required this.onTap,
    this.count,
  });
  final String label;
  final String emoji;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : const Color(0xFF3D2A14);
    final countFg = active ? const Color(0xFFE8D7B0) : const Color(0xFF8C5A2E);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8C5A2E) : const Color(0xF2FFFBEF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? const Color(0xFF8C5A2E) : const Color(0xFFB89A66),
              width: 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 3),
                Text(
                  '+$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: countFg,
                    height: 1.0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewChoiceRow extends StatelessWidget {
  const _ReviewChoiceRow({
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.isUserPick,
  });

  final int index;
  final String text;
  final bool isCorrect;
  final bool isUserPick;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Widget marker;
    FontWeight weight;
    if (isCorrect) {
      textColor = const Color(0xFF1F7A3A);
      marker = const Icon(
        Icons.check_circle,
        size: 16,
        color: Color(0xFF1F7A3A),
      );
      weight = FontWeight.w800;
    } else if (isUserPick) {
      textColor = const Color(0xFFB0392F);
      marker = const Icon(Icons.cancel, size: 16, color: Color(0xFFB0392F));
      weight = FontWeight.w700;
    } else {
      textColor = const Color(0xFF7A6748);
      marker = const Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: Color(0xFFB89F75),
      );
      weight = FontWeight.w500;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: marker),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${index + 1}. $text',
              style: TextStyle(
                color: textColor,
                fontWeight: weight,
                fontSize: 12.6,
                height: 1.4,
              ),
            ),
          ),
          if (isUserPick && !isCorrect)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text(
                '내 답',
                style: TextStyle(
                  color: Color(0xFFB0392F),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 인물 step 2 의 "N명 다음" 작은 핀 — 패널 핸들 좌측에 표시. 인물 1명 이상
/// 선택 시 노출되며, 누르면 step 3 진입 + 사건 reveal 시작.
class _CharacterNextPill extends StatelessWidget {
  const _CharacterNextPill({
    required this.count,
    required this.onPressed,
    this.compact = false,
  });
  final int count;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = compact ? '$count명' : '$count명 다음';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 9,
            vertical: compact ? 4 : 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF8C5A2E),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10.5 : 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(width: compact ? 2 : 3),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: compact ? 12 : 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviousStepPill extends StatelessWidget {
  const _PreviousStepPill({
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visibleLabel = compact ? '이전' : label;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 9,
              vertical: compact ? 4 : 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF6A401E),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE8A33D), width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 5,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 13,
                ),
                const SizedBox(width: 3),
                Text(
                  visibleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 10.5 : 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 선택 진행 단계 stepper — 헤더 우측 라벨형 단계 pill.
/// - 활성(=현재 진행 중): 초록
/// - 완료(=이전 단계, 클릭 시 그 단계로 돌아가며 reset): 노랑
/// - 미진입(=미래 단계, 클릭 비활성): 갈색
/// 같은 step 을 다시 누르면 그 단계 진행 내역만 초기화.
class _SelectionStepper extends StatelessWidget {
  const _SelectionStepper({
    required this.currentStep,
    required this.mode,
    required this.onStepTap,
  });

  final int currentStep;
  final _SelectionMode? mode;
  final ValueChanged<int> onStepTap;

  static const Color _activeColor = Color(0xFF2E8B57); // 초록
  static const Color _doneColor = Color(0xFFE8A33D); // 노랑
  static const Color _futureColor = Color(0xFF8C6743); // 갈색

  Color _colorFor(int step) {
    if (step == currentStep) return _activeColor;
    if (step < currentStep) return _doneColor;
    return _futureColor;
  }

  String _labelFor(int step) {
    return switch (step) {
      1 => '시대/방법',
      2 => switch (mode) {
        _SelectionMode.region => '장소',
        _SelectionMode.character => '인물',
        null => '선택',
      },
      _ => '이야기',
    };
  }

  IconData? _iconFor(int step) {
    return switch (step) {
      1 => Icons.home_rounded,
      2 =>
        mode == _SelectionMode.character
            ? Icons.group_rounded
            : Icons.place_rounded,
      _ => Icons.auto_stories_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB89A66), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 3; i++) ...[
            _StepPill(
              label: _labelFor(i),
              icon: _iconFor(i),
              color: _colorFor(i),
              enabled: i <= currentStep,
              onTap: () => onStepTap(i),
              tooltip: switch (i) {
                1 => '처음으로 돌아가 시대와 보는 방법을 다시 선택',
                2 =>
                  mode == _SelectionMode.region
                      ? '장소 선택 단계로 돌아가기'
                      : '인물 선택 단계로 돌아가기',
                _ => '이야기 목록 단계',
              },
            ),
            if (i < 3)
              Container(
                width: 7,
                height: 1.4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: i < currentStep ? _doneColor : _futureColor,
              ),
          ],
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 1.0 : 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: Colors.white),
                const SizedBox(width: 2),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return dot;
    return Tooltip(message: tooltip!, child: dot);
  }
}

/// 양피지 두루마리(scroll) 형식 landmark 팝업.
/// 가로로 펼치는 unfurl 애니메이션 → 콘텐츠 fade-in.
/// 좌·우 끝 어두운 갈색 cylindrical curl + 가운데 양피지 cream panel.
class _LandmarkScrollDialog extends StatefulWidget {
  const _LandmarkScrollDialog({required this.landmark, required this.onClose});
  final Landmark landmark;
  final VoidCallback onClose;

  @override
  State<_LandmarkScrollDialog> createState() => _LandmarkScrollDialogState();
}

class _LandmarkScrollDialogState extends State<_LandmarkScrollDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _unfurl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _unfurl = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeIn),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desc = (widget.landmark.description ?? '').trim();
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.center,
                    widthFactor: _unfurl.value.clamp(0.001, 1.0),
                    child: child,
                  ),
                );
              },
              child: _ScrollBody(
                landmark: widget.landmark,
                desc: desc,
                fade: _fade,
                onClose: widget.onClose,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollBody extends StatelessWidget {
  const _ScrollBody({
    required this.landmark,
    required this.desc,
    required this.fade,
    required this.onClose,
  });
  final Landmark landmark;
  final String desc;
  final Animation<double> fade;
  final VoidCallback onClose;

  // 양피지 PNG 의 원본 비율 (1536 × 1024).
  static const double _aspect = 1536 / 1024;

  // 본문 스타일 — TextPainter 측정 시 동일 스타일 사용해야 정확.
  static const TextStyle _bodyStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFF3B2A17),
    height: 1.55,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// 본문을 양피지 폭에 맞게 가공한다:
  /// 1. 문장 끝 부호(`. `, `? `, `! `) 다음 → 줄바꿈 (한 줄에 한 문장).
  /// 2. 괄호 안 공백을 NBSP 로 묶어 자연 줄바꿈이 괄호 내부에서 일어나지
  ///    않게 한다 (예: `(창 31장)`이 `(창` / `31장)` 으로 분리되는 것 방지).
  /// 3. 괄호 앞에 줄바꿈을 넣었을 때(시도) **전체 줄 수가 2 이하면** 적용,
  ///    3 줄 이상이면 적용하지 않는다 — 사용자 요구.
  static String _formatDescription(String raw, double maxWidth) {
    if (raw.isEmpty) return raw;
    final byPeriod = raw.replaceAllMapped(
      RegExp(r'([.?!])\s'),
      (m) => '${m[1]}\n',
    );
    // 괄호 내부 공백을 NBSP 로 변환 — 괄호 콘텐츠는 한 토큰처럼 묶임.
    final nbsp = byPeriod.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
      return '(${m[1]!.replaceAll(RegExp(r'\s'), ' ')})';
    });
    // 괄호 앞 줄바꿈 후보.
    final withParenBreak = nbsp.replaceAll(RegExp(r'\s+\('), '\n(');
    if (withParenBreak == nbsp) return nbsp; // 괄호가 없거나 처리 불가
    // 측정: 괄호를 떼어놓은 결과가 2 줄 이하인지 확인.
    final tp = TextPainter(
      text: TextSpan(text: withParenBreak, style: _bodyStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 10,
    )..layout(maxWidth: maxWidth);
    final lineCount = tp.computeLineMetrics().length;
    return lineCount <= 2 ? withParenBreak : nbsp;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: _aspect,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                'assets/elements/parchment_scroll_landmark.png',
              ),
              fit: BoxFit.contain,
            ),
          ),
          child: FadeTransition(
            opacity: fade,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final h = c.maxHeight;
                final formattedDesc = _formatDescription(desc, w * (1 - 0.36));
                // 양피지 PNG 의 안전 영역(시뮬레이터 실측 기반):
                // - 좌우 두루마리 ≈ 13%, 그 안쪽 사각 테두리 ≈ 18%
                //   → 텍스트는 18% 부터 (테두리 내부에 머무르도록).
                // - 상단 십자가 장식 ≈ 12~28% → 제목은 32% 부터
                // - 1번 다이아몬드 구분선 ≈ 46%
                // - 2번 다이아몬드 구분선 ≈ 68%
                // - 하단 왁스 씰 ≈ 78~95% → 본문은 2번 구분선 위에서 끝남
                return Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        w * 0.18,
                        h * 0.32,
                        w * 0.18,
                        h * 0.32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 제목은 한 줄로 고정 — 길면 폭에 맞춰 축소.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              landmark.name,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 19,
                                color: Color(0xFF4B321B),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                height: 1.15,
                              ),
                            ),
                          ),
                          // 1번 다이아몬드 구분선(이미지에 그려져 있음) 영역.
                          SizedBox(height: h * 0.07),
                          Expanded(
                            // 짧은 본문은 가운데 정렬, 긴 본문은 스크롤.
                            // ConstrainedBox 의 minHeight = 사용 가능 높이로
                            // 강제해서 짧을 때 Center 가 동작, 길어지면 자연
                            // 스럽게 스크롤로 전환.
                            child: LayoutBuilder(
                              builder: (context, bodyC) =>
                                  SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: bodyC.maxHeight,
                                      ),
                                      child: Center(
                                        child: Text(
                                          formattedDesc.isEmpty
                                              ? '이 랜드마크에 대한 설명이\n아직 없습니다.'
                                              : formattedDesc,
                                          textAlign: TextAlign.center,
                                          style: _bodyStyle,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 우상단 X 닫기 버튼 — 안쪽 사각 테두리 모서리에 위치.
                    Positioned(
                      top: h * 0.16,
                      right: w * 0.18,
                      child: GestureDetector(
                        onTap: onClose,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFEDE0BC,
                            ).withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFF7A5A3A,
                              ).withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0xFF4B321B),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 출처 dialog 의 한 줄 — "출처명 · 라이선스" 형태.
class _AttributionLine extends StatelessWidget {
  const _AttributionLine({required this.source, this.license});

  final String source;
  final String? license;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 8),
          child: Icon(Icons.circle, size: 5, color: Color(0xFF9A7A4C)),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF3A2A1A),
              ),
              children: [
                TextSpan(text: source),
                if (license != null) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: license!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
