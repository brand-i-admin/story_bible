class UserCompanionDiaryEntry {
  const UserCompanionDiaryEntry({
    required this.id,
    required this.userId,
    required this.entryDate,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final DateTime entryDate;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserCompanionDiaryEntry.fromMap(Map<String, dynamic> map) {
    return UserCompanionDiaryEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      entryDate: _parseDateOnly(map['entry_date']),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: _parseDateTime(map['created_at']),
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }

  UserCompanionDiaryEntry copyWith({
    String? id,
    String? userId,
    DateTime? entryDate,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserCompanionDiaryEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entryDate: entryDate ?? this.entryDate,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime _parseDateOnly(dynamic value) {
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final parsed = DateTime.parse(value as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  return DateTime.parse(value as String);
}
