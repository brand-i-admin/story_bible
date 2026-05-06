import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_proposal.dart';
import '../models/proposal_comment.dart';

/// Edge Function `generate-proposal-character` 의 응답 래퍼.
class GeneratedProposalCharacter {
  const GeneratedProposalCharacter({
    required this.storagePath,
    required this.prompt,
    required this.characterCode,
    required this.characterName,
  });
  final String storagePath;
  final String prompt;
  final String characterCode;
  final String characterName;
}

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

  /// 새 이야기 제안 저장 (proposal_type='new'). 성공 시 생성된 proposal id(uuid) 반환.
  /// 권한: 호출자가 `is_pastor=true` 여야 한다 (RPC 내부 체크).
  /// [sceneImagePaths] / [sceneImagePrompts] 는 모든 장면이 생성 완료된 뒤에만
  /// 전달한다 (길이가 storyScenes 와 일치해야 DB 에서 통과).
  /// [quizQuestions] 는 1~3개의 4지선다 퀴즈. 해설까지 필수 (RPC CHECK).
  Future<String> submit({
    required String eraId,
    int? afterStoryIndex,
    required String title,
    String? summary,
    List<String> characterCodes = const [],
    required String landmarkId,
    int? startYear,
    int? endYear,
    String timePrecision = 'approx',
    List<Map<String, String>> bibleRefs = const [],
    List<String> storyScenes = const [],
    List<List<String>> sceneCharacters = const [],
    List<String> sceneImagePaths = const [],
    List<String> sceneImagePrompts = const [],
    List<ProposedCharacter> proposedCharacters = const [],
    List<QuizDraft> quizQuestions = const [],
  }) async {
    final result = await _client.rpc(
      'submit_event_proposal',
      params: {
        'p_era_id': eraId,
        'p_title': title,
        'p_summary': summary,
        'p_character_codes': characterCodes,
        'p_landmark_id': landmarkId,
        'p_start_year': startYear,
        'p_end_year': endYear,
        'p_time_precision': timePrecision,
        'p_bible_refs': bibleRefs,
        'p_story_scenes': storyScenes,
        'p_scene_characters': sceneCharacters,
        'p_scene_image_paths': sceneImagePaths,
        'p_scene_image_prompts': sceneImagePrompts,
        'p_proposed_characters': proposedCharacters
            .map((c) => c.toMap())
            .toList(),
        'p_quiz_questions': quizQuestions.map((q) => q.toMap()).toList(),
        'p_after_story_index': afterStoryIndex,
      },
    );
    return result as String;
  }

  /// 기존 이야기 삭제 제안 (proposal_type='delete').
  ///
  /// `targetEventId` 가 이미 soft-delete 된 이벤트면 서버에서 예외. 동일 대상에
  /// pending 삭제 제안이 이미 존재하면 partial unique index 가 violate 를 던져
  /// `PostgrestException` 이 발생한다.
  Future<String> submitDeleteProposal({
    required String targetEventId,
    required String reason,
  }) async {
    final result = await _client.rpc(
      'submit_delete_proposal',
      params: {'p_target_event_id': targetEventId, 'p_reason': reason},
    );
    return result as String;
  }

  /// 일반 제안 제출 (proposal_type='general').
  ///
  /// `body` 는 본문 텍스트 (필수), `imagePaths` 는 사전에 업로드된
  /// `proposal-general-images/...` Storage 경로 (최대 5장).
  ///
  /// 권한: pastor 또는 admin (RPC 내부 체크).
  Future<String> submitGeneralProposal({
    required String title,
    required String body,
    List<String> imagePaths = const [],
  }) async {
    final result = await _client.rpc(
      'submit_general_proposal',
      params: {'p_title': title, 'p_body': body, 'p_image_paths': imagePaths},
    );
    return result as String;
  }

  /// 일반 제안의 이미지 한 장을 `proposal-general-images` 버킷에 업로드.
  /// 반환은 `bucket/path` 형태의 storage path (다른 path 와 동일한 규칙).
  ///
  /// [draftId] 는 클라이언트에서 만든 임시 식별자. 같은 폴더 안에서 idx 만 다른
  /// 파일로 업로드된다.
  /// [extension] 은 점(`.`) 없이 'png', 'jpg', 'webp' 등.
  Future<String> uploadGeneralProposalImage({
    required String userId,
    required String draftId,
    required int index,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ext = _normalizeImageExtension(extension);
    final path = '$userId/$draftId/$index.$ext';
    await _client.storage
        .from('proposal-general-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForImageExtension(ext),
          ),
        );
    return 'proposal-general-images/$path';
  }

  String _normalizeImageExtension(String ext) {
    final lower = ext.toLowerCase().trim();
    if (lower == 'jpeg') return 'jpg';
    if (lower.isEmpty) return 'png';
    return lower;
  }

  String _contentTypeForImageExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'png':
      default:
        return 'image/png';
    }
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

  /// 새 캐릭터 아바타 한 장 생성 — `generate-proposal-character` Edge Function
  /// 호출. 같은 draftId + characterCode 로 재호출 시 덮어쓰기(재생성).
  Future<GeneratedProposalCharacter> generateProposalCharacter({
    required String prompt,
    required String characterCode,
    required String characterName,
    required String draftId,
  }) async {
    final response = await _client.functions.invoke(
      'generate-proposal-character',
      body: {
        'prompt': prompt,
        'characterCode': characterCode,
        'characterName': characterName,
        'draftId': draftId,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'HTTP ${response.status}';
      throw Exception('캐릭터 생성 실패: $msg');
    }
    final data = response.data;
    if (data is! Map || data['storage_path'] is! String) {
      throw Exception('캐릭터 생성 응답 형식이 올바르지 않습니다');
    }
    return GeneratedProposalCharacter(
      storagePath: data['storage_path'] as String,
      prompt: (data['prompt'] as String?) ?? '',
      characterCode: (data['character_code'] as String?) ?? characterCode,
      characterName: (data['character_name'] as String?) ?? characterName,
    );
  }

  /// `proposal-characters` / `proposal-scenes` / `characters` 등 `bucket/path`
  /// 형태의 storage_path 로 public URL 반환. 모든 세 버킷이 public read 이므로
  /// 같은 로직으로 안전.
  String publicUrlForStoragePath(String bucketPath) {
    final idx = bucketPath.indexOf('/');
    if (idx < 0) return bucketPath;
    final bucket = bucketPath.substring(0, idx);
    final path = bucketPath.substring(idx + 1);
    return _client.storage.from(bucket).getPublicUrl(path);
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

  /// 관리자용 승인 (proposal_type='new' 전용).
  /// 성공 시 생성된 events.id 반환.
  /// [afterStoryIndexOverride] 로 삽입 위치를 재지정할 수 있다.
  /// [characterActiveOverrides] 는 `{ code: bool }` 매핑으로, 승인 다이얼로그
  /// 에서 관리자가 각 등장 인물의 `is_active` 를 어떻게 둘지 결정한 결과.
  /// 키 없는 코드는 RPC 가 기본값(true) 으로 처리.
  Future<String> approve(
    String proposalId, {
    int? afterStoryIndexOverride,
    Map<String, bool> characterActiveOverrides = const {},
  }) async {
    final result = await _client.rpc(
      'approve_event_proposal',
      params: {
        'p_proposal_id': proposalId,
        'p_after_story_index_override': afterStoryIndexOverride,
        'p_character_active_overrides': characterActiveOverrides,
      },
    );
    return result as String;
  }

  /// 관리자용 삭제 제안 승인 (proposal_type='delete' 전용).
  ///
  /// 서버 RPC `approve_delete_proposal` 가:
  ///   1) `events.deleted_at = now()` (soft delete) — events_ordered view 가
  ///      앱 전체에서 자동으로 숨김.
  ///   2) 이 이벤트가 마지막 출연이었던 캐릭터를 `characters.is_active = false`
  ///      로 비활성화 — characters_read_active 정책이 활성 인물만 노출하므로
  ///      앱 캐릭터 목록 fetch 결과에 들어가지 않는다 (로컬 번들에 PNG 가
  ///      남아있어도 사용자에게는 안 보임).
  ///   3) 정리할 storage 경로 묶음(jsonb) 반환:
  ///        - scene_image_paths: 이 이벤트의 장면 이미지 경로
  ///        - inactive_character_avatar_paths: 방금 비활성화된 캐릭터 아바타 경로
  ///
  /// 이 메서드는 그 두 묶음에 대해 **best-effort** 로 Supabase Storage 에서
  /// 파일을 제거한다. 이미 삭제됐거나 권한 문제로 실패해도 무시(앱 동작에는
  /// 영향 없음) — 고아 파일은 향후 cleanup 잡으로 정리 가능.
  ///
  /// **이미 sync 됐다면 정리 불필요한 이유**: `make sync-approved-proposal-assets`
  /// 가 `--delete-source` 로 돌면 proposal-* 원본 파일이 사라지고 path 도
  /// `characters/<code>.png` / 새 bucket 으로 패치된 상태일 수 있다. 이 경우
  /// remove() 가 404 에 가깝게 무반응으로 끝나고, 클라이언트는 그걸 정상으로
  /// 간주한다.
  ///
  /// 반환값: 삭제된 target event_id.
  Future<String> approveDelete(String proposalId) async {
    final result = await _client.rpc(
      'approve_delete_proposal',
      params: {'p_proposal_id': proposalId},
    );

    final map = (result is Map) ? Map<String, dynamic>.from(result) : null;
    if (map == null) {
      // 구 버전 RPC (return uuid) 와의 호환 — 정리는 스킵하고 id 만 반환.
      return result.toString();
    }

    final eventId = map['event_id']?.toString() ?? '';
    final scenePaths =
        (map['scene_image_paths'] as List?)
            ?.map((e) => e.toString())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    // 키 호환: 신 RPC = deleted_character_avatar_paths (hard delete),
    //           구 RPC = inactive_character_avatar_paths (soft delete) — 둘 다 본다.
    final avatarPaths =
        (map['deleted_character_avatar_paths'] as List? ??
                map['inactive_character_avatar_paths'] as List?)
            ?.map((e) => e.toString())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];

    await _bestEffortRemoveStoragePaths([...scenePaths, ...avatarPaths]);
    return eventId;
  }

  /// 'bucket/path' 또는 'path'(이 경우 characters 버킷 가정) 형식의 경로 묶음을
  /// 버킷별로 묶어 한 번에 remove. 어떤 단일 실패도 다른 버킷 정리를 막지 않는다.
  Future<void> _bestEffortRemoveStoragePaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final byBucket = <String, List<String>>{};
    for (final raw in paths) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      final slash = p.indexOf('/');
      final bucket = slash > 0 ? p.substring(0, slash) : 'characters';
      final inner = slash > 0 ? p.substring(slash + 1) : p;
      byBucket.putIfAbsent(bucket, () => <String>[]).add(inner);
    }
    for (final entry in byBucket.entries) {
      try {
        await _client.storage.from(entry.key).remove(entry.value);
      } catch (_) {
        // 무시 — 이미 삭제됐거나 권한이 없거나, 어느 쪽이든 사용자 경험에는 영향 없음.
      }
    }
  }

  /// 일반 제안 승인 (proposal_type='general' 전용). 부가 효과 없이 status 만
  /// 갱신. 이미지 정리 / row 정리는 의도적으로 하지 않는다 (요구사항).
  Future<void> approveGeneral(String proposalId) async {
    await _client.rpc(
      'approve_general_proposal',
      params: {'p_proposal_id': proposalId},
    );
  }

  /// 일반 제안 거절 (proposal_type='general' 전용). status='rejected' + 사유 저장만.
  Future<void> rejectGeneral(String proposalId, {String? note}) async {
    await _client.rpc(
      'reject_general_proposal',
      params: {'p_proposal_id': proposalId, 'p_note': note},
    );
  }

  /// 관리자용 거절. [note] 는 거절 사유(optional).
  ///
  /// 서버는 `position_invalidated_at IS NOT NULL` 인 제안은 거부한다 — 제안자가
  /// 위치를 다시 결정한 뒤에야 admin 이 다시 reject 가능.
  ///
  /// 거절 시 row 는 history 보존을 위해 남기지만 **proposal-* 버킷의 장면/
  /// 캐릭터 이미지는 더 이상 쓰이지 않아** 정리한다. 서버 RPC 가 정리할 경로
  /// 묶음을 jsonb 로 돌려주고, 클라이언트가 best-effort 로 storage 에서 제거.
  Future<void> reject(String proposalId, {String? note}) async {
    final result = await _client.rpc(
      'reject_event_proposal',
      params: {'p_proposal_id': proposalId, 'p_note': note},
    );
    if (result is Map) {
      final map = Map<String, dynamic>.from(result);
      final scenePaths =
          (map['scene_image_paths'] as List?)
              ?.map((e) => e.toString())
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      final charPaths =
          (map['rejected_character_storage_paths'] as List?)
              ?.map((e) => e.toString())
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      await _bestEffortRemoveStoragePaths([...scenePaths, ...charPaths]);
    }
  }

  /// 제안자 본인이 무효화된(position_invalidated_at set) 제안의 위치 + 연도를
  /// 다시 결정. 성공 시 `position_invalidated_at` 이 NULL 로 복구되어 admin 이
  /// 다시 approve/reject 할 수 있게 된다.
  ///
  /// [afterStoryIndex] : 새 위치 (era 안의 0..N — 0 은 맨 앞)
  /// [startYear]/[endYear] : 새 연도 범위. 둘 다 null 이면 변경 없음. RPC 가
  ///   prev/next 이벤트 연도와 정합 검증 (`prev.end_year <= start_year <=
  ///   end_year <= next.start_year`).
  Future<void> revisePosition({
    required String proposalId,
    required int afterStoryIndex,
    int? startYear,
    int? endYear,
    String? landmarkId,
  }) async {
    await _client.rpc(
      'revise_proposal_position',
      params: {
        'p_proposal_id': proposalId,
        'p_after_story_index': afterStoryIndex,
        'p_start_year': startYear,
        'p_end_year': endYear,
        'p_landmark_id': landmarkId,
      },
    );
  }

  /// 제안 삭제.
  ///
  /// RLS 정책 `event_proposals_delete_own_unapproved` 가 실제 권한을 강제:
  ///   - admin 은 상태 무관 언제든 삭제 가능
  ///   - proposer 본인은 status != 'approved' 일 때만 가능
  ///     (pending 또는 rejected 만 본인 삭제 허용; approved 는 불가)
  ///
  /// 권한 없이 호출하면 Supabase 가 단순히 "0 rows matched" 로 조용히
  /// 끝내므로(RLS 의 기본 동작), 호출자가 UI 에서 버튼을 적절히 비활성화
  /// 해야 사용자가 혼란 없이 경험한다 (proposal_detail_screen 참조).
  Future<void> deleteProposal(String proposalId) async {
    await _client.from('event_proposals').delete().eq('id', proposalId);
  }

  /// 제안 row + Storage 정리 일괄 처리.
  ///
  /// 1) `proposal-scenes` 의 모든 장면 이미지 삭제 (`scene_image_paths`)
  /// 2) `proposed_characters` 의 storage_path 삭제. 단, 같은 code 가
  ///    `characters` 테이블에 이미 published 상태(=관리자 또는 다른 경로로
  ///    이미 등록된 인물) 이면 **삭제하지 않는다** — 다른 이야기에서 재사용 중일
  ///    수 있기 때문.
  /// 3) DB row 삭제 (RLS 가 권한 검증).
  ///
  /// Storage 삭제 실패는 무시 (DB row 삭제까지는 진행) — 고아 파일이 남아도
  /// 보드 동작에는 영향 없음. 향후 cleanup job 으로 정리.
  Future<void> deleteProposalWithAssets(EventProposal proposal) async {
    // 1) 장면 이미지 삭제 — bucket 별로 묶어서 한 번에 remove.
    final scenesByBucket = <String, List<String>>{};
    for (final p in proposal.sceneImagePaths) {
      final slash = p.indexOf('/');
      if (slash <= 0) continue;
      final bucket = p.substring(0, slash);
      final path = p.substring(slash + 1);
      scenesByBucket.putIfAbsent(bucket, () => []).add(path);
    }
    for (final entry in scenesByBucket.entries) {
      try {
        await _client.storage.from(entry.key).remove(entry.value);
      } catch (_) {
        // 고아 파일 — 무시
      }
    }

    // 2) 신규 캐릭터 아바타 삭제. 단 characters 테이블에 같은 code 가 이미
    //    있으면 (published) 다른 이야기에서 재사용 중일 수 있어 보존.
    if (proposal.proposedCharacters.isNotEmpty) {
      final codes = proposal.proposedCharacters.map((c) => c.code).toList();
      List<String> publishedCodes = const [];
      try {
        final rows = await _client
            .from('characters')
            .select('code')
            .inFilter('code', codes);
        publishedCodes = (rows as List)
            .map((r) => (r as Map)['code'] as String)
            .toList();
      } catch (_) {
        // 조회 실패 시 보수적으로 모두 보존 (삭제 안 함).
        publishedCodes = codes;
      }
      final published = publishedCodes.toSet();
      final charsByBucket = <String, List<String>>{};
      for (final c in proposal.proposedCharacters) {
        if (published.contains(c.code)) continue; // 이미 등록된 인물 — 보존
        final p = c.storagePath;
        final slash = p.indexOf('/');
        if (slash <= 0) continue;
        final bucket = p.substring(0, slash);
        final path = p.substring(slash + 1);
        charsByBucket.putIfAbsent(bucket, () => []).add(path);
      }
      for (final entry in charsByBucket.entries) {
        try {
          await _client.storage.from(entry.key).remove(entry.value);
        } catch (_) {}
      }
    }

    // 3) DB row 삭제 (RLS 가 status != 'approved' + proposer 본인 또는 admin 검증).
    await _client.from('event_proposals').delete().eq('id', proposal.id);
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
    dynamic query = _client
        .from('event_proposals')
        .select('*, landmark:landmarks(id, name, lat, lng, kind)');
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
        .select('*, landmark:landmarks(id, name, lat, lng, kind)')
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
  /// proposer 이면서 status=pending 이어야 통과. `proposal_type='new'` 제안만
  /// 이 메서드로 수정한다 ('delete' 는 취소 후 재제출 권장).
  Future<void> updateProposal({
    required String proposalId,
    required String eraId,
    required String title,
    String? summary,
    List<String> characterCodes = const [],
    required String landmarkId,
    int? startYear,
    int? endYear,
    String timePrecision = 'approx',
    List<Map<String, dynamic>> bibleRefs = const [],
    List<String> storyScenes = const [],
    List<List<String>> sceneCharacters = const [],
    List<String> sceneImagePaths = const [],
    List<String> sceneImagePrompts = const [],
    List<ProposedCharacter> proposedCharacters = const [],
    List<QuizDraft> quizQuestions = const [],
    int? afterStoryIndex,
  }) async {
    await _client
        .from('event_proposals')
        .update({
          'era_id': eraId,
          'title': title,
          'summary': summary,
          'character_codes': characterCodes,
          'landmark_id': landmarkId,
          'start_year': startYear,
          'end_year': endYear,
          'time_precision': timePrecision,
          'bible_refs': bibleRefs,
          'story_scenes': storyScenes,
          'scene_characters': sceneCharacters,
          'scene_image_paths': sceneImagePaths,
          'scene_image_prompts': sceneImagePrompts,
          'proposed_characters': proposedCharacters
              .map((c) => c.toMap())
              .toList(),
          'quiz_questions': quizQuestions.map((q) => q.toMap()).toList(),
          'after_story_index': afterStoryIndex,
        })
        .eq('id', proposalId);
  }
}
