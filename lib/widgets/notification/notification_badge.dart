import 'package:flutter/material.dart';

/// 알림 아이콘 우상단에 얹는 빨간색 배지.
/// 읽지 않은 알림이 1개 이상이면 빨간 동그라미 + 느낌표.
/// 개수는 표시하지 않는다 (디자인 요구: "! 표로 표시").
class NotificationBadge extends StatelessWidget {
  const NotificationBadge({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      right: 2,
      top: 2,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFDF8EE), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55B00020),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
