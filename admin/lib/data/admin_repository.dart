import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/era.dart';

/// Supabase 와 직접 통신하는 어드민 리포지토리.
/// 관리자 전용 이야기 등록 파이프라인.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<Era>> fetchEras() async {
    final rows = await _client
        .from('eras')
        .select('id, code, name, display_order')
        .order('display_order', ascending: true);
    return rows.map<Era>((row) => Era.fromMap(row)).toList();
  }

  /// era 안에서 이미 published 된 이야기들의 (story_index, title) 목록.
  /// "어떤 이야기 다음에 끼울까?" 폼에서 사용한다.
  Future<List<({int storyIndex, String title})>> fetchPublishedSlots(
    String eraId,
  ) async {
    final rows = await _client
        .from('events')
        .select('story_index, title')
        .eq('era_id', eraId)
        .eq('status', 'published')
        .order('story_index', ascending: true);
    return rows
        .map<({int storyIndex, String title})>(
          (row) => (
            storyIndex: (row['story_index'] as num).toInt(),
            title: row['title'] as String,
          ),
        )
        .toList();
  }

  /// `insert_event_at_position` RPC 호출 — story_index 시프트 + INSERT 를
  /// 트랜잭션 안에서 처리. status 는 RPC 내부에서 'published' 로 강제된다.
  Future<String> submitEvent({
    required String eraCode,
    required int? afterStoryIndex,
    required String title,
    required String summary,
    required List<String> storyScenes,
    required List<List<String>> scenePersons,
    required List<String> personCodes,
    required List<Map<String, String>> bibleRefs,
    required int? startYear,
    required int? endYear,
    required String timePrecision,
    required String placeName,
    required double? lat,
    required double? lng,
  }) async {
    final result = await _client.rpc(
      'insert_event_at_position',
      params: {
        'p_era_code': eraCode,
        'p_after_story_index': afterStoryIndex,
        'p_title': title,
        'p_summary': summary,
        'p_story_scenes': storyScenes,
        'p_scene_persons': scenePersons,
        'p_person_codes': personCodes,
        'p_bible_refs': bibleRefs,
        'p_start_year': startYear,
        'p_end_year': endYear,
        'p_time_precision': timePrecision,
        'p_place_name': placeName,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    return result as String;
  }

  /// 인물 노출 토글.
  Future<void> setPersonActive(String code, bool active) async {
    await _client
        .from('persons')
        .update({'is_active': active})
        .eq('code', code);
  }

  /// 어드민이 등록 폼에서 자동완성용으로 인물 코드 리스트를 가져온다.
  Future<List<({String code, String name, bool isActive})>>
  fetchPersons() async {
    final rows = await _client
        .from('persons')
        .select('code, name, is_active')
        .order('code', ascending: true);
    return rows
        .map<({String code, String name, bool isActive})>(
          (row) => (
            code: row['code'] as String,
            name: row['name'] as String,
            isActive: row['is_active'] as bool,
          ),
        )
        .toList();
  }
}
