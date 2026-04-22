import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_proposal.dart';
import '../models/proposal_comment.dart';

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
  /// [sceneImagePaths] / [sceneImagePrompts] 는 모든 장면이 생성 완료된 뒤에만
  /// 전달한다 (길이가 storyScenes 와 일치해야 DB 에서 통과).
  Future<String> submit({
    required String eraId,
    int? afterStoryIndex,
    required String title,
    String? summary,
    List<String> characterCodes = const [],
    String? placeName,
    double? lat,
    double? lng,
    int? startYear,
    int? endYear,
    String timePrecision = 'approx',
    List<Map<String, String>> bibleRefs = const [],
    List<String> storyScenes = const [],
    List<List<String>> sceneCharacters = const [],
    List<String> sceneImagePaths = const [],
    List<String> sceneImagePrompts = const [],
  }) async {
    final result = await _client.rpc(
      'submit_event_proposal',
      params: {
        'p_era_id': eraId,
        'p_title': title,
        'p_summary': summary,
        'p_character_codes': characterCodes,
        'p_place_name': placeName,
        'p_lat': lat,
        'p_lng': lng,
        'p_start_year': startYear,
        'p_end_year': endYear,
        'p_time_precision': timePrecision,
        'p_bible_refs': bibleRefs,
        'p_story_scenes': storyScenes,
        'p_scene_characters': sceneCharacters,
        'p_scene_image_paths': sceneImagePaths,
        'p_scene_image_prompts': sceneImagePrompts,
        'p_after_story_index': afterStoryIndex,
      },
    );
    return result as String;
  }

  /// 장면 한 장을 생성하도록 Edge Function 을 호출.
  ///
  /// 반환: `(storagePath, prompt)` — storagePath 는 `proposal-scenes/...` 로
  /// 시작하는 경로, prompt 는 Vertex 에 실제 보낸 instruction 전문.
  /// 실패 시 [Exception] 을 던진다 (UI 에서 스낵바로 노출).
  Future<({String storagePath, String prompt})> generateProposalScene({
    required String sceneText,
    required List<String> characterCodes,
    required String draftId,
    required int sceneIndex,
    String? eventTitle,
    String? placeName,
  }) async {
    final response = await _client.functions.invoke(
      'generate-proposal-scene',
      body: {
        'sceneText': sceneText,
        'characterCodes': characterCodes,
        'draftId': draftId,
        'sceneIndex': sceneIndex,
        if (eventTitle != null) 'eventTitle': eventTitle,
        if (placeName != null) 'placeName': placeName,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'HTTP ${response.status}';
      throw Exception('이미지 생성 실패: $msg');
    }
    final data = response.data;
    if (data is! Map || data['storage_path'] is! String) {
      throw Exception('이미지 생성 응답 형식이 올바르지 않습니다');
    }
    return (
      storagePath: data['storage_path'] as String,
      prompt: (data['prompt'] as String?) ?? '',
    );
  }

  /// `proposal-scenes` 버킷의 storage path 로 public URL 을 만든다.
  /// (`storage_path` 는 `proposal-scenes/{uid}/{draft}/scene_{idx}.png` 형식)
  String publicUrlForProposalScene(String storagePath) {
    // bucket 이름 + 내부 경로 분리.
    final idx = storagePath.indexOf('/');
    if (idx < 0) return storagePath;
    final bucket = storagePath.substring(0, idx);
    final path = storagePath.substring(idx + 1);
    return _client.storage.from(bucket).getPublicUrl(path);
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

  /// 제안 목록 조회.
  ///
  /// [status] 필터: `pending` | `approved` | `rejected` | null(전체).
  /// [proposerUserId] 가 주어지면 본인 제안만.
  /// RLS: pastor/admin 만 읽을 수 있다.
  Future<List<EventProposal>> fetchProposals({
    String? status,
    String? proposerUserId,
  }) async {
    dynamic query = _client.from('event_proposals').select();
    if (status != null) {
      query = query.eq('status', status);
    }
    if (proposerUserId != null) {
      query = query.eq('proposer_user_id', proposerUserId);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map<EventProposal>(
          (row) => EventProposal.fromMap(row as Map<String, dynamic>),
        )
        .toList();
  }

  /// 제안 단건 조회 (상세 화면 전용).
  Future<EventProposal> fetchProposal(String proposalId) async {
    final row = await _client
        .from('event_proposals')
        .select()
        .eq('id', proposalId)
        .single();
    return EventProposal.fromMap(row);
  }

  /// 제안에 달린 댓글 목록 (작성 순).
  Future<List<ProposalComment>> fetchComments(String proposalId) async {
    final rows = await _client
        .from('event_proposal_comments')
        .select()
        .eq('proposal_id', proposalId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map<ProposalComment>(
          (row) => ProposalComment.fromMap(row as Map<String, dynamic>),
        )
        .toList();
  }

  /// 본인 pending 제안 수정. RLS `event_proposals_update` 정책에 의해
  /// proposer 이면서 status=pending 이어야 통과.
  Future<void> updateProposal({
    required String proposalId,
    required String eraId,
    required String title,
    String? summary,
    List<String> characterCodes = const [],
    String? placeName,
    double? lat,
    double? lng,
    int? startYear,
    int? endYear,
    String timePrecision = 'approx',
    List<Map<String, dynamic>> bibleRefs = const [],
    List<String> storyScenes = const [],
    List<List<String>> sceneCharacters = const [],
    List<String> sceneImagePaths = const [],
    List<String> sceneImagePrompts = const [],
    int? afterStoryIndex,
  }) async {
    await _client
        .from('event_proposals')
        .update({
          'era_id': eraId,
          'title': title,
          'summary': summary,
          'character_codes': characterCodes,
          'place_name': placeName,
          'lat': lat,
          'lng': lng,
          'start_year': startYear,
          'end_year': endYear,
          'time_precision': timePrecision,
          'bible_refs': bibleRefs,
          'story_scenes': storyScenes,
          'scene_characters': sceneCharacters,
          'scene_image_paths': sceneImagePaths,
          'scene_image_prompts': sceneImagePrompts,
          'after_story_index': afterStoryIndex,
        })
        .eq('id', proposalId);
  }
}
