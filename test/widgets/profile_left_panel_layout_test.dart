import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프로필 활동 탭은 초록 segmented 버튼 톤을 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('height: 42'));
    expect(source, contains('color: const Color(0xFFF1E1C0)'));
    expect(source, isNot(contains('math.min(constraints.maxWidth, 336.0)')));
    expect(
      source,
      contains('selected ? AppColors.brownWarm : Colors.transparent'),
    );
    expect(source, contains('selected ? Colors.white : AppColors.ink350'));
    expect(source, contains('boxShadow: selected ? AppShadows.sm : null'));
  });

  test('프로필 기록 퀴즈 통계 카드는 높이와 여백을 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('EdgeInsets.fromLTRB(12, 11, 12, 11)'));
    expect(source, contains('const SizedBox(width: 9)'));
    expect(source, contains('BoxConstraints(minHeight: 62)'));
    expect(source, contains('mainAxisAlignment: MainAxisAlignment.center'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.center'));
  });

  test('프로필 전체 진행률 카드는 진행바 중앙에 작은 완료 수와 전체 수를 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains("final valueLabel = '\$completed/\$total';"));
    expect(source, contains('Stack('));
    expect(source, contains('alignment: Alignment.center'));
    expect(source, contains('minHeight: 13'));
    expect(source, contains('fontSize: 9.4'));
    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, isNot(contains("valueSuffix: '장'")));
    expect(source, isNot(contains("'퀴즈를 풀면 기록이 쌓여요.'")));
  });

  test('저장한 이야기 미리보기는 썸네일 카드 높이를 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('return 228;'));
    expect(source, contains('EdgeInsets.fromLTRB(2, 8, 20, 8)'));
  });
}
