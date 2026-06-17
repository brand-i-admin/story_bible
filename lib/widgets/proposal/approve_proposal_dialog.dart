import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/character_name_fallbacks.dart';
import '../../models/event_proposal.dart';

/// 새 이야기 제안 승인 전 띄우는 확인 다이얼로그.
///
/// 1) 제안 작성자가 새로 만든 캐릭터 + 기존 등장 인물의 `is_active` 를 관리자가
///    토글로 결정. 신규 인물은 기본 ON, 기존 인물은 현재 DB 값 그대로 시작.
/// 2) "승인" 클릭 시 `{ code: bool }` 매핑을 반환해 호출자가 RPC 에 전달.
/// 3) 취소면 null 반환.
///
/// 다이얼로그 안에서 직접 Supabase 를 한 번만 query 한다 (작은 N개라 OK).
class ApproveProposalDialog extends StatefulWidget {
  const ApproveProposalDialog({super.key, required this.proposal});

  final EventProposal proposal;

  /// 결과: code → is_active 매핑. 취소 시 null.
  static Future<Map<String, bool>?> show(
    BuildContext context,
    EventProposal proposal,
  ) {
    return showDialog<Map<String, bool>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApproveProposalDialog(proposal: proposal),
    );
  }

  @override
  State<ApproveProposalDialog> createState() => _ApproveProposalDialogState();
}

class _CharRow {
  _CharRow({
    required this.code,
    required this.name,
    required this.isNew,
    required this.isActive,
  });
  final String code;
  final String name;
  final bool isNew;
  bool isActive;
}

class _ApproveProposalDialogState extends State<ApproveProposalDialog> {
  late Future<List<_CharRow>> _rowsFuture;

  @override
  void initState() {
    super.initState();
    _rowsFuture = _loadRows();
  }

  Future<List<_CharRow>> _loadRows() async {
    final p = widget.proposal;
    final newCodes = {for (final c in p.proposedCharacters) c.code};
    final allCodes = <String>{...p.characterCodes, ...newCodes};
    if (allCodes.isEmpty) return const [];

    // 기존 characters 의 현재 name + is_active 조회.
    final client = Supabase.instance.client;
    final existing = <String, Map<String, dynamic>>{};
    try {
      final rows = await client
          .from('characters')
          .select('code, name, is_active')
          .inFilter('code', allCodes.toList());
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        existing[r['code'] as String] = r;
      }
    } catch (_) {
      // 조회 실패 시 모두 신규 취급 — 기본 활성으로 보여주고 진행.
    }

    final result = <_CharRow>[];
    // 신규 인물 먼저 (UI 가시성).
    for (final c in p.proposedCharacters) {
      final ex = existing[c.code];
      result.add(
        _CharRow(
          code: c.code,
          name: localizedCharacterName(code: c.code, name: c.name),
          isNew: ex == null,
          isActive: ex == null ? true : (ex['is_active'] as bool?) ?? true,
        ),
      );
    }
    // 기존 등장 인물.
    for (final code in p.characterCodes) {
      if (newCodes.contains(code)) continue; // 위에서 처리됨
      final ex = existing[code];
      result.add(
        _CharRow(
          code: code,
          name: localizedCharacterName(
            code: code,
            name: ex?['name'] as String?,
          ),
          isNew: false,
          isActive: (ex?['is_active'] as bool?) ?? true,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('제안 승인 — 등장 인물 검토')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<_CharRow>>(
          future: _rowsFuture,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '인물 정보를 불러오지 못했어요\n${snap.error}',
                  style: theme.textTheme.bodySmall,
                ),
              );
            }
            final rows = snap.data ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '승인하면 이 이야기가 사용자 지도에 즉시 표시됩니다.\n'
                  '아래 인물 각각이 앱에 노출될지(=is_active) 먼저 결정해 주세요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '등장 인물이 없습니다.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _CharSwitchRow(
                        row: rows[i],
                        onToggle: (v) => setState(() => rows[i].isActive = v),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FutureBuilder<List<_CharRow>>(
          future: _rowsFuture,
          builder: (ctx, snap) {
            final rows = snap.data;
            final ready = snap.connectionState == ConnectionState.done;
            return FilledButton.icon(
              onPressed: !ready
                  ? null
                  : () {
                      final overrides = <String, bool>{
                        for (final r in (rows ?? const <_CharRow>[]))
                          r.code: r.isActive,
                      };
                      Navigator.of(context).pop(overrides);
                    },
              icon: const Icon(Icons.check),
              label: const Text('최종 승인'),
            );
          },
        ),
      ],
    );
  }
}

class _CharSwitchRow extends StatelessWidget {
  const _CharSwitchRow({required this.row, required this.onToggle});
  final _CharRow row;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (row.isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'NEW',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  row.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            row.isActive ? '노출' : '숨김',
            style: theme.textTheme.bodySmall?.copyWith(
              color: row.isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Switch(value: row.isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}
