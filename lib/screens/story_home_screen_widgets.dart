part of 'story_home_screen.dart';

enum _SelectionMode { character, region, timeline }

extension _IterableX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

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
        _SelectionMode.timeline => '시간 순',
        null => '선택',
      },
      _ => '이야기',
    };
  }

  IconData? _iconFor(int step) {
    return switch (step) {
      1 => Icons.home_rounded,
      2 => switch (mode) {
        _SelectionMode.character => Icons.group_rounded,
        _SelectionMode.timeline => Icons.timeline_rounded,
        _ => Icons.place_rounded,
      },
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
                2 => switch (mode) {
                  _SelectionMode.region => '장소 선택 단계로 돌아가기',
                  _SelectionMode.timeline => '시간 순으로 다시 보기',
                  _ => '인물 선택 단계로 돌아가기',
                },
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
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scale,
                  child: _ScrollBody(
                    landmark: widget.landmark,
                    desc: desc,
                    onClose: widget.onClose,
                  ),
                ),
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
    required this.onClose,
  });
  final Landmark landmark;
  final String desc;
  final VoidCallback onClose;

  static const TextStyle _bodyStyle = TextStyle(
    fontSize: AppFontSizes.base,
    color: AppColors.ink450,
    height: AppLineHeights.body,
    fontWeight: FontWeight.w400,
  );

  static String _kindLabel(Landmark landmark) {
    final category = landmark.category?.trim();
    if (category != null && category.isNotEmpty) {
      return category.replaceAll('_', ' ');
    }
    switch (landmark.kind) {
      case 'region':
        return '지역';
      case 'city':
        return '도시';
      case 'river':
        return '강';
      case 'sea':
        return '바다';
      case 'mountain':
        return '산';
      case 'island':
        return '섬';
      case 'palace':
        return '궁전';
      case 'wilderness':
        return '광야';
      case 'holy_site':
        return '성지';
      case 'campsite':
        return '진영';
      case 'anchor':
        return '거점';
      case 'minor':
        return '지점';
      default:
        return landmark.kind.replaceAll('_', ' ');
    }
  }

  static String _formatDescription(String raw, double maxWidth) {
    if (raw.isEmpty) return raw;
    final byPeriod = raw.replaceAllMapped(
      RegExp(r'([.?!])\s'),
      (m) => '${m[1]}\n',
    );
    final nbsp = byPeriod.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
      return '(${m[1]!.replaceAll(RegExp(r'\s'), ' ')})';
    });
    final withParenBreak = nbsp.replaceAll(RegExp(r'\s+\('), '\n(');
    if (withParenBreak == nbsp) return nbsp;
    final tp = TextPainter(
      text: TextSpan(text: withParenBreak, style: _bodyStyle),
      textDirection: TextDirection.ltr,
      maxLines: 10,
    )..layout(maxWidth: maxWidth);
    return tp.computeLineMetrics().length <= 2 ? withParenBreak : nbsp;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: modalSurfaceDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.x4l),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFF9F0),
                      Color(0xFFF8EEDB),
                      Color(0xFFF0DFC2),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              top: -48,
              right: -22,
              child: _WatercolorWash(
                size: 188,
                colors: [Color(0x4F87A7C9), Color(0x0087A7C9)],
              ),
            ),
            const Positioned(
              top: 76,
              left: -34,
              child: _WatercolorWash(
                size: 148,
                colors: [Color(0x43E4B96A), Color(0x00E4B96A)],
              ),
            ),
            const Positioned(
              bottom: -36,
              right: 24,
              child: _WatercolorWash(
                size: 166,
                colors: [Color(0x39C98775), Color(0x00C98775)],
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.03),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: LayoutBuilder(
                builder: (context, c) {
                  final formattedDesc = _formatDescription(
                    desc,
                    c.maxWidth - 48,
                  );
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFF3D5), Color(0xFFF0DDA9)],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xD5D9B97A),
                                width: 1.2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x18000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              landmark.emoji,
                              style: const TextStyle(fontSize: 24, height: 1),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  landmark.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: AppFontSizes.title,
                                    color: AppColors.ink500,
                                    fontWeight: FontWeight.w900,
                                    height: AppLineHeights.snug,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _PopupMetaChip(
                                      label: _kindLabel(landmark),
                                      icon: landmark.isRegion
                                          ? Icons.public_rounded
                                          : Icons.place_rounded,
                                    ),
                                    if (landmark.relatedEventCodes.isNotEmpty)
                                      _PopupMetaChip(
                                        label:
                                            '${landmark.relatedEventCodes.length}개 사건',
                                        icon: Icons.auto_stories_rounded,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          modalCloseButton(onTap: onClose),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xA6C69A58),
                              Colors.white.withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.46),
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            border: Border.all(
                              color: const Color(0xBFD8B787),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 10,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Text(
                              formattedDesc.isEmpty
                                  ? '이 랜드마크에 대한 설명이 아직 없습니다.'
                                  : formattedDesc,
                              textAlign: TextAlign.left,
                              style: _bodyStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatercolorWash extends StatelessWidget {
  const _WatercolorWash({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors, stops: const [0.0, 1.0]),
        ),
      ),
    );
  }
}

class _PopupMetaChip extends StatelessWidget {
  const _PopupMetaChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF0FFF8EC),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: const Color(0xBFD9BE92), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.ink300),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink400,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
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
