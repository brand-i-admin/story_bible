import 'package:flutter/material.dart';

/// 제안 상태(pending/approved/rejected) 를 시각적으로 보여주는 작은 칩.
class ProposalStatusChip extends StatelessWidget {
  const ProposalStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, bg, fg) = switch (status) {
      'pending' => (
        '등록 대기중',
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      'approved' => ('등록 승인', const Color(0xFFDCEFD6), const Color(0xFF2E5D2A)),
      'rejected' => ('등록 거절', const Color(0xFFF5D7D3), const Color(0xFF6A2A24)),
      _ => (
        status,
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
