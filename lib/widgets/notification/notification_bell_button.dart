import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_notification.dart';
import '../../state/notification_providers.dart';
import 'notification_badge.dart';
import 'notification_dropdown.dart';

/// 홈화면 상단의 종(bell) 아이콘 버튼.
///
/// - `unreadNotificationCountProvider` 를 구독해 읽지 않은 개수가 1개 이상이면
///   빨간 느낌표 배지 표시.
/// - 클릭하면 우측에 [NotificationDropdown] 을 Overlay 로 띄움.
/// - 알림 탭 시 호출자가 주입한 [onNavigate] 로 이동 책임 위임.
class NotificationBellButton extends ConsumerStatefulWidget {
  const NotificationBellButton({
    super.key,
    required this.onNavigate,
    required this.onOpenHistory,
  });

  /// 알림을 탭했을 때 호출 — 호출자가 deep_link 를 받아 화면 전환.
  final void Function(AppNotification notification) onNavigate;

  /// "전체 보기" 탭 시 호출 — 호출자가 히스토리 화면 push.
  final VoidCallback onOpenHistory;

  @override
  ConsumerState<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState
    extends ConsumerState<NotificationBellButton> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  void _toggleDropdown() {
    if (_overlay != null) {
      _closeDropdown();
      return;
    }
    _openDropdown();
  }

  void _openDropdown() {
    final overlay = Overlay.of(context);
    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;

    _overlay = OverlayEntry(
      builder: (ctx) {
        // Dropdown 을 종 버튼 우측에 맞춰 정렬하고 viewport 안에 clamp.
        // 종이 화면 right edge 가까이 있을 때 dropdown 이 잘리지 않도록.
        const dropdownWidth = 340.0;
        const screenPadding = 8.0;
        final screenWidth = MediaQuery.of(ctx).size.width;
        final preferredLeft =
            anchorPosition.dx + anchorSize.width - dropdownWidth;
        final left = preferredLeft.clamp(
          screenPadding,
          screenWidth - dropdownWidth - screenPadding,
        );
        return Stack(
          children: [
            // Barrier: 바깥 탭으로 닫기.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDropdown,
                child: const ColoredBox(color: Color(0x00000000)),
              ),
            ),
            Positioned(
              left: left,
              top: anchorPosition.dy + anchorSize.height + 6,
              child: NotificationDropdown(
                onClose: _closeDropdown,
                onTapItem: (n) {
                  _closeDropdown();
                  widget.onNavigate(n);
                },
                onOpenHistory: () {
                  _closeDropdown();
                  widget.onOpenHistory();
                },
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
  }

  void _closeDropdown() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final unread =
        ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    return Material(
      key: _anchorKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 36,
          width: 38,
          decoration: BoxDecoration(
            color: const Color(0xB02A2118),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xBFD8BF99), width: 0.9),
          ),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_outlined,
                color: Color(0xFFF8EED9),
                size: 19,
              ),
              NotificationBadge(visible: unread > 0),
            ],
          ),
        ),
      ),
    );
  }
}
