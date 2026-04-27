import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/theme/surfaces.dart';
import 'package:story_bible/theme/tokens.dart';

void main() {
  group('AppColors', () {
    test('parchment 베이스가 colors_and_type.css와 일치한다', () {
      expect(AppColors.parchmentBg, const Color(0xFFEEE0C6));
      expect(AppColors.parchmentLight, const Color(0xFFF8F1E4));
      expect(AppColors.parchmentCard, const Color(0xFFF7EBD8));
    });

    test('브라운 잉크 스파인이 어두운 → 밝은 순서로 배치된다', () {
      expect(AppColors.ink900, const Color(0xFF2A2118));
      expect(AppColors.ink700, const Color(0xFF3E2723));
      expect(AppColors.ink100, const Color(0xFF8E6F48));
    });

    test('브랜드 액센트 시드/골드가 일치한다', () {
      expect(AppColors.seed, const Color(0xFF8B5A2B));
      expect(AppColors.gold, const Color(0xFFD4A439));
    });

    test('인물 팔레트는 8색이고 i % 8로 순환한다', () {
      expect(AppColors.characters, hasLength(8));
      expect(AppColors.characterAt(0), AppColors.characters[0]);
      expect(AppColors.characterAt(8), AppColors.characters[0]);
      expect(AppColors.characterAt(15), AppColors.characters[7]);
      expect(AppColors.characterAt(-1), isNotNull);
    });
  });

  group('AppRadii', () {
    test('정의된 라운딩이 점진적으로 커진다', () {
      expect(AppRadii.xs, lessThan(AppRadii.sm));
      expect(AppRadii.sm, lessThan(AppRadii.md));
      expect(AppRadii.md, lessThan(AppRadii.xl));
      expect(AppRadii.xl, lessThan(AppRadii.xxl));
      expect(AppRadii.xxl, lessThan(AppRadii.x4l));
      expect(AppRadii.pill, 999.0);
    });
  });

  group('AppSpacing', () {
    test('Flutter 픽셀 어휘 (4/6/8/10/12/14/16/18/20/24)를 따른다', () {
      expect(
        <double>[
          AppSpacing.x1,
          AppSpacing.x2,
          AppSpacing.x3,
          AppSpacing.x4,
          AppSpacing.x5,
          AppSpacing.x6,
          AppSpacing.x7,
          AppSpacing.x8,
          AppSpacing.x9,
          AppSpacing.x10,
        ],
        <double>[4, 6, 8, 10, 12, 14, 16, 18, 20, 24],
      );
    });
  });

  group('AppTheme', () {
    test('light 테마가 시드 컬러와 양피지 배경을 사용한다', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, true);
      expect(theme.scaffoldBackgroundColor, AppColors.parchmentBg);
    });
  });

  group('AppSurfaces', () {
    test('modal/dialog/floating/card가 BoxDecoration을 반환한다', () {
      expect(AppSurfaces.modal(), isA<BoxDecoration>());
      expect(AppSurfaces.dialog(), isA<BoxDecoration>());
      expect(AppSurfaces.floating(), isA<BoxDecoration>());
      expect(AppSurfaces.card(), isA<BoxDecoration>());
    });

    test('card 표면이 parchmentCard 배경을 사용한다', () {
      final card = AppSurfaces.card();
      expect(card.color, AppColors.parchmentCard);
    });
  });
}
