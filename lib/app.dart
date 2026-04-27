import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/story_home_screen.dart';
import 'theme/app_theme.dart';

class StoryBibleApp extends ConsumerWidget {
  const StoryBibleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Story Bible',
      theme: AppTheme.light(),
      home: const StoryHomeScreen(),
    );
  }
}
