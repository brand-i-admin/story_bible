import 'package:supabase_flutter/supabase_flutter.dart';

/// 이야기 제안(event_proposals) 데이터 계층.
///
/// - 사역자(user_profiles.is_pastor=true)가 제안을 제출 → DB의
///   `submit_event_proposal` RPC 호출 → event_proposals row 생성(status='pending').
/// - 관리자가 `approve_event_proposal`로 승인하면 기존 `insert_event_at_position`
///   이 재사용되어 events 테이블에 published로 INSERT되고, proposal 은
///   `approved` 상태로 업데이트된다.
/// - `reject_event_proposal` / `add_proposal_comment` 도 RPC wrapper.
///
/// 리스트/상세 조회는 Phase 2~5 에서 EventProposal 모델과 함께 추가된다.
class ProposalRepository {
  ProposalRepository(this._client);

  final SupabaseClient _client;

  /// 새 제안 저장. 성공 시 생성된 proposal id(uuid) 반환.
  /// 권한: 호출자가 `is_pastor=true` 여야 한다 (RPC 내부 체크).
  Future<String> submit({
    required String eraId,
    int? afterStoryIndex,
    required String title,
    String? summary,
    List<String> personCodes = const [],
    String? placeName,
    double? lat,
    double? lng,
    int? startYear,
    int? endYear,
    String timePrecision = 'approx',
    List<Map<String, String>> bibleRefs = const [],
    List<String> storyScenes = const [],
    List<List<String>> scenePersons = const [],
  }) async {
    final result = await _client.rpc(
      'submit_event_proposal',
      params: {
        'p_era_id': eraId,
        'p_title': title,
        'p_summary': summary,
        'p_person_codes': personCodes,
        'p_place_name': placeName,
        'p_lat': lat,
        'p_lng': lng,
        'p_start_year': startYear,
        'p_end_year': endYear,
        'p_time_precision': timePrecision,
        'p_bible_refs': bibleRefs,
        'p_story_scenes': storyScenes,
        'p_scene_persons': scenePersons,
        'p_after_story_index': afterStoryIndex,
      },
    );
    return result as String;
  }

  /// 관리자용 승인. 성공 시 생성된 events.id 반환.
  /// [afterStoryIndexOverride] 로 삽입 위치를 재지정할 수 있다.
  Future<String> approve(
    String proposalId, {
    int? afterStoryIndexOverride,
  }) async {
    final result = await _client.rpc(
      'approve_event_proposal',
      params: {
        'p_proposal_id': proposalId,
        'p_after_story_index_override': afterStoryIndexOverride,
      },
    );
    return result as String;
  }

  /// 관리자용 거절. [note] 는 거절 사유(optional).
  Future<void> reject(String proposalId, {String? note}) async {
    await _client.rpc(
      'reject_event_proposal',
      params: {'p_proposal_id': proposalId, 'p_note': note},
    );
  }

  /// 제안에 댓글 작성 (사역자 또는 관리자).
  Future<String> addComment(String proposalId, String body) async {
    final result = await _client.rpc(
      'add_proposal_comment',
      params: {'p_proposal_id': proposalId, 'p_body': body},
    );
    return result as String;
  }
}
