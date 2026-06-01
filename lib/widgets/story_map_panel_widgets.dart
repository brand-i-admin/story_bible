part of 'story_map_panel.dart';

class _ZoomScaledLandmark extends StatelessWidget {
  const _ZoomScaledLandmark({
    required this.landmark,
    required this.isMeasureSelected,
    required this.isSelected,
    required this.eventCount,
    required this.onTap,
    this.compactHit = false,
  });

  final Landmark landmark;
  final bool isMeasureSelected;
  final bool isSelected;
  final int eventCount;
  final VoidCallback onTap;

  /// true 면 GestureDetector 의 hit-test 영역을 child 가 그리는 부분으로 한정
  /// (HitTestBehavior.deferToChild). regionPickerMode 에서 폴리곤 hit-through 를
  /// 보장하기 위해 사용.
  final bool compactHit;

  // 줌 3 (전 지역 보기) 에서는 핀이 거의 안 보이고, 줌 8+ 에서 풀 사이즈.
  // 사용자: "확대했을때만 잘 보이면 되기 때문" — 줌아웃 시 더 적극적으로 축소.
  static const double _minScale = 0.18;
  static const double _maxScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.of(context).zoom;
    // region + 사건 0개 → 작게 + 회색 + 클릭 비활성. 새 이야기가 추가되어
    // eventCount > 0 이 되면 자동으로 활성 상태로 전환.
    final disabled = landmark.isRegion && eventCount == 0;
    final disabledScale = disabled ? 0.55 : 1.0;
    // zoom 3 → 0.18 (cap), zoom 5 → 0.50, zoom 7 → 0.96, zoom 8+ → 1.3 (cap).
    // 줌아웃 시 가독 부담을 줄여 폴리곤·라벨에 시야 집중되게 한다.
    final raw = 0.18 + (zoom - 3.0) * 0.225;
    final scale = raw.clamp(_minScale, _maxScale).toDouble() * disabledScale;
    final inner = landmark.isRegion
        ? _RegionPin(
            name: landmark.name,
            eventCount: eventCount,
            isSelected: isSelected,
            disabled: disabled,
          )
        : _PointPin(emoji: landmark.emoji, name: landmark.name);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: compactHit
            ? HitTestBehavior.deferToChild
            : HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
        child: ColorFiltered(
          colorFilter: isMeasureSelected
              ? const ColorFilter.mode(Color(0x55FF6B35), BlendMode.srcATop)
              : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: inner,
        ),
      ),
    );
  }
}

/// 사건 마커 + 선택 여부 페어. z-order 정렬 위해 사용.
class _MarkerWithSelection {
  const _MarkerWithSelection({required this.selected, required this.marker});
  final bool selected;
  final Marker marker;
}

/// 사건 핀 — 동그라미 + 안에 큰 순서 번호. 핀 모양/장소 라벨 모두 제거.
/// 감정 새김이 있으면 같은 지름 안에 완료 톤을 주고, 작은 컬러 감정 이모지 배지를
/// 붙여 숫자 중심 정렬은 그대로 유지한다.
class _NumberedEventPin extends StatelessWidget {
  const _NumberedEventPin({
    required this.number,
    required this.isSelected,
    this.characterColors = const <Color>[],
    this.emotionKey,
  });

  final int number;
  final bool isSelected;
  final String? emotionKey;

  /// 사건에 포함된 "사용자가 고른 인물" 의 색 리스트. 비어 있으면 기존
  /// 단색 fill (selected → 노랑, else → 갈색). 1+ 면 [_MultiColorCirclePainter]
  /// 가 핀 동그라미를 N 등분 가로 띠로 채워 인물별 식별을 시각화한다.
  /// selected 일 때도 character color 를 우선 표시하고 노란 outer border 와
  /// 두꺼운 stroke 로 "현재 이야기" 강조.
  final List<Color> characterColors;

  @override
  Widget build(BuildContext context) {
    final hasColors = characterColors.isNotEmpty;
    final fillColor = isSelected ? AppColors.goldLight : AppColors.brownWarm2;
    final hasEmotion = emotionKey != null && emotionKey!.isNotEmpty;
    final size = hasEmotion
        ? (isSelected ? 27.0 : 25.0)
        : (isSelected ? 16.0 : 14.0);
    final orderBadgeSize = hasEmotion ? 12.0 : 0.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (hasEmotion)
            EmotionBadgeIcon(
              emotionKey: emotionKey!,
              size: size,
              iconSize: size * 0.58,
              borderColor: isSelected
                  ? const Color(0xFFFFE9B0)
                  : const Color(0xFFE0B465),
              elevation: false,
            )
          else
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                // hasColors 면 fill 은 painter 가 담당 → 컨테이너 배경 투명.
                color: hasColors ? null : fillColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFE9B0) : Colors.white,
                  width: isSelected ? 1.6 : 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (hasColors)
                    ClipOval(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(
                          painter: _MultiColorCirclePainter(
                            colors: characterColors,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    '$number',
                    style: TextStyle(
                      fontSize: isSelected ? 9 : 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                      shadows: hasColors
                          ? const [
                              Shadow(color: Color(0xCC000000), blurRadius: 1.6),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          if (hasEmotion)
            Positioned(
              right: -2,
              bottom: -2,
              child: _TinyOrderBadge(number: number, size: orderBadgeSize),
            ),
        ],
      ),
    );
  }
}

class _TinyOrderBadge extends StatelessWidget {
  const _TinyOrderBadge({required this.number, required this.size});

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2F9462),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.greenRim, width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

/// `_NumberedEventPin` 안의 가로 띠 N 등분 painter — 인물 모드에서 사건에
/// 포함된 선택 인물의 색을 위에서 아래로 같은 높이로 칠한다. ClipOval 안에
/// 그려져 정사각형 painter 가 원형으로 잘린다. N=1 이면 단색 채움.
class _MultiColorCirclePainter extends CustomPainter {
  const _MultiColorCirclePainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final n = colors.length;
    final stripeH = size.height / n;
    for (var i = 0; i < n; i++) {
      final paint = Paint()..color = colors[i];
      // 마지막 띠는 1px 여유로 fill — rounding 으로 hairline 안 생기게.
      final top = i * stripeH;
      final bottom = i == n - 1 ? size.height : (i + 1) * stripeH;
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MultiColorCirclePainter old) {
    if (old.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (old.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// 큰 region 핀 — 위 둥근 머리 + 아래 핀촉 + 라벨. 선택 시 ripple 애니메이션.
/// 라벨 폭이 핀 부모 width 를 넘지 않도록 maxWidth 제약 + ellipsis.
class _RegionPin extends StatelessWidget {
  const _RegionPin({
    required this.name,
    required this.eventCount,
    required this.isSelected,
    this.disabled = false,
  });

  final String name;
  final int eventCount;
  final bool isSelected;

  /// 사건 0개인 region — 회색 톤 + 사용자가 클릭해도 동작 X (부모 GestureDetector
  /// 가 onTap=null 처리). 새 이야기가 추가되어 사건이 1개 이상이면 자동 활성.
  final bool disabled;

  static const Color _pinColorDefault = AppColors.ink700;
  static const Color _pinColorSelected = AppColors.goldLight;
  static const Color _pinColorDisabled = Color(0xFF9E9285); // 회색
  static const Color _accentColor = AppColors.brownEdge;
  static const Color _accentColorDisabled = Color(0xFFB8B0A4);
  static const Color _rippleColor = AppColors.greenTop;

  @override
  Widget build(BuildContext context) {
    final pinColor = disabled
        ? _pinColorDisabled
        : (isSelected ? _pinColorSelected : _pinColorDefault);
    final labelTextColor = disabled
        ? const Color(0xFFE6DFD2)
        : (isSelected ? const Color(0xFF3D2A14) : const Color(0xFFF5E9C8));
    final accent = disabled ? _accentColorDisabled : _accentColor;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // ripple 애니메이션 — 선택된 경우만. 핀 아래 동심원 4겹 (금색).
        // disabled (사건 0) 일 땐 선택 자체가 안 되므로 ripple 도 자동 안 그려짐.
        if (isSelected && !disabled)
          const Positioned.fill(
            child: IgnorePointer(child: _RegionRipple(color: _rippleColor)),
          ),
        // 핀 + 라벨 (세로 정렬)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핀 머리(둥근 원 + 흰 점) + 핀촉 — 선택 시 금색. 장소 핀은 point pin
            // 보다 살짝 크게 (region 이 더 중요한 진입점이라 시각적 위계 부여).
            CustomPaint(
              size: const Size(28, 38),
              painter: _LocationPinPainter(color: pinColor),
            ),
            const SizedBox(height: 2),
            // 라벨 — 핀 색깔 캡슐 + 사건 개수 배지. maxWidth 로 overflow 방지.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: pinColor,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent, width: 1),
                  boxShadow: disabled
                      ? const []
                      : const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 3,
                            offset: Offset(0, 1.5),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: labelTextColor,
                          height: 1.1,
                        ),
                      ),
                    ),
                    if (eventCount > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.ink700
                              : AppColors.goldLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$eventCount',
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.goldLight
                                : AppColors.ink700,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 작은 non-region 마커 — 핀 모양 없이 이모지만 + 아래 plain text 라벨.
/// 흰 stroke shadow 로 가독성 보강.
class _PointPin extends StatelessWidget {
  const _PointPin({required this.emoji, required this.name});
  final String emoji;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 이모지만 — 원형/핀 배경 없음. 폴리곤·라벨이 주인공이라 살짝 투명.
        Opacity(
          opacity: 0.7,
          child: Text(
            emoji,
            style: const TextStyle(
              fontSize: 13,
              height: 1.0,
              shadows: [
                Shadow(
                  color: Color(0x33000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        // plain text 라벨 — 살짝 짙은 갈색으로 가독성 보강.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 64),
          child: Opacity(
            opacity: 0.85,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w700,
                color: AppColors.ink200,
                height: 1.1,
                shadows: [
                  Shadow(color: Color(0xCCFBF1DC), blurRadius: 2),
                  Shadow(color: Color(0xCCFBF1DC), blurRadius: 2),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// region 핀 머리(둥근 원 + 흰 점) + 핀촉(아래로 뾰족) Custom 페인터.
class _LocationPinPainter extends CustomPainter {
  _LocationPinPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final headR = w * 0.45;
    final headCx = w / 2;
    final headCy = headR + 1;

    // 그림자
    final shadow = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(headCx, headCy + 2), headR, shadow);

    // 핀촉 (아래로 뾰족) — dart:ui.Path 명시 (flutter_map 의 Path<R> 와 충돌 회피).
    final pinPaint = Paint()..color = color;
    final tip = Offset(headCx, h - 1);
    final leftBase = Offset(headCx - headR * 0.85, headCy + headR * 0.5);
    final rightBase = Offset(headCx + headR * 0.85, headCy + headR * 0.5);
    final path = ui.Path()
      ..moveTo(leftBase.dx, leftBase.dy)
      ..quadraticBezierTo(headCx - headR * 0.3, h - 6, tip.dx, tip.dy)
      ..quadraticBezierTo(
        headCx + headR * 0.3,
        h - 6,
        rightBase.dx,
        rightBase.dy,
      )
      ..close();
    canvas.drawPath(path, pinPaint);

    // 머리 원
    canvas.drawCircle(Offset(headCx, headCy), headR, pinPaint);

    // 머리 안 흰 점 — region 핀 식별용.
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(headCx, headCy), headR * 0.32, whitePaint);
  }

  @override
  bool shouldRepaint(covariant _LocationPinPainter old) => old.color != color;
}

/// 선택된 region 핀 아래 ripple 애니메이션 — 동심원 4겹 fade.
class _RegionRipple extends StatefulWidget {
  const _RegionRipple({required this.color});
  final Color color;

  @override
  State<_RegionRipple> createState() => _RegionRippleState();
}

class _RegionRippleState extends State<_RegionRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        return CustomPaint(
          painter: _RipplePainter(t: _ctl.value, color: widget.color),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.t, required this.color});
  final double t; // 0 ~ 1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // 핀촉이 아래쪽이라 ripple 의 중심은 핀촉(=핀 머리에서 약간 아래)
    final cy = size.height * 0.4;
    final maxR = math.min(size.width, size.height) * 0.55;
    for (var i = 0; i < 4; i++) {
      final phase = (t + i * 0.25) % 1.0;
      final r = phase * maxR;
      final alpha = ((1.0 - phase) * 0.85).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.t != t || old.color != color;
}

/// 비지리적 region (요한계시록 환상 등) 을 지도 좌하단에 작은 카드로 표시.
/// polygon 이 비어 지도에 그릴 수 없는 region 들을 사용자에게 노출하는 수단.
class _NonGeographicRegionCard extends StatelessWidget {
  const _NonGeographicRegionCard({required this.regions});

  final List<Landmark> regions;

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB89A66), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '✨ 환상 / 비지리적',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8C6743),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          for (final r in regions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2A14),
                      ),
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

class _CharacterColorLegend extends StatelessWidget {
  const _CharacterColorLegend({
    required this.codes,
    required this.colorForCharacter,
    required this.nameForCharacter,
  });

  final Set<String> codes;
  final Color Function(String characterCode) colorForCharacter;
  final String Function(String characterCode)? nameForCharacter;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB89A66), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          for (final code in codes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorForCharacter(code),
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x44000000), blurRadius: 1.5),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  nameForCharacter?.call(code) ?? code,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3D2A14),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 시대 미리보기 path 끝점에 그리는 ▶ 모양 화살촉. 색은 인물의 path 색.
class _ArrowHeadPainter extends CustomPainter {
  _ArrowHeadPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true;

    // ▶ 모양 — 오른쪽 가운데 꼭짓점, 왼쪽 위/아래 꼭짓점.
    // dart:ui Path 를 명시 (flutter_map 의 Path<LatLng> 와 충돌 회피).
    final path = ui.Path()
      ..moveTo(size.width * 0.95, size.height * 0.5)
      ..lineTo(size.width * 0.20, size.height * 0.18)
      ..lineTo(size.width * 0.40, size.height * 0.5)
      ..lineTo(size.width * 0.20, size.height * 0.82)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowHeadPainter old) => old.color != color;
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    if (assetPath.isEmpty) {
      return const Icon(Icons.person, size: 14, color: Color(0xFF8C5A2E));
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.person, size: 14, color: Color(0xFF8C5A2E)),
    );
  }
}
