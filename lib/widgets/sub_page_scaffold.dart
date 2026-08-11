import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_color_palette.dart';
import 'parchment_texture_layer.dart';
import 'story_home_styles.dart';
import 'sub_page_floating_home_button.dart';

/// 이야기 상세, 성경 리더, 주간 탭 등 서브 페이지 공통 레이아웃.
///
/// [compactBackOnly]가 true면 상단 앱바 대신 드래그 가능한 홈 버튼을 표시한다.
class SubPageScaffold extends StatefulWidget {
  const SubPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.compactBackOnly = false,
    this.plainHeader = false,
    this.showBackButton = true,
    this.compactTopPadding = 4,
    this.topSurfaceColor,
    this.topSurfaceExtent = 0,
    this.onBack,
  });

  final String title;
  final Widget child;
  final bool compactBackOnly;
  final bool plainHeader;
  final bool showBackButton;
  final double compactTopPadding;
  final Color? topSurfaceColor;
  final double topSurfaceExtent;
  final VoidCallback? onBack;

  @override
  State<SubPageScaffold> createState() => _SubPageScaffoldState();
}

class _SubPageScaffoldState extends State<SubPageScaffold> {
  static const double _floatingHomeButtonSize = 44;
  Offset? _floatingHomeOffset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: palette.pageGradient,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ParchmentTextureLayer(
                opacity: 0.08,
                tint: palette.primaryDeep,
              ),
            ),
          ),
          if (widget.topSurfaceColor != null && widget.topSurfaceExtent > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height:
                  MediaQuery.paddingOf(context).top + widget.topSurfaceExtent,
              child: ColoredBox(
                key: const ValueKey('sub-page-top-surface'),
                color: widget.topSurfaceColor!,
              ),
            ),
          SafeArea(
            child: widget.compactBackOnly && widget.showBackButton
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final maxX = math.max(
                        0.0,
                        constraints.maxWidth - _floatingHomeButtonSize,
                      );
                      final maxY = math.max(
                        0.0,
                        constraints.maxHeight - _floatingHomeButtonSize,
                      );
                      final resolvedOffset = Offset(
                        (_floatingHomeOffset?.dx ?? 6).clamp(0.0, maxX),
                        (_floatingHomeOffset?.dy ?? 6).clamp(0.0, maxY),
                      );

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: widget.compactTopPadding,
                              ),
                              child: widget.child,
                            ),
                          ),
                          Positioned(
                            left: resolvedOffset.dx,
                            top: resolvedOffset.dy,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                setState(() {
                                  _floatingHomeOffset = Offset(
                                    (resolvedOffset.dx + details.delta.dx)
                                        .clamp(0.0, maxX),
                                    (resolvedOffset.dy + details.delta.dy)
                                        .clamp(0.0, maxY),
                                  );
                                });
                              },
                              child: SubPageFloatingHomeButton(
                                onTap: _handleBack,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : widget.compactBackOnly
                ? Padding(
                    padding: EdgeInsets.only(top: widget.compactTopPadding),
                    child: widget.child,
                  )
                : widget.plainHeader
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
                        child: Row(
                          key: const ValueKey('sub-page-plain-header'),
                          children: [
                            if (widget.showBackButton) ...[
                              IconButton(
                                key: const ValueKey('sub-page-plain-back'),
                                tooltip: '이전',
                                onPressed: _handleBack,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                icon: Icon(
                                  Icons.chevron_left_rounded,
                                  size: 28,
                                  color: palette.primaryDeep,
                                ),
                              ),
                              const SizedBox(width: 2),
                            ],
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: largeText ? 2 : 1,
                                overflow: largeText
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: widget.child),
                    ],
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                        child: Row(
                          children: [
                            topUtilityButton(
                              label: '이전',
                              onTap: _handleBack,
                              selected: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                constraints: BoxConstraints(
                                  minHeight: largeText ? 52 : 40,
                                ),
                                alignment: Alignment.centerLeft,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: largeText ? 8 : 0,
                                ),
                                decoration: floatingPanelDecoration(
                                  color: palette.panelSurface,
                                  shadowOpacity: 0.08,
                                ),
                                child: Text(
                                  widget.title,
                                  maxLines: largeText ? 2 : 1,
                                  overflow: largeText
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: widget.child),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _handleBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      Navigator.of(context).pop();
      onBack();
      return;
    }
    Navigator.of(context).pop();
  }
}
