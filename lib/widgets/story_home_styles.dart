import 'dart:math' as math;

import 'package:flutter/material.dart';

// story_home_screen.dart에서 추출한 공통 스타일 헬퍼 모음.
//
// 양피지/고지도 테마를 유지하면서 패널/버튼/카드를 렌더링하기 위한
// BoxDecoration / Widget 빌더를 제공한다. 다이얼로그/서브 페이지를
// 별도 파일로 분리할 때 이 함수들을 재사용한다.

BoxDecoration modalSurfaceDecoration() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8F1E4), Color(0xFFF1E2C6)],
    ),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: const Color(0xC29E7A4C), width: 1.2),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 30,
        offset: Offset(0, 18),
      ),
    ],
  );
}

BoxDecoration floatingPanelDecoration({
  Color color = const Color(0xF5F7E9D1),
  double shadowOpacity = 0.12,
}) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(const Color(0x14FFFFFF), color), color],
    ),
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xB88E6F48), width: 1.0),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: shadowOpacity),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
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
        colors: [Color(0xFF48A86B), Color(0xFF2D7B4D)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD9F0D0), width: 1.2),
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
        colors: [Color(0xFFC8863B), Color(0xFFA85B25)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF1D39C), width: 1.2),
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
        colors: [Color(0xFFE3F3DE), Color(0xFFD2EBCB)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF7FB07B), width: 1.0),
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
    borderRadius: BorderRadius.circular(18),
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
            colors: [Color(0xFFC8863B), Color(0xFFA85B25)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F0E2), Color(0xFFEEDDC1)],
          ),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: selected ? const Color(0xFFF1D39C) : const Color(0xBC9A7A4C),
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
}) {
  final height = minHeight ?? (compact ? 34.0 : 42.0);
  final horizontal = horizontalPadding ?? (compact ? 12.0 : 18.0);
  final resolvedRadius = radius ?? (compact ? 12.0 : 15.0);
  final resolvedFontSize = fontSize ?? (compact ? 11.5 : 12.5);
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
            colors: completed
                ? const [Color(0xFF58B573), Color(0xFF2D8754)]
                : const [Color(0xFFD89A47), Color(0xFFB96B2D)],
          ),
          borderRadius: BorderRadius.circular(resolvedRadius),
          border: Border.all(
            color: completed
                ? const Color(0xFFD7EFCE)
                : const Color(0xFFF2D8A6),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: completed
                  ? const Color(0x223D8758)
                  : const Color(0x26A35B22),
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
            color: const Color(0xFFFDF8EE),
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
          color: const Color(0xFF5C4326),
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
    decoration: BoxDecoration(
      color: const Color(0xCC2A2118),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD8BF99)),
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFFF8EED9), size: 20),
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
      borderColor ??
      (selected ? const Color(0xFFF0C36B) : const Color(0xBFD8BF99));
  final resolvedForegroundColor = foregroundColor ?? const Color(0xFFF8EED9);
  final resolvedBoxShadow =
      boxShadow ??
      (selected
          ? [
              const BoxShadow(
                color: Color(0x45F0C36B),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ]
          : null);

  return Opacity(
    opacity: enabled ? 1 : 0.42,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: resolvedBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: resolvedBorderColor,
              width: selected ? 1.4 : 1,
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
              fontSize: 13.4,
              fontWeight: FontWeight.w800,
              height: 1.1,
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
        borderRadius: BorderRadius.circular(12),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4D381F),
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
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF3B2A17),
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
  final displayedAssets = sceneAssets.take(4).toList(growable: false);
  if (displayedAssets.isEmpty) {
    return const SizedBox.shrink();
  }

  const tileGap = 8.0;
  return SizedBox(
    width: double.infinity,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xBF9A7A4A), width: 1.2),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xF4EFE3CC),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = (constraints.maxWidth - (tileGap * 3)) / 4;
          final viewportHeight = MediaQuery.sizeOf(context).height;
          final maxTileHeight = math.max(180.0, viewportHeight * 0.48);
          final tileHeight = math.min(tileWidth * 1.62, maxTileHeight);
          return Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(displayedAssets.length, (index) {
                final path = displayedAssets[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == displayedAssets.length - 1 ? 0 : tileGap,
                  ),
                  child: SizedBox(
                    width: tileWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0x9C7C5C39),
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SizedBox(
                          height: tileHeight,
                          child: _hybridSceneImage(
                            path: path,
                            width: tileWidth,
                            height: tileHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    ),
  );
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
            borderRadius: BorderRadius.circular(10),
            dropdownColor: const Color(0xFFF3E4CC),
            iconEnabledColor: const Color(0xFF5B4327),
            style: const TextStyle(
              color: Color(0xFF4A331D),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
            items: items,
            onChanged: onChanged,
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
