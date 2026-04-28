import 'package:flutter/material.dart';

import 'tokens.dart';

// .sb-surface-* CSS 클래스의 Flutter 대응. 모달/다이얼로그/플로팅/카드 표면.
// 위젯에서 동일한 BoxDecoration을 직접 만들지 말고 여기 팩토리를 호출한다.

class AppSurfaces {
  AppSurfaces._();

  static BoxDecoration modal() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.parchmentLight, AppColors.parchmentWarm],
      ),
      borderRadius: BorderRadius.circular(AppRadii.x4l),
      border: Border.all(color: const Color(0xC29E7A4C), width: 1.2),
      boxShadow: AppShadows.xl,
    );
  }

  static BoxDecoration dialog() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFBF5EA), AppColors.parchmentMid],
      ),
      borderRadius: BorderRadius.circular(AppRadii.xxxl),
      border: Border.all(color: const Color(0xC29E7A4C), width: 1.2),
      boxShadow: AppShadows.lg,
    );
  }

  static BoxDecoration floating({
    Color color = const Color(0xF5F7E9D1),
    double shadowOpacity = 0.12,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.alphaBlend(const Color(0x14FFFFFF), color), color],
      ),
      borderRadius: BorderRadius.circular(AppRadii.xxl),
      border: Border.all(color: const Color(0xB88E6F48), width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: shadowOpacity),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration card() {
    return BoxDecoration(
      color: AppColors.parchmentCard,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      border: Border.all(color: const Color(0xB58E6F48), width: 1.0),
    );
  }
}
