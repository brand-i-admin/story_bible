import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/story_repository.dart';
import 'package:story_bible/data/user_repository.dart';
import 'package:story_bible/models/character.dart';
import 'package:story_bible/models/era.dart';
import 'package:story_bible/models/event_emotion_mark.dart';
import 'package:story_bible/models/story_event.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/story_controller.dart';

part 'story_controller_test_groups.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

const _fallbackEmotionMark = EventEmotionMark(
  eventId: 'fallback',
  emotionKey: 'joy',
  emotionLabel: '기쁨',
  emotionEmoji: '✨',
  note: '',
  updatedAt: null,
);

User _user({required String id}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime(2026).toIso8601String(),
  );
}

Era _era({
  required String id,
  required String code,
  String testament = 'old',
  String name = '테스트',
  int displayOrder = 0,
}) {
  return Era(
    id: id,
    code: code,
    testament: testament,
    name: name,
    displayOrder: displayOrder,
    startYear: null,
    endYear: null,
    mapCenterLat: null,
    mapCenterLng: null,
    mapZoom: null,
  );
}

Character _person({
  required String id,
  required String name,
  int displayOrder = 0,
}) {
  return Character(
    id: id,
    code: id,
    name: name,
    tagline: null,
    description: null,
    avatarUrl: null,
    displayOrder: displayOrder,
  );
}

StoryEvent _event({
  required String id,
  required String eraId,
  required List<String> characterCodes,
  int globalRank = 0,
  int rankInEra = 0,
  int storyIndex = 0,
}) {
  return StoryEvent(
    id: id,
    landmarkId: 'lm_test',
    eraId: eraId,
    title: '사건 $id',
    summary: null,
    storyScenes: const <String>[],
    sceneCharacters: const <List<String>>[],
    startYear: null,
    endYear: null,
    timePrecision: 'approx',
    storyIndex: storyIndex,
    rankInEra: rankInEra,
    globalRank: globalRank,
    placeName: null,
    lat: null,
    lng: null,
    characterCodes: characterCodes,
    bibleRefs: const [],
  );
}
