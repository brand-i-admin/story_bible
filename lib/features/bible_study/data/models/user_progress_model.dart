class UserProgress {
  const UserProgress({
    required this.eventId,
    required this.completed,
    this.completedAt,
  });

  final int eventId;
  final bool completed;
  final DateTime? completedAt;

  factory UserProgress.fromJson(Map<String, dynamic> json) {
    return UserProgress(
      eventId: json['event_id'] as int,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'completed': completed,
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}
