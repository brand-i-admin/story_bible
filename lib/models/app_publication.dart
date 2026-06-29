enum AppPublicationCategory {
  notice('notice', '공지'),
  guide('guide', '가이드');

  const AppPublicationCategory(this.wire, this.label);

  final String wire;
  final String label;

  static AppPublicationCategory fromWire(String? raw) {
    for (final category in AppPublicationCategory.values) {
      if (category.wire == raw) {
        return category;
      }
    }
    return AppPublicationCategory.notice;
  }
}

class AppPublication {
  const AppPublication({
    required this.id,
    required this.slug,
    required this.category,
    required this.title,
    required this.body,
    required this.displayOrder,
    required this.createdAt,
    this.linkUrl,
    this.linkLabel,
    this.publishedAt,
  });

  final String id;
  final String slug;
  final AppPublicationCategory category;
  final String title;
  final String body;
  final String? linkUrl;
  final String? linkLabel;
  final int displayOrder;
  final DateTime? publishedAt;
  final DateTime createdAt;

  factory AppPublication.fromMap(Map<String, dynamic> row) {
    return AppPublication(
      id: (row['id'] as String?) ?? '',
      slug: (row['slug'] as String?) ?? '',
      category: AppPublicationCategory.fromWire(row['category'] as String?),
      title: (row['title'] as String?) ?? '',
      body: (row['body'] as String?) ?? '',
      linkUrl: _nonEmpty(row['link_url'] as String?),
      linkLabel: _nonEmpty(row['link_label'] as String?),
      displayOrder: ((row['display_order'] as num?) ?? 0).toInt(),
      publishedAt: _parseDate(row['published_at']),
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
    );
  }

  DateTime get displayDate => publishedAt ?? createdAt;

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static String? _nonEmpty(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
