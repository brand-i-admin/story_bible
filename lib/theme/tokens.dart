import 'package:flutter/material.dart';

// Story Bible 디자인 시스템 토큰 — 단일 진실 소스(single source of truth).
//
// 3D 지형 지도(OpenFreeMap Liberty + DEM)의 밝은 석회 베이지, 세이지 그린,
// 올리브 브라운, 옅은 수계 블루와 맞도록 전역 톤을 맞춘다.
// 위젯/화면에서 hex 코드를 직접 쓰지 말고 여기 토큰만 참조한다.

class AppColors {
  AppColors._();

  // BASE PALETTE — terrain limestone & sage parchment
  static const parchmentBg = Color(0xFFE8E6D8);
  static const parchmentLight = Color(0xFFF8F4E7);
  static const parchmentMid = Color(0xFFEDE7D6);
  static const parchmentWarm = Color(0xFFE6D9BF);
  static const parchmentCream = Color(0xFFFCF8EC);
  static const parchmentCard = Color(0xFFF2EAD8);
  static const parchmentCardAlt = Color(0xFFE4DEC8);
  static const parchmentDim = Color(0xFFEAE4D3);

  // OLIVE INK — text / borders
  static const ink900 = Color(0xFF22271D);
  static const ink800 = Color(0xFF2D3022);
  static const ink700 = Color(0xFF33331F);
  static const ink600 = Color(0xFF3B3926);
  static const ink500 = Color(0xFF47442D);
  static const ink450 = Color(0xFF4F4D34);
  static const ink400 = Color(0xFF5B563B);
  static const ink350 = Color(0xFF665F43);
  static const ink300 = Color(0xFF70684B);
  static const ink200 = Color(0xFF82785A);
  static const ink150 = Color(0xFF998F70);
  static const ink100 = Color(0xFF8A7E5E);

  // BRAND ACCENTS
  static const seed = Color(0xFF5F7040);
  static const gold = Color(0xFFC69B3F);
  static const goldDeep = Color(0xFFA2702C);
  static const goldLight = Color(0xFFD2AD61);
  static const goldHi = Color(0xFFE7D8A2);
  static const goldRim = Color(0xFFE6D18B);
  static const brownWarm = Color(0xFF7B9155);
  static const brownWarm2 = Color(0xFF526F3F);
  static const brownRim = Color(0xFFDDE8BD);
  static const brownEdge = Color(0xFF7B7656);
  static const brownEdge2 = Color(0xFF85805D);

  // Success
  static const greenTop = Color(0xFF6FA76D);
  static const greenBot = Color(0xFF477D52);
  static const greenRim = Color(0xFFDCECC7);
  static const greenTint1 = Color(0xFFE7F0DB);
  static const greenTint2 = Color(0xFFD9E8C7);
  static const greenBorder = Color(0xFF8EAD72);
  static const greenBtnTop = Color(0xFF77A963);
  static const greenBtnBot = Color(0xFF4E7E50);

  // Danger
  static const dangerTop = Color(0xFFD97C60);
  static const dangerBot = Color(0xFFB4583B);
  static const dangerRim = Color(0xFFF2C2B3);

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
  static const fgOnDark = Color(0xFFF8F3E4);
  static const fgOnGold = parchmentCream;
  static const borderHairlineDark = Color(0xFFD7C8A6);

  // Alpha 적용 보더(브라운 계열) — surfaces 팩토리에서 사용
  static const borderModalDialog = Color(0xC285805D); // brownEdge2 @ 0.76
  static const borderFloating = Color(0xB88A7E5E); // ink100 @ 0.72
  static const borderCard = Color(0xB58A7E5E); // ink100 @ 0.71

  // 표면 기본/오버레이
  static const floatingSurfaceDefault = Color(0xF5F3EBD9);
  static const dialogTopHighlight = Color(0xFFFBF7EA);
  static const overlayWhiteSoft = Color(0x14FFFFFF); // 8% white, alpha-blend용

  // 인물 색상 fallback — selectedCharacterColors에 매핑이 없을 때
  static const characterFallback = Color(0xFF7E7A63);

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
    BoxShadow(color: Color(0x26A35B22), blurRadius: 10, offset: Offset(0, 5)),
  ];
  static const green = <BoxShadow>[
    BoxShadow(color: Color(0x213D8758), blurRadius: 10, offset: Offset(0, 5)),
  ];
  static const goldGlow = <BoxShadow>[
    BoxShadow(color: Color(0x45F0C36B), blurRadius: 8, offset: Offset(0, 2)),
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
