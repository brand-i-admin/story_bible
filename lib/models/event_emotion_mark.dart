class EventEmotionOption {
  const EventEmotionOption({
    required this.key,
    required this.label,
    required this.emoji,
  });

  final String key;
  final String label;
  final String emoji;

  static const options = <EventEmotionOption>[
    EventEmotionOption(key: 'joy', label: '기쁨', emoji: '✨'),
    EventEmotionOption(key: 'anticipation', label: '기대', emoji: '↗'),
    EventEmotionOption(key: 'gratitude', label: '감사', emoji: '♥'),
    EventEmotionOption(key: 'wonder', label: '놀라움', emoji: '?'),
    EventEmotionOption(key: 'sadness', label: '안타까움', emoji: '💧'),
    EventEmotionOption(key: 'comfort', label: '위로', emoji: '🌿'),
    EventEmotionOption(key: 'fear', label: '두려움', emoji: '⚡'),
    EventEmotionOption(key: 'other', label: '기타', emoji: '·'),
  ];

  static EventEmotionOption? byKey(String key) {
    for (final option in options) {
      if (option.key == key) return option;
    }
    return null;
  }
}

class EventEmotionMark {
  const EventEmotionMark({
    required this.eventId,
    required this.emotionKey,
    required this.emotionLabel,
    required this.emotionEmoji,
    required this.note,
    required this.updatedAt,
  });

  final String eventId;
  final String emotionKey;
  final String emotionLabel;
  final String emotionEmoji;
  final String note;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap({required String userId}) {
    final timestamp = (updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    return {
      'user_id': userId,
      'event_id': eventId,
      'emotion_key': emotionKey,
      'emotion_label': emotionLabel,
      'emotion_emoji': emotionEmoji,
      'note': note,
      'updated_at': timestamp,
    };
  }

  factory EventEmotionMark.fromMap(Map<String, dynamic> map) {
    final key = (map['emotion_key'] as String?) ?? 'other';
    final option = EventEmotionOption.byKey(key);
    final updatedAtText = map['updated_at'] as String?;
    return EventEmotionMark(
      eventId: map['event_id'] as String,
      emotionKey: key,
      emotionLabel: (map['emotion_label'] as String?) ?? option?.label ?? '기타',
      emotionEmoji: option?.emoji ?? (map['emotion_emoji'] as String?) ?? '·',
      note: (map['note'] as String?) ?? '',
      updatedAt: updatedAtText == null
          ? null
          : DateTime.tryParse(updatedAtText),
    );
  }
}
