import 'dart:convert';

/// event_proposals row — 사역자가 제출한 이야기 초안.
///
/// 상태(status) 는 서버 CHECK 제약에 따라 'pending' | 'approved' | 'rejected'
/// 셋 중 하나. 승인 시 `approvedEventId` 에 events 테이블 PK 가 세팅된다.
class EventProposal {
  const EventProposal({
    required this.id,
    required this.proposerUserId,
    required this.eraId,
    required this.title,
    required this.summary,
    required this.characterCodes,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.startYear,
    required this.endYear,
    required this.timePrecision,
    required this.bibleRefs,
    required this.storyScenes,
    required this.sceneCharacters,
    required this.sceneImagePaths,
    required this.sceneImagePrompts,
    required this.proposedCharacters,
    required this.afterStoryIndex,
    required this.status,
    required this.reviewedByUserId,
    required this.reviewedAt,
    required this.reviewNote,
    required this.approvedEventId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String proposerUserId;
  final String eraId;
  final String title;
  final String? summary;
  final List<String> characterCodes;
  final String? placeName;
  final double? lat;
  final double? lng;
  final int? startYear;
  final int? endYear;
  final String timePrecision;
  final List<Map<String, dynamic>> bibleRefs; // [{book, from, to}, ...]
  final List<String> storyScenes;
  final List<List<String>> sceneCharacters;

  /// 장면별 생성된 이미지의 Supabase Storage 경로. storyScenes 와 동일한 길이여야
  /// 함. `proposal-scenes/{uid}/{draft}/scene_{idx}.png` 형태. 비어 있으면 아직
  /// 이미지 생성 전 (pastor 가 작성 중).
  final List<String> sceneImagePaths;

  /// 장면 이미지 생성 시 Vertex 에 실제 보낸 prompt (참조/재생성용 스냅샷).
  /// storyScenes 와 동일한 길이.
  final List<String> sceneImagePrompts;

  /// 이 제안에서 새로 만든 캐릭터 메타 + Storage 경로 리스트.
  /// 각 요소는 [ProposedCharacter]. 기존 characters 에 없는 인물만 여기에 담김.
  /// 승인 시 characters 테이블에 upsert 된다.
  final List<ProposedCharacter> proposedCharacters;

  final int? afterStoryIndex;
  final String status; // pending / approved / rejected
  final String? reviewedByUserId;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? approvedEventId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory EventProposal.fromMap(Map<String, dynamic> row) {
    return EventProposal(
      id: row['id'] as String,
      proposerUserId: row['proposer_user_id'] as String,
      eraId: row['era_id'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String?,
      characterCodes: _asStringList(row['character_codes']),
      placeName: row['place_name'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      startYear: (row['start_year'] as num?)?.toInt(),
      endYear: (row['end_year'] as num?)?.toInt(),
      timePrecision: (row['time_precision'] as String?) ?? 'approx',
      bibleRefs: _asMapList(row['bible_refs']),
      storyScenes: _asStringList(row['story_scenes']),
      sceneCharacters: _asNestedStringList(row['scene_characters']),
      sceneImagePaths: _asStringList(row['scene_image_paths']),
      sceneImagePrompts: _asStringList(row['scene_image_prompts']),
      proposedCharacters: _asProposedCharacters(row['proposed_characters']),
      afterStoryIndex: (row['after_story_index'] as num?)?.toInt(),
      status: (row['status'] as String?) ?? 'pending',
      reviewedByUserId: row['reviewed_by_user_id'] as String?,
      reviewedAt: _parseDate(row['reviewed_at']),
      reviewNote: row['review_note'] as String?,
      approvedEventId: row['approved_event_id'] as String?,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  static List<String> _asStringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    if (raw is String && raw.isNotEmpty) {
      // JSONB가 문자열로 넘어온 경우
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    }
    return const [];
  }

  static List<List<String>> _asNestedStringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map<List<String>>(
            (inner) =>
                inner is List ? inner.whereType<String>().toList() : const [],
          )
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map<List<String>>(
              (inner) =>
                  inner is List ? inner.whereType<String>().toList() : const [],
            )
            .toList();
      }
    }
    return const [];
  }

  static List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  static List<ProposedCharacter> _asProposedCharacters(dynamic raw) {
    final list = _asMapList(raw);
    return list.map(ProposedCharacter.fromMap).toList(growable: false);
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

/// `event_proposals.proposed_characters` jsonb 원소.
///
/// 제안 작성자가 기존 characters 테이블에 없는 신규 인물을 만들 때 사용된다.
/// - [code]: 소문자/숫자/언더스코어만 (Edge Function 이 sanitize)
/// - [name]: 표시용 이름 (한글)
/// - [prompt]: Vertex 에 보낸 최종 prompt 스냅샷 (common style 포함)
/// - [storagePath]: `proposal-characters/{uid}/{draft}/{code}.png`
class ProposedCharacter {
  const ProposedCharacter({
    required this.code,
    required this.name,
    required this.prompt,
    required this.storagePath,
  });

  final String code;
  final String name;
  final String prompt;
  final String storagePath;

  Map<String, dynamic> toMap() => {
    'code': code,
    'name': name,
    'prompt': prompt,
    'storage_path': storagePath,
  };

  factory ProposedCharacter.fromMap(Map<String, dynamic> m) {
    return ProposedCharacter(
      code: (m['code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      prompt: (m['prompt'] as String?) ?? '',
      storagePath: (m['storage_path'] as String?) ?? '',
    );
  }
}
