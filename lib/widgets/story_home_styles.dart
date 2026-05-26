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
    color: const Color(0xEEF7EBD8),
    borderRadius: BorderRadius.circular(AppRadii.xl),
    border: Border.all(color: const Color(0xB58E6F48), width: 1.0),
  );
}

BoxDecoration headerChipDecoration() {
  return BoxDecoration(
    color: const Color(0xEEF2E1C6),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xBC9A7A4C), width: 1),
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
            colors: [Color(0xFFF8F0E2), Color(0xFFEEDDC1)],
          ),
    borderRadius: BorderRadius.circular(AppRadii.lg),
    border: Border.all(
      color: selected ? AppColors.brownRim : const Color(0xBC9A7A4C),
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
                (completed ? const Color(0xFFD7EFCE) : AppColors.goldHi),
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
          border: Border.all(color: const Color(0xBC9A7A4C), width: 1.0),
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
      color: const Color(0xCC2A2118),
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
      (selected ? const Color(0xD06A401E) : const Color(0xB02A2118));
  final resolvedBorderColor =
      borderColor ?? (selected ? AppColors.goldRim : const Color(0xBFD8BF99));
  final resolvedForegroundColor = foregroundColor ?? AppColors.fgOnDark;
  final resolvedBoxShadow =
      boxShadow ?? (selected ? AppShadows.goldGlow : null);

  // 랜드마크 필터 칩과 시각적 균형을 맞추기 위해 padding/radius/font 동일하게.
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

Widget storySection({
  required String title,
  required String content,
  Widget? action,
  Widget? footer,
}) {
  return SizedBox(
    width: double.infinity,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: const Color(0xF4EFE3CC),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (footer != null) footer,
        ],
      ),
    ),
  );
}

/// 장면 이미지 row. [sceneAssets] 의 각 원소는 로컬 asset 경로
/// (`assets/...`) 또는 Supabase Storage public URL (`http...`) 이다.
/// `SceneAssetLoader` 가 하이브리드 로딩에서 둘 중 적절한 것을 채워 넘긴다.
Widget storySceneRow(List<String> sceneAssets) {
  return StorySceneRow(sceneAssets: sceneAssets);
}

/// 장면 이미지 가로 스크롤 row. 한 화면에 ~2.3 타일 노출이라 3장 이상이면
/// 우측에 잘려 있다. 등장 시 한 번 살짝 들썩이고(nudge), 평소엔 우측 페이드로
/// "더 있음" affordance.
class StorySceneRow extends StatefulWidget {
  const StorySceneRow({super.key, required this.sceneAssets});

  final List<String> sceneAssets;

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
    if (!_assetsIdentical(old.sceneAssets, widget.sceneAssets)) {
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
        border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
        borderRadius: BorderRadius.circular(AppRadii.md),
        color: const Color(0xF4EFE3CC),
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
              return SizedBox(
                width: tileWidth,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0x9C7C5C39),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: _hybridSceneImage(
                      path: path,
                      width: tileWidth,
                      height: tileHeight,
                    ),
                  ),
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

/// 상단 row에 "Aa" 라벨로 표시되는 글자 크기 토글 버튼.
///
/// `topUtilityButton`과 동일한 스타일을 공유하지만 고정 라벨과 고정 폭을 사용한다.
Widget topFontScaleButton({required VoidCallback onTap}) {
  return topUtilityButton(label: 'Aa', onTap: onTap);
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
