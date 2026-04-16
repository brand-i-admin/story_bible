import 'package:flutter/material.dart';

/// 서브 페이지 상단/모서리에 떠있는 홈 이동 버튼.
///
/// [SubPageScaffold]의 compactBackOnly 모드에서 사용한다.
class SubPageFloatingHomeButton extends StatelessWidget {
  const SubPageFloatingHomeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xD06A401E),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF0C36B), width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: Color(0xFFF8EED9),
          ),
        ),
      ),
    );
  }
}
