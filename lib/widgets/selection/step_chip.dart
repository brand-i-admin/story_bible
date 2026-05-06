// 부모 라이브러리: lib/widgets/story_selection_panel.dart
//
// 단계 칩, 요약 필, 분절 토글, 주요 액션 버튼, 빈 단계 메시지 등
// 단계(step) 인터랙션 관련 위젯을 모은 파트 파일.
part of '../story_selection_panel.dart';

class _EmptyStepMessage extends StatelessWidget {
  const _EmptyStepMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6A4C33),
            fontSize: 14.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
