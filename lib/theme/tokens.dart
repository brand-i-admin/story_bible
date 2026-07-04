import 'package:flutter/material.dart';

// Story Bible 디자인 시스템 토큰 — 단일 진실 소스(single source of truth).
//
// 3D 지형 지도(OpenFreeMap Liberty + DEM)는 유지하고, 앱 chrome/버튼/카드는
// 홍보 이미지의 밝은 지도 종이, 네이비 잉크, 청록 수계 톤과 맞춘다.
// 위젯/화면에서 hex 코드를 직접 쓰지 말고 여기 토큰만 참조한다.

class AppColors {
  AppColors._();

  // BASE PALETTE — bright map paper
  static const parchmentBg = Color(0xFFF2EFE3);
  static const parchmentLight = Color(0xFFFFFCF3);
  static const parchmentMid = Color(0xFFF4ECDD);
  static const parchmentWarm = Color(0xFFEDE1CD);
  static const parchmentCream = Color(0xFFFFFFF7);
  static const parchmentCard = Color(0xFFFFF9EC);
  static const parchmentCardAlt = Color(0xFFEEF4E6);
  static const parchmentDim = Color(0xFFEFE7D8);

  // NAVY INK — text / chrome
  static const ink900 = Color(0xFF09264A);
  static const ink800 = Color(0xFF0C315E);
  static const ink700 = Color(0xFF153E67);
  static const ink600 = Color(0xFF264E74);
  static const ink500 = Color(0xFF365F80);
  static const ink450 = Color(0xFF436C86);
  static const ink400 = Color(0xFF50758C);
  static const ink350 = Color(0xFF5A7A8E);
  static const ink300 = Color(0xFF6A8492);
  static const ink200 = Color(0xFF7E908F);
  static const ink150 = Color(0xFF909B91);
  static const ink100 = Color(0xFFA3AA99);

  // BRAND ACCENTS
  static const seed = Color(0xFF087986);
  static const oceanTop = Color(0xFF0FA7AC);
  static const oceanBot = Color(0xFF087986);
  static const oceanDeep = Color(0xFF073D5A);
  static const oceanRim = Color(0xFFB8E7E4);
  static const gold = Color(0xFFF2A738);
  static const goldDeep = Color(0xFFD77C1E);
  static const goldLight = Color(0xFFF7B957);
  static const goldHi = Color(0xFFFFE0A3);
  static const goldRim = Color(0xFFFFE7B8);
  // Legacy names retained for existing widgets: selected UI now uses ocean/navy.
  static const brownWarm = oceanBot;
  static const brownWarm2 = oceanDeep;
  static const brownRim = oceanRim;
  static const brownEdge = Color(0xFF60908C);
  static const brownEdge2 = Color(0xFF739F9A);

  // Success
  static const greenTop = Color(0xFF68C48C);
  static const greenBot = Color(0xFF2B8A62);
  static const greenRim = Color(0xFFD7F1DC);
  static const greenTint1 = Color(0xFFEAF7EC);
  static const greenTint2 = Color(0xFFD9F0DF);
  static const greenBorder = Color(0xFF8DCA9C);
  static const greenBtnTop = Color(0xFF66C18A);
  static const greenBtnBot = Color(0xFF2D8E63);

  // Danger
  static const dangerTop = Color(0xFFE27B68);
  static const dangerBot = Color(0xFFB84F3F);
  static const dangerRim = Color(0xFFF7C5BA);

  // REGION HIGHLIGHT — 지도 era 폴리곤 영역 표시 (story_map_panel + era_polygon_glow_layer).
  // 후보 = 밝은 옐로우 골드, 선택 = 밝은 sage green. ancient atlas 양피지 위에서
  // 또렷이 살아남도록 stepper accent(panel_chrome._stageAccentColor) 의 어두운
  // 톤(D2873E/77A85A) 보다 더 밝고 채도 높은 값을 사용.
  // era 식별은 era_pick_rows 의 점·아이콘 색으로 별도 제공.
  static const regionCandidate = Color(0xFFD7B75A); // muted topographic ochre
  static const regionSelected = Color(0xFFA9C982); // terrain sage green

  /// region fill 칠하기 전 베이스를 중성화하는 cream-white wash.
  /// 지도 베이스가 따뜻한 베이지라 그 위에 candidate/selected 색을 alpha 로
  /// 얹으면 베이스+색 blend 가 갈색/어두운 톤으로 보임.
  /// 이 wash 를 한 겹 먼저 깔아 베이스를 중성화하면 의도된 노랑/초록이 살아남는다.
  static const regionParchmentWash = Color(0xFFF8F3E4);

  // Semantic
  static const fgOnDark = Color(0xFFFFFCF3);
  static const fgOnGold = parchmentCream;
  static const borderHairlineDark = Color(0xFFB8D8D6);

  // Alpha 적용 보더(청록 해안선 계열) — surfaces 팩토리에서 사용
  static const borderModalDialog = Color(0xCC5D8F8B);
  static const borderFloating = Color(0xC06D9D9A);
  static const borderCard = Color(0xAA6D9D9A);

  // 표면 기본/오버레이
  static const floatingSurfaceDefault = Color(0xFAFCF9EF);
  static const dialogTopHighlight = Color(0xFFFFFFF8);
  static const overlayWhiteSoft = Color(0x14FFFFFF); // 8% white, alpha-blend용

  // 인물 색상 fallback — selectedCharacterColors에 매핑이 없을 때
  static const characterFallback = Color(0xFF5A7F8A);

  // CHARACTER PALETTE — 8색 순환 (i % 8)
  static const characters = <Color>[
    Color(0xFF2F6F88), // 0 water blue
    Color(0xFFA7633A), // 1 clay
    Color(0xFF5F7D3B), // 2 olive
    Color(0xFF965C62), // 3 rose
    Color(0xFF5E665A), // 4 stone
    Color(0xFFB28A2E), // 5 ochre
    Color(0xFF776243), // 6 earth
    Color(0xFF4F7F85), // 7 teal
  ];

  static Color characterAt(int index) =>
      characters[index.remainder(characters.length).abs()];
}

class AppRadii {
  AppRadii._();

  static const xs = 8.0; // map control btn
  static const sm = 10.0; // chip
  static const md = 12.0; // utility btn, cards
  static const lg = 14.0; // soft button, dialog action
  static const xl = 18.0; // interactive card, input
  static const xxl = 22.0; // floating panel
  static const xxxl = 24.0; // dialog surface
  static const x4l = 28.0; // modal surface
  static const pill = 999.0;
}

class AppSpacing {
  AppSpacing._();

  // Flutter 픽셀 어휘 (8px 배수가 아님 — 의도적)
  static const x1 = 4.0;
  static const x2 = 6.0;
  static const x3 = 8.0;
  static const x4 = 10.0;
  static const x5 = 12.0;
  static const x6 = 14.0;
  static const x7 = 16.0;
  static const x8 = 18.0;
  static const x9 = 20.0;
  static const x10 = 24.0;
}

class AppShadows {
  AppShadows._();

  static const sm = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
  static const md = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const lg = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 14)),
  ];
  static const xl = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 18)),
  ];
  static const gold = <BoxShadow>[
    BoxShadow(color: Color(0x26F2A738), blurRadius: 10, offset: Offset(0, 5)),
  ];
  static const green = <BoxShadow>[
    BoxShadow(color: Color(0x212B8A62), blurRadius: 10, offset: Offset(0, 5)),
  ];
  static const goldGlow = <BoxShadow>[
    BoxShadow(color: Color(0x45F7B957), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

class AppFontSizes {
  AppFontSizes._();

  static const xs = 10.4;
  static const sm = 11.2;
  static const base = 12.0;
  static const btn = 12.5;
  static const body = 13.0;
  static const chip = 13.4;
  static const input = 14.5;
  static const dialog = 18.5;
  static const title = 20.0;
  static const display = 28.0;
}

class AppLineHeights {
  AppLineHeights._();

  static const tight = 1.1;
  static const snug = 1.15;
  static const normal = 1.4;
  static const body = 1.45;
}
