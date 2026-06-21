import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/surfaces.dart';
import '../theme/tokens.dart';

// story_home_screen.dart에서 추출한 공통 스타일 헬퍼.
// 시각 값은 lib/theme/tokens.dart에 정의된 토큰을 참조한다.
// 새 위젯은 가능하면 AppSurfaces / AppColors를 직접 사용할 것.

BoxDecoration modalSurfaceDecoration() {
  return AppSurfaces.modal();
}

BoxDecoration floatingPanelDecoration({
  Color color = AppColors.floatingSurfaceDefault,
  double shadowOpacity = 0.12,
}) {
  return AppSurfaces.floating(color: color, shadowOpacity: shadowOpacity);
}

BoxDecoration interactiveCardDecoration({
  required bool selected,
  bool completed = false,
}) {
  if (selected && completed) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.greenTop, AppColors.greenBot],
      ),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      border: Border.all(color: AppColors.greenRim, width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x24408F5E),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ],
    );
  }
  if (selected) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.brownWarm, AppColors.brownWarm2],
      ),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      border: Border.all(color: AppColors.brownRim, width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26A35B22),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ],
    );
  }
  if (completed) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.greenTint1, AppColors.greenTint2],
      ),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      border: Border.all(color: AppColors.greenBorder, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x183A7A4B),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
  return BoxDecoration(
    color: AppColors.floatingSurfaceDefault,
    borderRadius: BorderRadius.circular(AppRadii.xl),
    border: Border.all(color: AppColors.borderCard, width: 1.0),
  );
}

BoxDecoration headerChipDecoration() {
  return BoxDecoration(
    color: AppColors.parchmentMid.withValues(alpha: 0.94),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.borderFloating, width: 1),
  );
}

BoxDecoration softButtonDecoration({required bool selected}) {
  return BoxDecoration(
    gradient: selected
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brownWarm, AppColors.brownWarm2],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.parchmentLight, AppColors.parchmentMid],
          ),
    borderRadius: BorderRadius.circular(AppRadii.lg),
    border: Border.all(
      color: selected ? AppColors.brownRim : AppColors.borderFloating,
      width: 1.0,
    ),
    boxShadow: selected
        ? const [
            BoxShadow(
              color: Color(0x26A35B22),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ]
        : null,
  );
}

Widget filledActionButton({
  required String label,
  required VoidCallback onTap,
  bool completed = false,
  bool compact = false,
  double? minWidth,
  double? minHeight,
  double? horizontalPadding,
  double? radius,
  double? fontSize,
  List<Color>? gradientColors,
  Color? borderColor,
  Color? shadowColor,
}) {
  final height = minHeight ?? (compact ? 34.0 : 42.0);
  final horizontal = horizontalPadding ?? (compact ? 12.0 : 18.0);
  final resolvedRadius = radius ?? (compact ? 12.0 : 15.0);
  final resolvedFontSize = fontSize ?? (compact ? 11.5 : AppFontSizes.btn);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(resolvedRadius),
      child: Container(
        constraints: BoxConstraints(
          minWidth: minWidth ?? 92,
          minHeight: height,
        ),
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                gradientColors ??
                (completed
                    ? const [AppColors.greenBtnTop, AppColors.greenBtnBot]
                    : const [AppColors.goldLight, AppColors.goldDeep]),
          ),
          borderRadius: BorderRadius.circular(resolvedRadius),
          border: Border.all(
            color:
                borderColor ??
                (completed ? AppColors.greenRim : AppColors.goldHi),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  shadowColor ??
                  (completed
                      ? const Color(0x223D8758)
                      : const Color(0x26A35B22)),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.parchmentCream,
            fontSize: resolvedFontSize,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    ),
  );
}

Widget modalCloseButton({required VoidCallback onTap, double size = 34}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size * 0.38),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xECF7EBD7),
          borderRadius: BorderRadius.circular(size * 0.38),
          border: Border.all(color: AppColors.borderFloating, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.close_rounded,
          size: size * 0.52,
          color: AppColors.ink400,
        ),
      ),
    ),
  );
}

Widget mapControlButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
}) {
  return Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: AppColors.ink900.withValues(alpha: 0.80),
      borderRadius: BorderRadius.circular(AppRadii.xs),
      border: Border.all(color: AppColors.borderHairlineDark),
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: AppColors.fgOnDark, size: 16),
    ),
  );
}

const double _topUtilityIconButtonHeight = 36;
const double _topUtilityIconButtonWidth = 38;

Widget topUtilityButton({
  required String label,
  required VoidCallback onTap,
  bool selected = false,
  bool enabled = true,
  Color? backgroundColor,
  Color? borderColor,
  Color? foregroundColor,
  List<BoxShadow>? boxShadow,
}) {
  final resolvedBackgroundColor =
      backgroundColor ??
      (selected
          ? AppColors.brownWarm2.withValues(alpha: 0.92)
          : AppColors.ink900.withValues(alpha: 0.76));
  final resolvedBorderColor =
      borderColor ??
      (selected ? AppColors.brownRim : AppColors.borderHairlineDark);
  final resolvedForegroundColor = foregroundColor ?? AppColors.fgOnDark;
  final resolvedBoxShadow =
      boxShadow ?? (selected ? AppShadows.goldGlow : null);

  return Opacity(
    opacity: enabled ? 1 : 0.42,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: resolvedBackgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: resolvedBorderColor,
              width: selected ? 1.2 : 0.9,
            ),
            boxShadow: resolvedBoxShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: resolvedForegroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: AppLineHeights.tight,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget topUtilityIconButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
  bool selected = false,
  bool enabled = true,
  Color? backgroundColor,
  Color? borderColor,
  Color? foregroundColor,
  List<BoxShadow>? boxShadow,
}) {
  final resolvedBackgroundColor =
      backgroundColor ??
      (selected
          ? AppColors.brownWarm2.withValues(alpha: 0.92)
          : AppColors.ink900.withValues(alpha: 0.76));
  final resolvedBorderColor =
      borderColor ??
      (selected ? AppColors.brownRim : AppColors.borderHairlineDark);
  final resolvedForegroundColor = foregroundColor ?? AppColors.fgOnDark;
  final resolvedBoxShadow =
      boxShadow ?? (selected ? AppShadows.goldGlow : null);

  return Opacity(
    opacity: enabled ? 1 : 0.42,
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: _topUtilityIconButtonWidth,
            height: _topUtilityIconButtonHeight,
            decoration: BoxDecoration(
              color: resolvedBackgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: resolvedBorderColor,
                width: selected ? 1.2 : 0.9,
              ),
              boxShadow: resolvedBoxShadow,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: resolvedForegroundColor, size: 18),
          ),
        ),
      ),
    ),
  );
}

Widget storySection({
  required String title,
  required String content,
  Widget? action,
  Widget? footer,
  bool inlineTitle = false,
}) {
  return SizedBox(
    width: double.infinity,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderCard, width: 1.2),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: AppColors.parchmentCard.withValues(alpha: 0.96),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inlineTitle)
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: AppFontSizes.body,
                  height: AppLineHeights.body,
                  color: AppColors.ink800,
                ),
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink450,
                    ),
                  ),
                  TextSpan(text: content),
                ],
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppFontSizes.body,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink450,
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              content,
              style: const TextStyle(
                fontSize: AppFontSizes.body,
                height: AppLineHeights.body,
                color: AppColors.ink800,
              ),
            ),
          ],
          if (footer != null) footer,
        ],
      ),
    ),
  );
}

/// 장면 이미지 row. [sceneAssets] 의 각 원소는 로컬 asset 경로
/// (`assets/...`) 또는 Supabase Storage public URL (`http...`) 이다.
/// `SceneAssetLoader` 가 하이브리드 로딩에서 둘 중 적절한 것을 채워 넘긴다.
Widget storySceneRow(
  List<String> sceneAssets, {
  List<String> sceneCaptions = const [],
}) {
  return StorySceneRow(sceneAssets: sceneAssets, sceneCaptions: sceneCaptions);
}

/// 장면 이미지 가로 스크롤 row. 한 화면에 ~2.3 타일 노출이라 3장 이상이면
/// 우측에 잘려 있다. 등장 시 한 번 살짝 들썩이고(nudge), 평소엔 우측 페이드로
/// "더 있음" affordance.
class StorySceneRow extends StatefulWidget {
  const StorySceneRow({
    super.key,
    required this.sceneAssets,
    this.sceneCaptions = const [],
  });

  final List<String> sceneAssets;
  final List<String> sceneCaptions;

  @override
  State<StorySceneRow> createState() => _StorySceneRowState();
}

class _StorySceneRowState extends State<StorySceneRow> {
  final ScrollController _ctl = ScrollController();
  bool _didInitialNudge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRunInitialNudge();
    });
  }

  @override
  void didUpdateWidget(covariant StorySceneRow old) {
    super.didUpdateWidget(old);
    if (!_assetsIdentical(old.sceneAssets, widget.sceneAssets) ||
        !_assetsIdentical(old.sceneCaptions, widget.sceneCaptions)) {
      _didInitialNudge = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRunInitialNudge();
      });
    }
  }

  static bool _assetsIdentical(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _maybeRunInitialNudge() async {
    if (_didInitialNudge) return;
    if (!_ctl.hasClients) return;
    if (_ctl.position.maxScrollExtent <= 0) return;
    _didInitialNudge = true;
    // 0 → 60 → 0 한 번 들썩여서 "오른쪽에 더 있음" affordance.
    // 거리는 충분히 크게(60), 총 ~640ms.
    const peak = 60.0;
    try {
      await _ctl.animateTo(
        peak,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || !_ctl.hasClients) return;
      await _ctl.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // dispose 등으로 controller 가 detach 되면 무시.
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedAssets = widget.sceneAssets.take(4).toList(growable: false);
    if (displayedAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    const tileGap = 8.0;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderCard, width: 1.2),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: AppColors.parchmentCard.withValues(alpha: 0.96),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 한 화면에 약 2.3개 노출 → 부모 폭의 1/2.3 ≈ 0.435 가 한 타일 폭.
          final tileWidth = (constraints.maxWidth - tileGap) / 2.3;
          final viewportHeight = MediaQuery.sizeOf(context).height;
          final maxTileHeight = math.max(220.0, viewportHeight * 0.42);
          final tileHeight = math.min(tileWidth * 1.62, maxTileHeight);

          final list = ListView.separated(
            controller: _ctl,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: displayedAssets.length,
            separatorBuilder: (_, __) => const SizedBox(width: tileGap),
            itemBuilder: (context, index) {
              final path = displayedAssets[index];
              final caption = index < widget.sceneCaptions.length
                  ? widget.sceneCaptions[index].trim()
                  : '';
              return SizedBox(
                width: tileWidth,
                child: _FlippableSceneTile(
                  key: ValueKey('story-scene-tile-$index'),
                  index: index,
                  path: path,
                  caption: caption,
                  width: tileWidth,
                  height: tileHeight,
                ),
              );
            },
          );

          // 우측 페이드 — overflow 가 있고 끝까지 안 갔을 때만 fade. ShaderMask
          // 는 항상 배치하고 색만 토글해서 setState 없이 _ctl 알림만으로 동기.
          return SizedBox(
            height: tileHeight,
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (context, child) {
                final hasOverflow =
                    _ctl.hasClients && _ctl.position.maxScrollExtent > 0;
                final atEnd =
                    !hasOverflow ||
                    _ctl.position.pixels >= _ctl.position.maxScrollExtent - 4;
                final fadeOn = hasOverflow && !atEnd;
                return ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.92, 1.0],
                    colors: [
                      Colors.white,
                      Colors.white,
                      fadeOn ? const Color(0x00FFFFFF) : Colors.white,
                    ],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: child!,
                );
              },
              child: list,
            ),
          );
        },
      ),
    );
  }
}

class _FlippableSceneTile extends StatefulWidget {
  const _FlippableSceneTile({
    super.key,
    required this.index,
    required this.path,
    required this.caption,
    required this.width,
    required this.height,
  });

  final int index;
  final String path;
  final String caption;
  final double width;
  final double height;

  @override
  State<_FlippableSceneTile> createState() => _FlippableSceneTileState();
}

class _FlippableSceneTileState extends State<_FlippableSceneTile> {
  bool _showBack = false;

  void _toggle() {
    if (widget.caption.isEmpty) {
      return;
    }
    setState(() {
      _showBack = !_showBack;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = widget.caption.isNotEmpty;
    Widget tile = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _showBack ? math.pi : 0),
      duration: const Duration(milliseconds: 440),
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        final showingBackFace = value > math.pi / 2;
        final displayRotation = showingBackFace ? value - math.pi : value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(displayRotation),
          child: showingBackFace
              ? _SceneCaptionBack(
                  key: ValueKey('story-scene-caption-back-${widget.index}'),
                  caption: widget.caption,
                )
              : _SceneTileFront(
                  index: widget.index,
                  path: widget.path,
                  caption: widget.caption,
                  width: widget.width,
                  height: widget.height,
                ),
        );
      },
    );

    tile = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderFloating, width: 1.0),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: tile,
      ),
    );

    if (!hasCaption) {
      return tile;
    }
    return Semantics(
      button: true,
      label: widget.caption,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: tile,
        ),
      ),
    );
  }
}

class _SceneTileFront extends StatelessWidget {
  const _SceneTileFront({
    required this.index,
    required this.path,
    required this.caption,
    required this.width,
    required this.height,
  });

  final int index;
  final String path;
  final String caption;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _hybridSceneImage(path: path, width: width, height: height),
        if (caption.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _SceneCaptionOverlay(
              key: ValueKey('story-scene-caption-front-$index'),
              caption: caption,
            ),
          ),
      ],
    );
  }
}

class _SceneCaptionOverlay extends StatelessWidget {
  const _SceneCaptionOverlay({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.18,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneCaptionBack extends StatelessWidget {
  const _SceneCaptionBack({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.ink900.withValues(alpha: 0.94),
            const Color(0xFF4A3823).withValues(alpha: 0.96),
          ],
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.38,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

Widget bibleMoveButton({required VoidCallback onTap}) {
  return filledActionButton(
    label: '이동',
    onTap: onTap,
    compact: true,
    minWidth: 78,
  );
}

Widget lockedPreviewOverlay({required Widget child}) {
  return Container(
    color: const Color(0x2EF3E6D0),
    alignment: Alignment.center,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    ),
  );
}

Widget bibleDropdownFrame<T>({
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return SizedBox(
    height: 38,
    child: DecoratedBox(
      decoration: softButtonDecoration(selected: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            iconSize: 12,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            dropdownColor: const Color(0xFFF3E4CC),
            iconEnabledColor: const Color(0xFF5B4327),
            style: const TextStyle(
              color: AppColors.ink500,
              fontWeight: FontWeight.w900,
              fontSize: AppFontSizes.base,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

/// 상단 row에서 글자 크기 설정 바텀시트를 여는 토글 버튼.
Widget topFontScaleButton({required VoidCallback onTap}) {
  return Semantics(
    button: true,
    label: '글자 크기 변경',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('top-font-scale-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 42, minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ink900.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderHairlineDark, width: 0.9),
          ),
          alignment: Alignment.center,
          child: const Text(
            '글자',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.fgOnDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 로컬 asset vs Supabase Storage URL 구분 후 적절한 Image 위젯 반환.
/// 둘 다 실패하면 진흙 배경 + 파손 아이콘.
Widget _hybridSceneImage({
  required String path,
  required double width,
  required double height,
}) {
  final isNetwork = path.startsWith('http://') || path.startsWith('https://');
  Widget fallback() => Container(
    width: width,
    height: height,
    color: const Color(0xFFE7D2B2),
    alignment: Alignment.center,
    child: const Icon(Icons.broken_image_outlined, color: Color(0xFF7A4B21)),
  );
  if (isNetwork) {
    return Image.network(
      path,
      fit: BoxFit.cover,
      width: width,
      height: height,
      alignment: Alignment.center,
      errorBuilder: (_, _, _) => fallback(),
    );
  }
  return Image.asset(
    path,
    fit: BoxFit.cover,
    width: width,
    height: height,
    alignment: Alignment.center,
    errorBuilder: (_, _, _) => fallback(),
  );
}
