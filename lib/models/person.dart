class Person {
  const Person({
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
      return 'assets/avatars/_placeholder.png';
    }
    return avatarUrl!;
  }
}
