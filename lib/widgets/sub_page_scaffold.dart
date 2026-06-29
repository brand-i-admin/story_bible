import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
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
  });

  final String title;
  final Widget child;
  final bool compactBackOnly;

  @override
  State<SubPageScaffold> createState() => _SubPageScaffoldState();
}

class _SubPageScaffoldState extends State<SubPageScaffold> {
  static const double _floatingHomeButtonSize = 44;
  Offset? _floatingHomeOffset;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.parchmentLight,
                    AppColors.parchmentMid,
                    AppColors.parchmentWarm,
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: ParchmentTextureLayer(
                opacity: 0.08,
                tint: AppColors.brownWarm2,
              ),
            ),
          ),
          SafeArea(
            child: widget.compactBackOnly
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
                              padding: const EdgeInsets.only(top: 4),
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
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                        child: Row(
                          children: [
                            topUtilityButton(
                              label: '이전',
                              onTap: () => Navigator.of(context).pop(),
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
                                  color: AppColors.floatingSurfaceDefault,
                                  shadowOpacity: 0.08,
                                ),
                                child: Text(
                                  widget.title,
                                  maxLines: largeText ? 2 : 1,
                                  overflow: largeText
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: const TextStyle(
                                    color: AppColors.ink500,
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
}
