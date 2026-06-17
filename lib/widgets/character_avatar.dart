import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/character.dart';
import '../state/story_controller.dart';

/// 인물 아바타 (원형, 동그란 테두리 + 그림자).
///
/// ## 하이브리드 로딩 정책 (2026-04~)
/// 1. 로컬 번들: `assets/avatars_thumbs/<code>.png` 가 있으면 바로 사용 (비용 0).
/// 2. Supabase Storage fallback: 로컬에 없으면 `character.avatarStoragePath`
///    (`characters/...` 또는 `proposal-characters/...`) 로 public URL 생성 후
///    `Image.network` 로 로드.
/// 3. 둘 다 실패하면 이름 첫 글자 이니셜 배경.
///
/// 이 정책 덕분에 **앱이 재배포될 때마다 기존 자산은 로컬에 흡수** 되고,
/// 새로 등장한 캐릭터만 일시적으로 네트워크를 탄다. 그 사이에도 썸네일만
/// 받으므로 과금 부담이 낮다.
class CharacterAvatar extends ConsumerWidget {
  const CharacterAvatar({super.key, required this.character, this.size = 32});

  final Character character;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로컬 번들 아바타가 실제로 있는 캐릭터만 assetPath 를 1차로 시도.
    // 그렇지 않으면(승인은 됐으나 아직 번들 sync 전인 신규 캐릭터) storage 가
    // 1차 경로 — placeholder PNG 가 errorBuilder 를 못 트리거하던 버그 방지.
    final hasLocal = character.hasLocalAvatar;
    final assetPath = hasLocal ? character.avatarAssetPath.trim() : '';
    final storagePath = _storagePathFor(character, hasLocal);
    final fallbackText = character.name.trim().isEmpty
        ? '?'
        : character.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF3E7CC), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: _buildHybridImage(
          ref: ref,
          assetPath: assetPath,
          storagePath: storagePath,
          fallbackText: fallbackText,
          fallbackFontSize: fallbackFontSize,
        ),
      ),
    );
  }

  String? _storagePathFor(Character character, bool hasLocal) {
    final explicitPath = character.avatarStoragePath?.trim();
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return explicitPath;
    }
    final code = character.code.trim();
    if (hasLocal && code.isNotEmpty) {
      return '$code.png';
    }
    return null;
  }

  /// 로컬 → 원격 → 이니셜 순서 렌더.
  ///
  /// Flutter `Image.asset` 의 `errorBuilder` 는 asset 이 번들에 없을 때
  /// 불린다. 그 안에서 storage URL 로 `Image.network` 를 다시 시도하고,
  /// 네트워크도 실패하면 최종 이니셜. 로컬 asset 이 번들에 있으면
  /// 네트워크는 절대 안 탄다 (대부분의 경우).
  Widget _buildHybridImage({
    required WidgetRef ref,
    required String assetPath,
    required String? storagePath,
    required String fallbackText,
    required double fallbackFontSize,
  }) {
    final fallback = _Fallback(text: fallbackText, fontSize: fallbackFontSize);

    // Case 1: 로컬 path 도, storage path 도 없는 순수 fallback.
    if (assetPath.isEmpty && (storagePath == null || storagePath.isEmpty)) {
      return fallback;
    }

    String? storageUrl() {
      if (storagePath == null || storagePath.isEmpty) {
        return null;
      }
      return _storageUrlFor(ref, storagePath);
    }

    // Case 2: 로컬 경로가 있으면 그걸 1차로 시도, 실패 시 네트워크 → 실패 시 이니셜.
    // 로컬 thumb 은 canonical 비율(인물 머리가 상단 1/3) 이므로 _squareAvatar
    // 의 height=size*2 위쪽 자르기를 적용한다. 네트워크 fallback 은 proposal
    // 원본 비율이라 단순 정사각 cover.
    if (assetPath.isNotEmpty) {
      return _squareAvatar(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) {
            final fallbackUrl = storageUrl();
            if (fallbackUrl == null) return fallback;
            return _zoomedNetworkAvatar(fallbackUrl, fallback);
          },
        ),
      );
    }

    // Case 3: 로컬 경로 비어있고 storage 만 있음 (승인은 됐지만 아직 로컬 sync 전).
    //
    // proposal 원본 PNG 는 Imagen 4.0 1024×1024, 인물이 화면 정중앙에 그려진다.
    // 그대로 cover 만 쓰면 머리부터 발끝까지 전부 보여 canonical thumb(상체
    // 위주) 과 시각 비율이 맞지 않는다. → topCenter 기준 1.5× 확대해 상반신
    // 위주로 자른다. 부모 ClipOval 이 자연스럽게 외곽을 클립한다.
    final fallbackUrl = storageUrl();
    if (fallbackUrl != null) {
      return _zoomedNetworkAvatar(fallbackUrl, fallback);
    }

    return fallback;
  }

  Widget _zoomedNetworkAvatar(String url, Widget fallback) {
    return ColoredBox(
      color: Colors.white,
      child: Transform.scale(
        scale: 1.5,
        alignment: Alignment.topCenter,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, error, _) {
            debugPrint(
              '[avatar] storage Image.network failed url=$url error=$error',
            );
            return fallback;
          },
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const ColoredBox(color: Color(0xFFE7D2B2));
          },
        ),
      ),
    );
  }

  /// characters 버킷 또는 proposal-characters 버킷에서 public URL 생성.
  /// `storagePath` 는 둘 중 하나의 형식:
  ///   - `characters/{code}.png`  (bucket/path)
  ///   - `proposal-characters/{uid}/{draft}/{code}.png`
  ///   - 또는 과거 호환을 위한 `{code}.png` (bucket 이름 없이) — 이 경우
  ///     characters 버킷으로 간주.
  static String? _storageUrlFor(WidgetRef ref, String storagePath) {
    try {
      final client = ref.read(supabaseClientProvider);
      final SupabaseStorageClient storage = client.storage;
      // 앞의 '/' 로 bucket/path 분리
      final slash = storagePath.indexOf('/');
      if (slash < 0) {
        // bucket 이름 없이 code.png 만 있는 경우 — characters 버킷 기본 가정
        return storage.from('characters').getPublicUrl(storagePath);
      }
      final bucket = storagePath.substring(0, slash);
      final path = storagePath.substring(slash + 1);
      return storage.from(bucket).getPublicUrl(path);
    } catch (_) {
      // Supabase 초기화 전 (예: 테스트) 이면 URL 구성 실패 → 이니셜 대체.
      return null;
    }
  }

  /// 로컬/원격 공통으로 쓰이는 정사각 컨테이너 레이아웃.
  Widget _squareAvatar({required Widget child}) {
    return ColoredBox(
      color: Colors.white,
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        child: SizedBox(width: size, height: size * 2, child: child),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.text, this.fontSize = 11});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFFF3EAD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
