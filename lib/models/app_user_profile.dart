class AppUserProfile {
  const AppUserProfile({
    required this.userId,
    required this.shareId,
    required this.nickname,
    required this.photoUrl,
    required this.prayerRequest,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String shareId;
  final String nickname;
  final String? photoUrl;
  final String? prayerRequest;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AppUserProfile.fromMap(Map<String, dynamic> map) {
    return AppUserProfile(
      userId: map['user_id'] as String,
      shareId: ((map['share_id'] as String?) ?? '').trim(),
      nickname: (map['nickname'] as String?)?.trim().isNotEmpty == true
          ? (map['nickname'] as String).trim()
          : '사용자',
      photoUrl: (map['photo_url'] as String?)?.trim(),
      prayerRequest: (map['prayer_request'] as String?)?.trim(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
