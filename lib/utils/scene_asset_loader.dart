import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/story_event.dart';

/// `assets/story_images_thumbs/` 하위의 4장면 이미지를 이벤트 단위로 조회한다.
///
/// 이벤트 제목/코드를 기반으로 디렉토리를 찾고, 장면 파일(`scene_1.png` ~
/// `scene_4.png`)을 번호순으로 정렬해 반환. 매니페스트와 개별 결과를 모두
/// 인메모리에 캐싱해서 반복 호출을 빠르게 처리한다.
class SceneAssetLoader {
  SceneAssetLoader();

  static final RegExp _sceneFilenamePattern = RegExp(
    r'/scene_(\d+)\.(?:png|jpe?g|webp)$',
    caseSensitive: false,
  );
  static final RegExp _sceneTitleNumberPattern = RegExp(r'^\s*(\d{1,4})\b');
  static final RegExp _sceneInvalidDirChars = RegExp(r'[\\/:*?"<>|]+');
  static final RegExp _sceneWhitespacePattern = RegExp(r'\s+');
  static final RegExp _sceneLooseNormalizePattern = RegExp(
    r"[\s_\-:·,./\\(){}\[\]']+",
  );

  List<String>? _assetManifestCache;
  final Map<String, List<String>> _sceneAssetsCache = <String, List<String>>{};

  Future<List<String>> loadAssetManifest() async {
    // 정상 캐시(비어있지 않음)만 재사용. 빈 결과(에러로 인한 일시적 실패)는
    // 캐시하지 않아 dev server 가 복구되면 다음 호출에서 재시도되도록 한다.
    final cached = _assetManifestCache;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetKeys = manifest.listAssets();
      if (assetKeys.isNotEmpty) {
        _assetManifestCache = assetKeys;
        return assetKeys;
      }
    } catch (_) {
      // Fall through to JSON manifest for older/alternate environments.
    }

    try {
      final rawManifest = await rootBundle.loadString('AssetManifest.json');
      final decoded = json.decode(rawManifest);
      if (decoded is Map<String, dynamic>) {
        final assetKeys = decoded.keys.toList(growable: false);
        if (assetKeys.isNotEmpty) {
          _assetManifestCache = assetKeys;
          return assetKeys;
        }
      }
    } catch (_) {
      // Return empty manifest when assets are unavailable in current build.
    }
    // 실패 시: 캐시 없이 빈 배열 반환. 다음 호출 때 다시 시도.
    return const <String>[];
  }

  @visibleForTesting
  String sceneDirectoryNameForTitle(String title) {
    final replaced = title.replaceAll(_sceneInvalidDirChars, '_').trim();
    final trimmedDots = replaced.replaceAll(RegExp(r'^\.+|\.+$'), '');
    final collapsed = trimmedDots
        .replaceAll(_sceneWhitespacePattern, ' ')
        .trim();
    return collapsed.isNotEmpty ? collapsed : 'untitled_event';
  }

  @visibleForTesting
  String normalizeSceneLookupKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(_sceneLooseNormalizePattern, '')
        .trim();
  }

  @visibleForTesting
  String stripSceneDirectoryPrefix(String directoryName) {
    return directoryName.replaceFirst(RegExp(r'^\d+\s*'), '').trim();
  }

  @visibleForTesting
  String? scenePrefixForTitle(String title) {
    final match = _sceneTitleNumberPattern.firstMatch(title.trim());
    final digits = match?.group(1);
    if (digits == null || digits.isEmpty) {
      return null;
    }
    final numeric = int.tryParse(digits);
    if (numeric == null) {
      return null;
    }
    return numeric.toString().padLeft(3, '0');
  }

  /// 이벤트에 해당하는 장면 이미지 경로/URL 목록을 반환.
  ///
  /// ## 하이브리드 로딩 순서
  /// 1. `assets/story_images_thumbs/<dir>/scene_N.png` 로컬 번들 — 있으면 이것만 반환.
  /// 2. 번들에 없고 [event.sceneImagePaths] 가 비어있지 않으면 Supabase Storage
  ///    public URL 로 변환해 반환 (`Image.network` 가 로드).
  /// 3. 둘 다 없으면 빈 리스트 — UI 는 이미지 row 를 그냥 숨긴다.
  ///
  /// 호출자에서 `path.startsWith('http')` 여부로 `Image.asset` vs
  /// `Image.network` 를 분기할 수 있도록 반환 문자열의 규약을 유지한다.
  Future<List<String>> loadForEvent(
    StoryEvent event, {
    String Function(String storagePath)? publicUrlFor,
  }) async {
    final localAssets = await loadForTitle(title: event.title);
    if (localAssets.isNotEmpty) return localAssets;

    final storagePaths = event.sceneImagePaths
        .where((p) => p.isNotEmpty)
        .toList();
    if (storagePaths.isEmpty || publicUrlFor == null) {
      return const [];
    }
    return storagePaths.map(publicUrlFor).toList(growable: false);
  }

  Future<List<String>> loadForTitle({required String title}) async {
    final dirName = sceneDirectoryNameForTitle(title);
    final cached = _sceneAssetsCache[dirName];
    if (cached != null) {
      return cached;
    }

    final manifest = await loadAssetManifest();
    const sceneRoot = 'assets/story_images_thumbs/';
    final allScenePaths = manifest
        .where(
          (path) =>
              path.startsWith(sceneRoot) &&
              _sceneFilenamePattern.hasMatch(path),
        )
        .toList(growable: false);

    final knownDirs = <String>{};
    for (final path in allScenePaths) {
      final relative = path.substring(sceneRoot.length);
      final slashIndex = relative.indexOf('/');
      if (slashIndex <= 0) {
        continue;
      }
      knownDirs.add(relative.substring(0, slashIndex));
    }

    var chosenDir = dirName;
    final directPrefix = '$sceneRoot$chosenDir/';
    final hasDirect = allScenePaths.any(
      (path) => path.startsWith(directPrefix),
    );
    if (!hasDirect) {
      final titlePrefix = scenePrefixForTitle(title);
      if (titlePrefix != null) {
        final titleMatchedDir =
            knownDirs
                .where((dir) => dir.startsWith('$titlePrefix '))
                .toList(growable: false)
              ..sort((a, b) => a.length.compareTo(b.length));
        if (titleMatchedDir.isNotEmpty) {
          chosenDir = titleMatchedDir.first;
        }
      }
    }

    final chosenPrefixAfterTitle = '$sceneRoot$chosenDir/';
    final hasTitleMatched = allScenePaths.any(
      (path) => path.startsWith(chosenPrefixAfterTitle),
    );
    if (!hasTitleMatched) {
      final titleKey = normalizeSceneLookupKey(title);
      final dirNameKey = normalizeSceneLookupKey(dirName);
      final fallbackCandidates =
          knownDirs
              .map((dir) {
                final rawKey = normalizeSceneLookupKey(dir);
                final strippedKey = normalizeSceneLookupKey(
                  stripSceneDirectoryPrefix(dir),
                );
                var score = -1;
                if (rawKey == titleKey || rawKey == dirNameKey) {
                  score = 0;
                } else if (strippedKey == titleKey ||
                    strippedKey == dirNameKey) {
                  score = 1;
                } else if (strippedKey.endsWith(titleKey) ||
                    strippedKey.endsWith(dirNameKey)) {
                  score = 2;
                } else if (strippedKey.contains(titleKey) ||
                    strippedKey.contains(dirNameKey) ||
                    titleKey.contains(strippedKey) ||
                    dirNameKey.contains(strippedKey)) {
                  score = 3;
                }
                return (dir: dir, score: score);
              })
              .where((candidate) => candidate.score >= 0)
              .toList(growable: false)
            ..sort((a, b) {
              final byScore = a.score.compareTo(b.score);
              if (byScore != 0) {
                return byScore;
              }
              return a.dir.length.compareTo(b.dir.length);
            });
      if (fallbackCandidates.isNotEmpty) {
        chosenDir = fallbackCandidates.first.dir;
      }
    }

    final chosenPrefix = '$sceneRoot$chosenDir/';
    final sceneAssets =
        allScenePaths
            .where((path) => path.startsWith(chosenPrefix))
            .toList(growable: false)
          ..sort((a, b) {
            final aMatch = _sceneFilenamePattern.firstMatch(a);
            final bMatch = _sceneFilenamePattern.firstMatch(b);
            final aIndex = int.tryParse(aMatch?.group(1) ?? '') ?? 0;
            final bIndex = int.tryParse(bMatch?.group(1) ?? '') ?? 0;
            return aIndex.compareTo(bIndex);
          });

    _sceneAssetsCache[dirName] = sceneAssets;
    return sceneAssets;
  }
}
