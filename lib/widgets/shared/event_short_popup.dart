import 'package:flutter/material.dart';

import '../../models/story_event.dart';
import '../story_home_styles.dart';

/// 지도 위 핀 콜아웃과 주간 스터디 단축 팝업에서 함께 사용하는 위젯.
///
/// 이전에는 `story_map_panel._buildEventCallout`와
/// `weekly_tab_page._weeklyShortPopup`로 거의 동일한 코드가 중복돼 있었다.
/// 양피지 테마(filledActionButton, floatingPanelDecoration)를 공유한다.
class EventShortPopup extends StatelessWidget {
  const EventShortPopup({
    super.key,
    required this.event,
    required this.onClose,
    required this.onOpenDetail,
    this.maxWidth,
    this.maxHeight,
    this.shortText,
    this.detailLabel = '자세히 보기',
  });

  final StoryEvent event;

  /// null이면 닫기 버튼이 표시되지 않는다.
  final VoidCallback? onClose;

  /// null이면 "자세히 보기" 버튼이 비활성화된다.
  final VoidCallback? onOpenDetail;

  /// 최대 너비 제약 (지도 콜아웃 모드에서 사용).
  final double? maxWidth;

  /// 최대 높이 제약 (주간 단축 팝업 모드에서 사용, 스크롤 가능).
  final double? maxHeight;

  /// 본문 텍스트. null이면 event의 shortStory > story > summary 순으로 자동 추출.
  final String? shortText;

  /// 액션 버튼 라벨.
  final String detailLabel;

  String _resolvedShortText() {
    if (shortText != null) return shortText!.trim();
    return (event.shortStory ?? event.story ?? event.summary ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final body = _PopupBody(
      title: event.title,
      shortText: _resolvedShortText(),
      detailLabel: detailLabel,
      onOpenDetail: onOpenDetail,
      onClose: onClose,
    );

    Widget content = DecoratedBox(
      decoration: floatingPanelDecoration(
        color: const Color(0xFFF9F1E4),
        shadowOpacity: 0.28,
      ),
      child: maxHeight != null ? SingleChildScrollView(child: body) : body,
    );

    if (maxWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      );
    }
    if (maxHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: content,
      );
    }

    return Material(color: Colors.transparent, child: content);
  }
}

class _PopupBody extends StatelessWidget {
  const _PopupBody({
    required this.title,
    required this.shortText,
    required this.detailLabel,
    required this.onOpenDetail,
    required this.onClose,
  });

  final String title;
  final String shortText;
  final String detailLabel;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 48, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF3D2D18),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (shortText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  shortText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4C3A21),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: filledActionButton(
                  label: detailLabel,
                  onTap: onOpenDetail ?? () {},
                  compact: true,
                  minWidth: 96,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null)
          Positioned(
            right: 10,
            top: 8,
            child: modalCloseButton(size: 24, onTap: onClose!),
          ),
      ],
    );
  }
}
