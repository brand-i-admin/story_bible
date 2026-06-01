import 'package:flutter/material.dart';

import 'tokens.dart';

// .sb-* 시맨틱 클래스의 Flutter 대응. 위젯에서 임의 TextStyle 생성 대신 사용한다.
//
// 패밀리는 Flutter 기본을 유지(별도 webfont 미사용). 시스템 폰트 폴백이
// Noto Sans/Serif KR 근사치를 자연 적용한다.

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle h1 = TextStyle(
    fontSize: AppFontSizes.display,
    fontWeight: FontWeight.w900,
    height: AppLineHeights.snug,
    color: AppColors.ink700,
    letterSpacing: 0,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: AppFontSizes.title,
    fontWeight: FontWeight.w900,
    height: AppLineHeights.snug,
    color: AppColors.ink700,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: AppFontSizes.dialog,
    fontWeight: FontWeight.w900,
    height: AppLineHeights.snug,
    color: AppColors.ink800,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: FontWeight.w800,
    height: AppLineHeights.tight,
    color: AppColors.ink450,
  );

  static const TextStyle body = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: FontWeight.w400,
    height: AppLineHeights.body,
    color: AppColors.ink800,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: AppFontSizes.sm,
    fontWeight: FontWeight.w700,
    height: AppLineHeights.normal,
    color: AppColors.ink200,
  );

  static const TextStyle chipLabel = TextStyle(
    fontSize: AppFontSizes.chip,
    fontWeight: FontWeight.w800,
    height: AppLineHeights.tight,
    color: AppColors.fgOnDark,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: AppFontSizes.btn,
    fontWeight: FontWeight.w900,
    height: 1.0,
    color: AppColors.fgOnGold,
  );

  static const TextStyle hint = TextStyle(
    fontSize: 13.6,
    fontWeight: FontWeight.w600,
    color: AppColors.ink150,
  );

  static const TextStyle counter = TextStyle(
    fontSize: AppFontSizes.xs,
    fontWeight: FontWeight.w700,
    color: AppColors.ink150,
  );
}
