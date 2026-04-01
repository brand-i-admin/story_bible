class IntercessoryPrayerItem {
  const IntercessoryPrayerItem({
    required this.id,
    required this.targetUserId,
    required this.shareId,
    required this.nickname,
    required this.photoUrl,
    required this.prayerRequest,
    required this.createdAt,
  });

  final String id;
  final String targetUserId;
  final String shareId;
  final String nickname;
  final String? photoUrl;
  final String? prayerRequest;
  final DateTime createdAt;

  factory IntercessoryPrayerItem.fromMap(Map<String, dynamic> map) {
    return IntercessoryPrayerItem(
      id: map['id'] as String,
      targetUserId: map['target_user_id'] as String,
      shareId: ((map['share_id'] as String?) ?? '').trim(),
      nickname: (map['nickname'] as String?)?.trim().isNotEmpty == true
          ? (map['nickname'] as String).trim()
          : '사용자',
      photoUrl: (map['photo_url'] as String?)?.trim(),
      prayerRequest: (map['prayer_request'] as String?)?.trim(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
