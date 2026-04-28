/// event_proposal_comments row — 사역자/관리자가 제안에 남기는 댓글.
class ProposalComment {
  const ProposalComment({
    required this.id,
    required this.proposalId,
    required this.authorUserId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String proposalId;
  final String authorUserId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProposalComment.fromMap(Map<String, dynamic> row) {
    final now = DateTime.now();
    return ProposalComment(
      id: row['id'] as String,
      proposalId: row['proposal_id'] as String,
      authorUserId: row['author_user_id'] as String,
      body: row['body'] as String,
      createdAt: _parseDate(row['created_at']) ?? now,
      updatedAt: _parseDate(row['updated_at']) ?? now,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
