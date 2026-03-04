import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/navigation/app_route_observer.dart';
import 'core/theme/app_colors.dart';
import 'features/bible_study/presentation/bible_study_screen.dart';

class StoryBibleApp extends StatelessWidget {
  const StoryBibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Story Bible',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.woodMid),
        scaffoldBackgroundColor: AppColors.woodDark,
        textTheme: GoogleFonts.notoSerifKrTextTheme(),
      ),
      navigatorObservers: [appRouteObserver],
      home: const BibleStudyScreen(),
    );
  }
}
