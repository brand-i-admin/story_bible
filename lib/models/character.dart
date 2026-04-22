/// 성경 인물 캐릭터 (이전 `Person` 모델의 후속).
///
/// ## 아바타 경로 하이브리드 로딩 정책
/// 캐릭터 이미지는 "로컬 번들 먼저 → Supabase Storage fallback" 원칙으로
/// 로드된다. 그래서 두 경로를 동시에 보관한다:
///
/// - [avatarUrl]: 로컬 번들 경로 (`assets/avatars/<code>.png`). `Image.asset`
///   으로 바로 로드. **대부분의 사용자는 이 경로에서 로드** → Supabase 비용
///   0.
/// - [avatarStoragePath]: Supabase Storage 버킷 경로 (`characters/<code>.png`
///   또는 `proposal-characters/<uid>/<draft>/<code>.png`). 로컬에 파일이
///   없을 때 `Image.network` 로 fallback. 앱 재빌드 + 배포 후엔 이 경로가
///   로컬로 흡수되어 더 이상 네트워크 히트 없음.
///
/// 이 로딩 전략은 `lib/widgets/character_avatar.dart` 의 `CharacterAvatar`
/// 위젯에 캡슐화되어 있다.
class Character {
  const Character({
    required this.id,
    required this.code,
    required this.name,
    required this.tagline,
    required this.description,
    required this.avatarUrl,
    required this.displayOrder,
    // Nullable + optional on purpose: existing call sites don't need to
    // pass it yet (Supabase Storage fallback is a hybrid layer added in
    // 2026-04 and is absent for locally-bundled canonical cast).
    this.avatarStoragePath,
  });

  final String id;
  final String code;
  final String name;
  final String? tagline;
  final String? description;

  /// 로컬 번들 경로 (`assets/avatars/<code>.png`). null 이면 로컬 번들에
  /// 이 인물 아바타가 없다는 뜻 — `avatarStoragePath` 만으로 로드 시도.
  final String? avatarUrl;

  /// Supabase Storage 경로 (`<bucket>/<path>`). null 이면 storage 에도
  /// 없음 → 로컬도 없으면 최종적으로 initial fallback (텍스트 이니셜).
  final String? avatarStoragePath;

  final int displayOrder;

  /// 로컬 번들 런타임 썸네일 경로. `avatars` → `avatars_thumbs` 로 매핑해
  /// 저해상도 버전을 우선 사용 (앱 런타임에는 썸네일이면 충분).
  ///
  /// [avatarUrl] 이 비어있거나 `assets/avatars/` 로 시작하지 않으면
  /// placeholder 반환. 하이브리드 로딩 관점에서는 이 값은 **로컬 자산이
  /// 있다고 가정**한 경로. 실제 번들에 없을 수 있으므로 `AssetManifest` 로
  /// 검증한 뒤 storage 로 fallback 하는 건 `CharacterAvatar` 위젯 쪽 책임.
  String get avatarAssetPath {
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return 'assets/avatars_thumbs/_placeholder.png';
    }
    final trimmed = avatarUrl!.trim();
    if (trimmed.startsWith('assets/avatars/')) {
      return trimmed.replaceFirst('assets/avatars/', 'assets/avatars_thumbs/');
    }
    return trimmed;
  }
}
