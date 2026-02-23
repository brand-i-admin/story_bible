import 'package:flutter/material.dart';

import 'screens/story_home_screen.dart';

class StoryBibleApp extends StatelessWidget {
  const StoryBibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Story Bible',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5A2B)),
        scaffoldBackgroundColor: const Color(0xFFEEE0C6),
      ),
      home: const StoryHomeScreen(),
    );
  }
}
