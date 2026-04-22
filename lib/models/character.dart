class Character {
  const Character({
    required this.id,
    required this.code,
    required this.name,
    required this.tagline,
    required this.description,
    required this.avatarUrl,
    required this.displayOrder,
  });

  final String id;
  final String code;
  final String name;
  final String? tagline;
  final String? description;
  final String? avatarUrl;
  final int displayOrder;

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
