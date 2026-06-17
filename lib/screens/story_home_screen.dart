import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/era.dart';
import '../models/event_emotion_mark.dart';
import '../models/landmark.dart';
import '../models/quiz_question.dart';
import '../models/story_event.dart';
import '../services/push_service.dart';
import '../state/auth_providers.dart';
import '../state/notification_providers.dart';
import '../state/proposal_providers.dart';
import '../state/story_controller.dart';
import '../state/story_state.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';
import '../utils/home_back_navigation.dart';
import '../utils/scene_asset_loader.dart';
import '../widgets/bible_reader_page.dart';
import '../widgets/character_panel.dart';
import '../widgets/completion_celebration.dart';
import '../widgets/event_detail_page.dart';
import '../widgets/event_quiz_dialog.dart';
import '../widgets/notification/notification_bell_button.dart';
import '../widgets/notification/notification_deep_link.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/profile_tab_page.dart';
import '../widgets/proposal/pastor_gate_dialog.dart';
import '../widgets/quiz/quiz_tab_page.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/story_map_panel.dart';
import '../widgets/story_selection_panel.dart';
import '../widgets/v2/home_intro_panel.dart';
import '../widgets/v2/map_hint_overlay.dart';
import '../widgets/v2/region_event_list.dart';
import '../widgets/v2/region_pick_panel.dart';
import '../widgets/v2/timeline_unit_pick_panel.dart';
import 'notification_history_screen.dart';
import 'proposal_board_screen.dart';
import 'proposal_detail_screen.dart';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

part 'story_home_screen_state.dart';
part 'story_home_screen_widgets.dart';

class StoryHomeScreen extends ConsumerStatefulWidget {
  const StoryHomeScreen({super.key, this.initialStep = 1});

  /// 시대 선택 패널의 시작 단계. v2 첫 화면(시대 + 모드 분기)에서 인물 모드를
  /// 고르고 들어오면 `2` 를 넘겨 곧장 인물 선택 단계부터 시작한다.
  final int initialStep;

  @override
  ConsumerState<StoryHomeScreen> createState() => _StoryHomeScreenState();
}
