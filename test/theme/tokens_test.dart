import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/theme/app_color_palette.dart';
import 'package:story_bible/theme/app_theme.dart';
import 'package:story_bible/theme/surfaces.dart';
import 'package:story_bible/theme/tokens.dart';

void main() {
  group('AppColors', () {
    test('parchment 베이스가 밝은 홍보 지도 종이 톤과 일치한다', () {
      expect(AppColors.parchmentBg, const Color(0xFFF2EFE3));
      expect(AppColors.parchmentLight, const Color(0xFFFFFCF3));
      expect(AppColors.parchmentCard, const Color(0xFFFFF9EC));
    });

    test('네이비 잉크 스파인이 어두운 → 밝은 순서로 배치된다', () {
      expect(AppColors.ink900, const Color(0xFF09264A));
      expect(AppColors.ink700, const Color(0xFF153E67));
      expect(AppColors.ink100, const Color(0xFFA3AA99));
    });

    test('브랜드 액센트 청록/골드가 일치한다', () {
      expect(AppColors.seed, const Color(0xFF087986));
      expect(AppColors.oceanTop, const Color(0xFF0FA7AC));
      expect(AppColors.oceanBot, const Color(0xFF087986));
      expect(AppColors.oceanDeep, const Color(0xFF073D5A));
      expect(AppColors.gold, const Color(0xFFF2A738));
    });

    test('인물 팔레트는 8색이고 i % 8로 순환한다', () {
      expect(AppColors.characters, hasLength(8));
      expect(AppColors.characterAt(0), AppColors.characters[0]);
      expect(AppColors.characterAt(8), AppColors.characters[0]);
      expect(AppColors.characterAt(15), AppColors.characters[7]);
      // 음수 인덱스도 안전 (remainder().abs())
      expect(AppColors.characterAt(-1), AppColors.characters[1]);
      expect(AppColors.characterAt(-8), AppColors.characters[0]);
      expect(AppColors.characterAt(-9), AppColors.characters[1]);
    });

    test('인물 팔레트 8색이 지도 위 경로 톤과 정확히 일치한다', () {
      expect(AppColors.characters, const <Color>[
        Color(0xFF2F6F88),
        Color(0xFFA7633A),
        Color(0xFF5F7D3B),
        Color(0xFF965C62),
        Color(0xFF5E665A),
        Color(0xFFB28A2E),
        Color(0xFF776243),
        Color(0xFF4F7F85),
      ]);
    });

    test('상태색(완료/위험)이 현재 톤과 일치한다', () {
      expect(AppColors.greenTop, const Color(0xFF68C48C));
      expect(AppColors.greenBot, const Color(0xFF2B8A62));
      expect(AppColors.dangerTop, const Color(0xFFE27B68));
      expect(AppColors.dangerBot, const Color(0xFFB84F3F));
    });

    test('characterFallback과 표면 보더 토큰이 정의된다', () {
      expect(AppColors.characterFallback, const Color(0xFF5A7F8A));
      expect(AppColors.borderModalDialog, const Color(0xCC5D8F8B));
      expect(AppColors.borderFloating, const Color(0xC06D9D9A));
      expect(AppColors.borderCard, const Color(0xAA6D9D9A));
    });
  });

  group('AppShadows', () {
    test('green 그림자 alpha가 0.13(0x21)을 유지한다', () {
      // 회귀 보호: 0x22(0.133)로 잘못 정의되면 fail
      expect(AppShadows.green.first.color, const Color(0x212B8A62));
    });

    test('의미별 그림자가 모두 단일 BoxShadow를 갖는다', () {
      expect(AppShadows.sm, hasLength(1));
      expect(AppShadows.md, hasLength(1));
      expect(AppShadows.lg, hasLength(1));
      expect(AppShadows.xl, hasLength(1));
      expect(AppShadows.gold, hasLength(1));
      expect(AppShadows.green, hasLength(1));
      expect(AppShadows.goldGlow, hasLength(1));
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

  group('AppColorPalette', () {
    test('classic은 main 기준 어두운 올리브 상단 버튼과 골드 미션색을 사용한다', () {
      expect(
        AppColorPalette.classic.utilityBackground,
        const Color(0xC222271D),
      );
      expect(
        AppColorPalette.classic.utilitySelectedBackground,
        const Color(0xEB526F3F),
      );
      expect(AppColorPalette.classic.currentAccent, const Color(0xFFE8A33D));
    });

    test('brightCoast는 atlasNavy와 겹치지 않는 파스텔 초록·주황·보라 조합이다', () {
      expect(AppColorPalette.brightCoast.primary, const Color(0xFF7AAA6D));
      expect(
        AppColorPalette.brightCoast.currentAccent,
        const Color(0xFFE9A85D),
      );
      expect(AppColorPalette.brightCoast.stepStory, const Color(0xFFA982B8));
      expect(
        AppColorPalette.brightCoast.primary,
        isNot(AppColorPalette.atlasNavy.primary),
      );
      expect(
        AppColorPalette.brightCoast.primaryDeep,
        isNot(AppColorPalette.atlasNavy.primaryDeep),
      );
    });
  });

  group('AppTheme', () {
    test('light 테마가 시드 컬러와 양피지 배경을 사용한다', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, true);
      expect(theme.scaffoldBackgroundColor, AppColors.parchmentBg);
      expect(
        theme.extension<AppPaletteTheme>()?.palette,
        AppColorPalette.classic,
      );
    });

    test('light 테마는 선택한 팔레트를 ThemeExtension과 ColorScheme에 반영한다', () {
      final theme = AppTheme.light(palette: AppColorPalette.colorfulMap);

      expect(
        theme.extension<AppPaletteTheme>()?.palette,
        AppColorPalette.colorfulMap,
      );
      expect(theme.colorScheme.primary, AppColorPalette.colorfulMap.primary);
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
