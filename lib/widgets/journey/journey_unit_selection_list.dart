import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';
import '../../utils/journey_filtering.dart';
import '../fading_horizontal_text_scroll.dart';

class JourneyUnitSelectionList extends StatefulWidget {
  const JourneyUnitSelectionList({
    super.key,
    required this.groups,
    required this.selectedUnitKeys,
    required this.onSelectionChanged,
    this.targetBadgeLabel,
    this.expandPartiallySelectedEras = true,
    this.expandAllEras = false,
    this.revealInitialSelection = false,
    this.completedEventIds = const <String>{},
    this.showEraLabel = false,
    this.unifiedEraSurface = false,
  });

  final List<JourneyEraGroup> groups;
  final Set<String> selectedUnitKeys;
  final ValueChanged<Set<String>> onSelectionChanged;
  final String? targetBadgeLabel;
  final bool expandPartiallySelectedEras;
  final bool expandAllEras;
  final bool revealInitialSelection;
  final Set<String> completedEventIds;
  final bool showEraLabel;
  final bool unifiedEraSurface;

  @override
  State<JourneyUnitSelectionList> createState() =>
      _JourneyUnitSelectionListState();
}

class _JourneyUnitSelectionListState extends State<JourneyUnitSelectionList> {
  final Set<String> _expandedEraIds = <String>{};
  final Set<String> _initializedEraIds = <String>{};
  final GlobalKey _initialSelectionFocusKey = GlobalKey();
  String? _initialSelectionFocusEraId;
  bool _initialSelectionFocusScheduled = false;
  bool _didFocusInitialSelection = false;

  @override
  void initState() {
    super.initState();
    _initializeGroupExpansion(widget.groups);
  }

  @override
  void didUpdateWidget(covariant JourneyUnitSelectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initializeGroupExpansion(widget.groups);
  }

  void _initializeGroupExpansion(Iterable<JourneyEraGroup> groups) {
    for (final group in groups) {
      if (!_initializedEraIds.add(group.era.id)) continue;
      final selectedCount = group.units
          .where((unit) => widget.selectedUnitKeys.contains(unit.key))
          .length;
      if (widget.revealInitialSelection &&
          selectedCount > 0 &&
          _initialSelectionFocusEraId == null) {
        _initialSelectionFocusEraId = group.era.id;
      }
      if (widget.expandAllEras ||
          (widget.revealInitialSelection && selectedCount > 0) ||
          (widget.expandPartiallySelectedEras &&
              selectedCount > 0 &&
              selectedCount < group.units.length)) {
        _expandedEraIds.add(group.era.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      final palette = AppPaletteTheme.of(context);
      return Container(
        padding: const EdgeInsets.all(AppSpacing.x6),
        decoration: BoxDecoration(
          color: palette.mutedSurface,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: palette.subtleBorder),
        ),
        child: Text(
          '선택할 수 있는 시대 구간이 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: AppFontSizes.base,
          ),
        ),
      );
    }
    _scheduleInitialSelectionFocus();
    if (widget.unifiedEraSurface) {
      final palette = AppPaletteTheme.of(context);
      return Container(
        key: const ValueKey('journey-era-list-surface'),
        decoration: BoxDecoration(
          color: palette.cardSurface,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: palette.subtleBorder),
          boxShadow: AppShadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < widget.groups.length; index++) ...[
              _buildEraCard(
                context,
                widget.groups[index],
                embeddedInUnifiedSurface: true,
              ),
              if (index + 1 < widget.groups.length)
                Divider(height: 1, color: palette.subtleBorder),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < widget.groups.length; index++) ...[
          _buildEraCard(context, widget.groups[index]),
          if (index + 1 < widget.groups.length)
            const SizedBox(height: AppSpacing.x3),
        ],
      ],
    );
  }

  void _scheduleInitialSelectionFocus() {
    if (!widget.revealInitialSelection ||
        _didFocusInitialSelection ||
        _initialSelectionFocusScheduled ||
        _initialSelectionFocusEraId == null) {
      return;
    }
    _initialSelectionFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initialSelectionFocusScheduled = false;
      if (!mounted || _didFocusInitialSelection) return;
      final focusContext = _initialSelectionFocusKey.currentContext;
      if (focusContext == null) return;
      _didFocusInitialSelection = true;
      await Scrollable.ensureVisible(
        focusContext,
        alignment: 0.12,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildEraCard(
    BuildContext context,
    JourneyEraGroup group, {
    bool embeddedInUnifiedSurface = false,
  }) {
    final palette = AppPaletteTheme.of(context);
    final keys = group.units.map((unit) => unit.key).toSet();
    final selectedCount = keys.intersection(widget.selectedUnitKeys).length;
    final allSelected = selectedCount == keys.length && keys.isNotEmpty;
    final partiallySelected = selectedCount > 0 && !allSelected;
    final expanded = _expandedEraIds.contains(group.era.id);
    final bibleBooks = group.bibleBookNames.isEmpty
        ? '연결된 성경 권 없음'
        : group.bibleBookNames.join(' · ');
    final card = Container(
      key: ValueKey('journey-era-${group.era.code}'),
      decoration: embeddedInUnifiedSurface
          ? null
          : BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(
                color: selectedCount > 0
                    ? palette.selectedBorder
                    : palette.subtleBorder,
              ),
              boxShadow: AppShadows.sm,
            ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedEraIds.remove(group.era.id);
                } else {
                  _expandedEraIds.add(group.era.id);
                }
              });
            },
            borderRadius: embeddedInUnifiedSurface
                ? BorderRadius.zero
                : BorderRadius.circular(AppRadii.xl),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Row(
                children: [
                  Checkbox(
                    key: ValueKey('journey-era-checkbox-${group.era.code}'),
                    value: partiallySelected ? null : allSelected,
                    tristate: true,
                    onChanged: (_) => _toggleEra(group, !allSelected),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showEraLabel)
                          _FadingEraTitleRow(
                            eraCode: group.era.code,
                            emoji: journeyEraEmoji(group.era),
                            friendlyTitle: group.friendlyTitle,
                            eraName: group.era.name,
                          )
                        else
                          Row(
                            children: [
                              if (journeyEraEmoji(group.era).isNotEmpty) ...[
                                Text(
                                  journeyEraEmoji(group.era),
                                  key: ValueKey(
                                    'journey-era-emoji-${group.era.code}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: AppFontSizes.input,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.x2),
                              ],
                              Expanded(
                                child: Text(
                                  group.friendlyTitle,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: AppFontSizes.chip,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: AppSpacing.x1),
                        FadingHorizontalTextScroll(
                          text: bibleBooks,
                          scrollKey: ValueKey(
                            'journey-era-books-scroll-${group.era.code}',
                          ),
                          textScaler: MediaQuery.textScalerOf(context),
                          style: TextStyle(
                            color: palette.characterAccent,
                            fontSize: AppFontSizes.sm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: palette.mutedText,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Container(
              key: ValueKey('journey-nested-units-${group.era.code}'),
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.x6,
                0,
                AppSpacing.x3,
                AppSpacing.x3,
              ),
              decoration: BoxDecoration(
                color: palette.mutedSurface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: palette.subtleBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < group.units.length; index++) ...[
                    _buildUnitRow(context, group.units[index]),
                    if (index + 1 < group.units.length)
                      Divider(height: 1, color: palette.subtleBorder),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    if (_initialSelectionFocusEraId == group.era.id) {
      return KeyedSubtree(key: _initialSelectionFocusKey, child: card);
    }
    return card;
  }

  Widget _buildUnitRow(BuildContext context, JourneyUnitGroup unit) {
    final palette = AppPaletteTheme.of(context);
    final selected = widget.selectedUnitKeys.contains(unit.key);
    final targetLabel = widget.targetBadgeLabel;
    final progress = journeyProgress(
      unit.events,
      engravedEventIds: widget.completedEventIds,
    );
    return Material(
      key: ValueKey('journey-unit-${unit.key}'),
      color: selected
          ? Color.alphaBlend(palette.selectedSurface, palette.cardSurface)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _toggleUnit(unit.key, !selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x3,
            AppSpacing.x3,
            AppSpacing.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => _toggleUnit(unit.key, value ?? false),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FadingHorizontalTextScroll(
                            text: unit.title,
                            scrollKey: ValueKey(
                              'journey-unit-title-scroll-${unit.key}',
                            ),
                            textScaler: MediaQuery.textScalerOf(context),
                            style: TextStyle(
                              color: palette.text,
                              fontSize: AppFontSizes.base,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x2),
                        Container(
                          key: ValueKey('journey-unit-progress-${unit.key}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.x2,
                            vertical: AppSpacing.x1,
                          ),
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              palette.successBottom.withValues(alpha: 0.12),
                              palette.cardSurface,
                            ),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: palette.successBottom.withValues(
                                alpha: 0.58,
                              ),
                            ),
                          ),
                          child: Text(
                            '${progress.completed}/${progress.total}',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: palette.successBottom,
                              fontSize: AppFontSizes.xs,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (targetLabel != null && unit.containsTarget) ...[
                      const SizedBox(height: AppSpacing.x2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          key: ValueKey('journey-target-badge-${unit.key}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.x3,
                            vertical: AppSpacing.x1,
                          ),
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              palette.characterAccent.withValues(alpha: 0.18),
                              palette.cardSurface,
                            ),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: palette.characterAccent,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: palette.characterAccent.withValues(
                                  alpha: 0.13,
                                ),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: Text(
                            '$targetLabel ${unit.targetEventCount}개',
                            style: TextStyle(
                              color: palette.characterAccent,
                              fontSize: AppFontSizes.xs,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleEra(JourneyEraGroup group, bool selected) {
    final next = {...widget.selectedUnitKeys};
    for (final unit in group.units) {
      if (selected) {
        next.add(unit.key);
      } else {
        next.remove(unit.key);
      }
    }
    if (selected) {
      setState(() => _expandedEraIds.add(group.era.id));
    }
    widget.onSelectionChanged(next);
  }

  void _toggleUnit(String key, bool selected) {
    final next = {...widget.selectedUnitKeys};
    if (selected) {
      next.add(key);
    } else {
      next.remove(key);
    }
    widget.onSelectionChanged(next);
  }
}

class _FadingEraTitleRow extends StatefulWidget {
  const _FadingEraTitleRow({
    required this.eraCode,
    required this.emoji,
    required this.friendlyTitle,
    required this.eraName,
  });

  final String eraCode;
  final String emoji;
  final String friendlyTitle;
  final String eraName;

  @override
  State<_FadingEraTitleRow> createState() => _FadingEraTitleRowState();
}

class _FadingEraTitleRowState extends State<_FadingEraTitleRow> {
  final ScrollController _controller = ScrollController();
  bool _hasOverflow = false;
  bool _atEnd = true;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScrollState);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncScrollState)
      ..dispose();
    super.dispose();
  }

  void _scheduleOverflowCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _syncScrollState();
    });
  }

  void _syncScrollState() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final hasOverflow = position.maxScrollExtent > 0;
    final atEnd =
        !hasOverflow || position.pixels >= position.maxScrollExtent - 1;
    if (_hasOverflow == hasOverflow && _atEnd == atEnd) return;
    setState(() {
      _hasOverflow = hasOverflow;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowCheck();
    final palette = AppPaletteTheme.of(context);
    final showFade = _hasOverflow && !_atEnd;
    return Semantics(
      label: '${widget.friendlyTitle}, ${widget.eraName}',
      child: ExcludeSemantics(
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0, 0.72, 0.9, 1],
            colors: [
              Colors.white,
              Colors.white,
              showFade ? const Color(0x88FFFFFF) : Colors.white,
              showFade ? const Color(0x00FFFFFF) : Colors.white,
            ],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            key: ValueKey('journey-era-title-scroll-${widget.eraCode}'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.emoji.isNotEmpty) ...[
                  Text(
                    widget.emoji,
                    key: ValueKey('journey-era-emoji-${widget.eraCode}'),
                    style: const TextStyle(fontSize: AppFontSizes.input),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                ],
                Text(
                  widget.friendlyTitle,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: AppFontSizes.chip,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Container(
                  key: ValueKey('journey-era-label-${widget.eraCode}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x1,
                  ),
                  decoration: BoxDecoration(
                    color: palette.selectionFill,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: palette.selectedBorder),
                  ),
                  child: Text(
                    widget.eraName,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: palette.primaryDeep,
                      fontSize: AppFontSizes.xs,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
