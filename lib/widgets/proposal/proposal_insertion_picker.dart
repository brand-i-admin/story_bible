import 'package:flutter/material.dart';

import '../../models/era.dart';
import '../../models/story_event.dart';
import 'person_codes_picker.dart';

/// 제안 폼의 상단 섹션. 홈 UI 톤(베이지/브라운, Card 기반)에 맞춰
/// 세 가지 선택을 하나의 흐름으로 묶는다:
///
/// 1) **시대**를 고른다 (chip)
/// 2) **등장인물**을 복수 선택 (기존 인물 chip + 자유 입력)
/// 3) **이 이야기를 어느 이야기 뒤에 넣을지** 카드 리스트에서 탭
///    - 리스트는 era 내 published events 중 선택된 인물이 한 명이라도 등장하는 것
///    - 선택된 인물이 하나도 없거나 해당 era 에 아무 이야기가 없으면 전체 리스트 표시
///    - "맨 앞에 배치" 는 별도 카드
///
/// 최종 선택은 [afterStoryIndex] (null = 맨 앞) 로 반환된다. 저장 시 RPC 가
/// story_index 시프트 + INSERT 를 수행한다.
class ProposalInsertionPicker extends StatefulWidget {
  const ProposalInsertionPicker({
    super.key,
    required this.eras,
    required this.availablePersons,
    required this.eventsFetcher,
    required this.initialEraId,
    required this.initialPersonCodes,
    required this.initialAfterStoryIndex,
    required this.onEraChanged,
    required this.onPersonCodesChanged,
    required this.onAfterStoryIndexChanged,
  });

  final List<Era> eras;
  final List<PersonOption> availablePersons;

  /// era 선택이 바뀔 때마다 events 를 로드한다 (StoryRepository.fetchEventsByEra 주입).
  final Future<List<StoryEvent>> Function(String eraId) eventsFetcher;

  final String? initialEraId;
  final List<String> initialPersonCodes;
  final int? initialAfterStoryIndex;

  final ValueChanged<String> onEraChanged;
  final ValueChanged<List<String>> onPersonCodesChanged;
  final ValueChanged<int?> onAfterStoryIndexChanged;

  @override
  State<ProposalInsertionPicker> createState() =>
      _ProposalInsertionPickerState();
}

class _ProposalInsertionPickerState extends State<ProposalInsertionPicker> {
  String? _eraId;
  List<String> _personCodes = const [];
  int? _afterStoryIndex; // null = 맨 앞
  List<StoryEvent> _events = const [];
  bool _loadingEvents = false;

  @override
  void initState() {
    super.initState();
    _eraId = widget.initialEraId;
    _personCodes = List.of(widget.initialPersonCodes);
    _afterStoryIndex = widget.initialAfterStoryIndex;
    if (_eraId != null) {
      _loadEvents(_eraId!);
    }
  }

  Future<void> _loadEvents(String eraId) async {
    setState(() => _loadingEvents = true);
    try {
      final events = await widget.eventsFetcher(eraId);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loadingEvents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _loadingEvents = false;
      });
    }
  }

  void _selectEra(String eraId) {
    setState(() {
      _eraId = eraId;
      _afterStoryIndex = null;
      _events = const [];
    });
    widget.onEraChanged(eraId);
    widget.onAfterStoryIndexChanged(null);
    _loadEvents(eraId);
  }

  void _updatePersons(List<String> codes) {
    setState(() => _personCodes = codes);
    widget.onPersonCodesChanged(codes);
  }

  void _selectAfter(int? storyIndex) {
    setState(() => _afterStoryIndex = storyIndex);
    widget.onAfterStoryIndexChanged(storyIndex);
  }

  /// 선택된 인물 중 하나라도 등장하는 이야기만 필터.
  /// 선택된 인물이 없으면 전체 반환.
  List<StoryEvent> _filteredEvents() {
    if (_personCodes.isEmpty) return _events;
    final selected = _personCodes.toSet();
    return _events.where((e) => e.personCodes.any(selected.contains)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(theme, '1. 시대 선택'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final era in widget.eras)
              ChoiceChip(
                label: Text(era.name),
                selected: _eraId == era.id,
                onSelected: (_) => _selectEra(era.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel(theme, '2. 등장 인물 (복수 선택)'),
        PersonCodesPicker(
          available: widget.availablePersons,
          initial: _personCodes,
          onChanged: _updatePersons,
        ),
        const SizedBox(height: 16),
        _sectionLabel(theme, '3. 이 이야기의 위치 선택'),
        Text(
          _personCodes.isEmpty
              ? '선택된 인물이 없으면 해당 시대의 모든 이야기에서 위치를 고를 수 있습니다. 탭한 이야기 "뒤"에 새 이야기가 들어갑니다.'
              : '선택한 인물이 등장하는 이야기만 보입니다. 탭한 이야기 "뒤"에 새 이야기가 들어갑니다.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_eraId == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '먼저 시대를 선택해주세요',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else if (_loadingEvents)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _buildInsertionList(theme),
      ],
    );
  }

  Widget _buildInsertionList(ThemeData theme) {
    final filtered = _filteredEvents();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsertionCard(
          title: '맨 앞에 배치',
          subtitle: '이 시대의 첫 이야기로 들어갑니다',
          selected: _afterStoryIndex == null,
          onTap: () => _selectAfter(null),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                _personCodes.isEmpty
                    ? '이 시대에 아직 이야기가 없습니다'
                    : '선택한 인물이 등장하는 이야기가 없습니다',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final e in filtered)
            _InsertionCard(
              title: e.title,
              subtitle: e.summary ?? '',
              personCodes: e.personCodes,
              storyIndex: e.storyIndex,
              selected: _afterStoryIndex == e.storyIndex,
              onTap: () => _selectAfter(e.storyIndex),
            ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InsertionCard extends StatelessWidget {
  const _InsertionCard({
    required this.title,
    required this.subtitle,
    this.personCodes,
    this.storyIndex,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<String>? personCodes;
  final int? storyIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? highlight.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? highlight : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (storyIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: Text(
                      '#$storyIndex',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (personCodes != null && personCodes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final c in personCodes!.take(6))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  c,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            if (personCodes!.length > 6)
                              Text(
                                '+${personCodes!.length - 6}',
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: highlight, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
