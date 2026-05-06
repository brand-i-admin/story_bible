import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/story_home_screen.dart';
import 'state/font_scale_providers.dart';
import 'theme/app_theme.dart';

/// `MaterialApp.builder`에 주입되어 `MediaQuery.textScaler`를 `fontScaleProvider`
/// 값에 동기화한다. 테스트에서도 재사용하기 위해 top-level로 분리.
Widget fontScaleBuilder(BuildContext context, Widget? child) {
  if (child == null) {
    return const SizedBox.shrink();
  }
  return Consumer(
    builder: (context, ref, _) {
      final fontScale = ref.watch(fontScaleProvider);
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: TextScaler.linear(fontScale.ratio)),
        child: child,
      );
    },
  );
}

class StoryBibleApp extends StatelessWidget {
  const StoryBibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Story Bible',
      theme: AppTheme.light(),
      builder: fontScaleBuilder,
      // 모든 흐름을 StoryHomeScreen 한 화면에 통합. 시대 선택 단계가
      // 시대 멀티 + [지역/인물] 분기 카드 (HomeIntroPanel) 로 구성되고,
      // 모드 선택 후 인물 모드는 기존 인물/사건 단계, 지역 모드는 region 패널로
      // 같은 화면 안에서 swap 된다.
      home: const StoryHomeScreen(),
    );
  }
}
