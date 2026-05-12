import 'package:flutter/material.dart';

/// 지도 위에 떠 있는 흐릿한 안내 문구. 사용자가 무엇을 해야 할지 모를 때
/// 화면 가운데에 잠시 보여주고, 사용자가 한 번 행동(폴리곤 탭·줌·인물 선택
/// 후 다음 등)하면 부모가 visible=false 로 dismiss 한다.
///
/// 입력 차단을 안 하므로 hint 가 떠 있어도 그 아래의 폴리곤·핀은 정상 클릭
/// 가능 (부모에서 IgnorePointer 로 감싸 사용).
class MapHintOverlay extends StatelessWidget {
  const MapHintOverlay({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white.withValues(alpha: 0.92), size: 26),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
