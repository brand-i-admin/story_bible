import 'package:flutter/material.dart';

// Story Bible 디자인 시스템 토큰 — 단일 진실 소스(single source of truth).
//
// 출처: Claude Design 핸드오프 번들 `colors_and_type.css`.
// 위젯/화면에서 hex 코드를 직접 쓰지 말고 여기 토큰만 참조한다.

class AppColors {
  AppColors._();

  // BASE PALETTE — Parchment & Brown
  static const parchmentBg = Color(0xFFEEE0C6);
  static const parchmentLight = Color(0xFFF8F1E4);
  static const parchmentMid = Color(0xFFF2E5CC);
  static const parchmentWarm = Color(0xFFF1E2C6);
  static const parchmentCream = Color(0xFFFDF8EE);
  static const parchmentCard = Color(0xFFF7EBD8);
  static const parchmentCardAlt = Color(0xFFEFE3CC);
  static const parchmentDim = Color(0xFFF3E6D0);

  // BROWN SPINE — text / borders
  static const ink900 = Color(0xFF2A2118);
  static const ink800 = Color(0xFF3B2A17);
  static const ink700 = Color(0xFF3E2723);
  static const ink600 = Color(0xFF402B18);
  static const ink500 = Color(0xFF4A331D);
  static const ink450 = Color(0xFF4D381F);
  static const ink400 = Color(0xFF5C4326);
  static const ink350 = Color(0xFF5E4528);
  static const ink300 = Color(0xFF6E512C);
  static const ink200 = Color(0xFF8A6A46);
  static const ink150 = Color(0xFF9B805D);
  static const ink100 = Color(0xFF8E6F48);

  // BRAND ACCENTS
  static const seed = Color(0xFF8B5A2B);
  static const gold = Color(0xFFD4A439);
  static const goldDeep = Color(0xFFB96B2D);
  static const goldLight = Color(0xFFD89A47);
  static const goldHi = Color(0xFFF2D8A6);
  static const goldRim = Color(0xFFF0C36B);
  static const brownWarm = Color(0xFFC8863B);
  static const brownWarm2 = Color(0xFFA85B25);
  static const brownRim = Color(0xFFF1D39C);
  static const brownEdge = Color(0xFF9A7A4C);
  static const brownEdge2 = Color(0xFF9E7A4C);

  // Success
  static const greenTop = Color(0xFF48A86B);
  static const greenBot = Color(0xFF2D7B4D);
  static const greenRim = Color(0xFFD9F0D0);
  static const greenTint1 = Color(0xFFE3F3DE);
  static const greenTint2 = Color(0xFFD2EBCB);
  static const greenBorder = Color(0xFF7FB07B);
  static const greenBtnTop = Color(0xFF58B573);
  static const greenBtnBot = Color(0xFF2D8754);

  // Danger
  static const dangerTop = Color(0xFFD97C60);
  static const dangerBot = Color(0xFFB4583B);
  static const dangerRim = Color(0xFFF2C2B3);

  // Semantic
  static const fgOnDark = Color(0xFFF8EED9);
  static const fgOnGold = parchmentCream;
  static const borderHairlineDark = Color(0xFFD8BF99);

  // CHARACTER PALETTE — 8색 순환 (i % 8)
  static const characters = <Color>[
    Color(0xFF3B6C94), // 0 blue
    Color(0xFFB6673C), // 1 orange
    Color(0xFF557C3E), // 2 green
    Color(0xFF8A4E5D), // 3 rose
    Color(0xFF616161), // 4 gray
    Color(0xFF9E7C24), // 5 gold
    Color(0xFF7B5D43), // 6 brown
    Color(0xFF5C6B9F), // 7 indigo
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
    BoxShadow(color: Color(0x223D8758), blurRadius: 10, offset: Offset(0, 5)),
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
