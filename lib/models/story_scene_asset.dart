class StorySceneAsset {
  const StorySceneAsset({
    required this.sceneIndex,
    required this.originalPath,
    required this.thumbnailPath,
    required this.status,
    required this.metadata,
  });

  final int sceneIndex;
  final String? originalPath;
  final String? thumbnailPath;
  final String status;
  final Map<String, dynamic> metadata;

  String get displayPath {
    final thumb = thumbnailPath?.trim() ?? '';
    if (thumb.isNotEmpty) {
      return thumb;
    }
    return originalPath?.trim() ?? '';
  }

  factory StorySceneAsset.legacy({
    required int sceneIndex,
    required String assetPath,
  }) {
    return StorySceneAsset(
      sceneIndex: sceneIndex,
      originalPath: null,
      thumbnailPath: assetPath,
      status: 'legacy_asset',
      metadata: const {},
    );
  }
}
