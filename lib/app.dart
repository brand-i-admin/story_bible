// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
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
        data: media.copyWith(
          textScaler: TextScaler.linear(fontScale.ratio),
        ),
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
      home: const StoryHomeScreen(),
    );
  }
}
