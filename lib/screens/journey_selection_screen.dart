import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journey_selection.dart';
import '../state/journey_selection_providers.dart';
import '../state/story_controller.dart';
import '../theme/app_color_palette.dart';
import '../theme/tokens.dart';
import '../utils/journey_filtering.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/story_home_styles.dart';
import '../widgets/sub_page_scaffold.dart';
import 'journey_selection/book_journey_screen.dart';
import 'journey_selection/journey_selection_route.dart';
import 'journey_selection/partial_journey_screen.dart';
import 'journey_selection/person_journey_screen.dart';
import 'journey_selection/target_journey_scope_screen.dart';

class JourneySelectionScreen extends ConsumerWidget {
  const JourneySelectionScreen({super.key});

  static const String routeName = journeySelectionRouteName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(journeyCatalogProvider);
    final selection = ref.watch(journeySelectionProvider);
    final engravedEventIds = ref.watch(
      storyControllerProvider.select(
        (state) => state.eventEmotionMarks.keys.toSet(),
      ),
    );
    return SubPageScaffold(
      title: '여정 선택',
      plainHeader: true,
      child: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _JourneyLoadError(
          onRetry: () => ref.invalidate(journeyCatalogProvider),
        ),
        data: (catalog) => _JourneySelectionBody(
          catalog: catalog,
          selection: selection,
          engravedEventIds: engravedEventIds,
        ),
      ),
    );
  }
}

class _JourneySelectionBody extends ConsumerWidget {
  const _JourneySelectionBody({
    required this.catalog,
    required this.selection,
    required this.engravedEventIds,
  });

  final JourneyCatalogData catalog;
  final JourneySelection selection;
  final Set<String> engravedEventIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charactersByCode = {
      for (final character in catalog.characters) character.code: character,
    };
    final currentEvents = filterJourneyEvents(
      events: catalog.events,
      eras: catalog.eras,
      selection: selection,
      charactersByCode: charactersByCode,
    );
    final currentProgress = journeyProgress(
      currentEvents,
      engravedEventIds: engravedEventIds,
    );
    final eraGroups = buildJourneyEraGroups(
      events: catalog.events,
      eras: catalog.eras,
    );
    final selectedGroups = eraGroups
        .where(
          (group) =>
              group.units.any((unit) => selection.unitKeys.contains(unit.key)),
        )
        .toList(growable: false);
    final selectionTitle = switch (selection.source) {
      JourneySource.all => '성경 전체를 순서대로',
      JourneySource.segments => '시대·구간에서 고르기',
      JourneySource.book => '성경책에서 시작하기',
      JourneySource.person => '인물에서 시작하기',
    };
    final selectionDetail = switch (selection.source) {
      JourneySource.all => '창세기부터 차례대로 이어서 읽어요',
      JourneySource.segments => _selectionUnitDetail(selectedGroups),
      JourneySource.book || JourneySource.person =>
        selection.scope == JourneyScope.targetOnly
            ? selection.displayLabel
            : '${_selectionTargetLabel(selection)} | ${_selectionUnitDetail(selectedGroups)}',
    };
    return ListView(
      key: const ValueKey('journey-selection-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x6,
        AppSpacing.x3,
        AppSpacing.x6,
        AppSpacing.x10,
      ),
      children: [
        Text(
          '어떤 기준으로 이야기를 따라가 볼까요?',
          style: TextStyle(
            color: AppPaletteTheme.of(context).text,
            fontSize: AppFontSizes.input,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        _JourneyChoiceCard(
          key: const ValueKey('journey-choice-all'),
          surfaceKey: const ValueKey('journey-choice-all-surface'),
          selectedIndicatorKey: const ValueKey('journey-all-selected-check'),
          icon: Icons.route_rounded,
          title: '성경 전체를 순서대로',
          detail: '창세기부터 차례대로 이어서 읽어요',
          selected: selection.source == JourneySource.all,
          recommended: true,
          onTap: () => _confirmAllJourney(context, ref),
        ),
        const SizedBox(height: AppSpacing.x3),
        _JourneyChoiceCard(
          key: const ValueKey('journey-choice-person'),
          icon: Icons.person_rounded,
          title: '인물에서 시작하기',
          detail: '인물로 찾아요',
          selected: selection.source == JourneySource.person,
          onTap: () => _openPeople(context),
        ),
        const SizedBox(height: AppSpacing.x3),
        _JourneyChoiceCard(
          key: const ValueKey('journey-choice-book'),
          icon: Icons.menu_book_rounded,
          title: '성경책에서 시작하기',
          detail: '구약·신약 66권에서 찾아요',
          selected: selection.source == JourneySource.book,
          onTap: () => _openBooks(context),
        ),
        const SizedBox(height: AppSpacing.x3),
        _JourneyChoiceCard(
          key: const ValueKey('journey-choice-segments'),
          icon: Icons.schedule_rounded,
          title: '시대·구간에서 고르기',
          detail: '원하는 시대와 소분류를 골라요',
          selected: selection.source == JourneySource.segments,
          onTap: () => _openPartial(context),
        ),
        const SizedBox(height: AppSpacing.x7),
        Row(
          key: const ValueKey('current-journey-section-divider'),
          children: [
            Expanded(
              child: Divider(color: AppPaletteTheme.of(context).subtleBorder),
            ),
            const SizedBox(width: AppSpacing.x3),
            Icon(
              Icons.route_rounded,
              size: 17,
              color: AppPaletteTheme.of(context).mutedText,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Divider(color: AppPaletteTheme.of(context).subtleBorder),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        _SelectedJourneyInfo(
          title: selectionTitle,
          detail: selectionDetail,
          progress: currentProgress,
          onTap: () => _openCurrentJourney(
            context,
            selection: selection,
            currentEventCount: currentEvents.length,
          ),
        ),
        const SizedBox(height: AppSpacing.x7),
        SizedBox(
          width: double.infinity,
          child: filledActionButton(
            label: '선택된 여정으로 지도 위 나열',
            minHeight: 42,
            fontSize: AppFontSizes.base,
            fontWeight: FontWeight.w700,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  String _selectionTargetLabel(JourneySelection selection) {
    return switch (selection.source) {
      JourneySource.book => selection.bookName ?? '성경책',
      JourneySource.person => selection.personName ?? '인물',
      JourneySource.all || JourneySource.segments => selection.displayLabel,
    };
  }

  String _selectionUnitDetail(List<JourneyEraGroup> groups) {
    if (groups.isEmpty) {
      return '선택한 시대 | 선택한 대분류(선택한 소분류)';
    }
    return groups
        .map((group) {
          final units = group.units
              .where((unit) => selection.unitKeys.contains(unit.key))
              .map((unit) => unit.title)
              .join(', ');
          return '${group.era.name} | ${group.friendlyTitle}($units)';
        })
        .join(' · ');
  }

  Future<void> _openPartial(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartialJourneyScreen(catalog: catalog),
      ),
    );
  }

  Future<void> _confirmAllJourney(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '전체 순서로 설정하시겠습니까?',
        actions: [
          ParchmentDialogActionButton(
            label: '취소',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(false),
          ),
          ParchmentDialogActionButton(
            label: '설정',
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Text(
          '성경 전체 이야기를 시간 순서대로 보여줍니다.',
          style: TextStyle(
            color: AppPaletteTheme.of(dialogContext).mutedText,
            fontSize: AppFontSizes.base,
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await ref
          .read(journeySelectionProvider.notifier)
          .setSelection(const JourneySelection.all());
    }
  }

  Future<void> _openBooks(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookJourneyScreen(
          catalog: catalog,
          engravedEventIds: engravedEventIds,
        ),
      ),
    );
  }

  Future<void> _openPeople(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonJourneyScreen(
          catalog: catalog,
          engravedEventIds: engravedEventIds,
        ),
      ),
    );
  }

  Future<void> _openCurrentJourney(
    BuildContext context, {
    required JourneySelection selection,
    required int currentEventCount,
  }) async {
    switch (selection.source) {
      case JourneySource.all:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => ParchmentDialog(
            title: '성경 전체를 순서대로',
            actions: [
              ParchmentDialogActionButton(
                label: '확인',
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ],
            child: Text(
              '$currentEventCount개 이야기가 모두 포함되어 있어요.',
              style: TextStyle(
                color: AppPaletteTheme.of(dialogContext).mutedText,
                fontSize: AppFontSizes.base,
              ),
            ),
          ),
        );
        return;
      case JourneySource.segments:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PartialJourneyScreen(catalog: catalog, revealSelection: true),
          ),
        );
        return;
      case JourneySource.book:
        final bookName = selection.bookName;
        if (bookName == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TargetJourneyScopeScreen.book(
              bookName: bookName,
              catalog: catalog,
              engravedEventIds: engravedEventIds,
              initialSelection: selection,
              revealSelection: true,
            ),
          ),
        );
        return;
      case JourneySource.person:
        final character = catalog.characters
            .where((item) => item.code == selection.personCode)
            .firstOrNull;
        if (character == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TargetJourneyScopeScreen.person(
              character: character,
              catalog: catalog,
              engravedEventIds: engravedEventIds,
              initialSelection: selection,
              revealSelection: true,
            ),
          ),
        );
        return;
    }
  }
}

class _RecommendationBadge extends StatelessWidget {
  const _RecommendationBadge();

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: const ValueKey('journey-recommendation-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: palette.currentFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: palette.currentAccent.withValues(alpha: 0.78),
        ),
      ),
      child: Text(
        '추천',
        style: TextStyle(
          color: palette.text,
          fontSize: AppFontSizes.xs,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _JourneyChoiceCard extends StatelessWidget {
  const _JourneyChoiceCard({
    super.key,
    this.surfaceKey,
    this.selectedIndicatorKey,
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    this.recommended = false,
    required this.onTap,
  });

  final Key? surfaceKey;
  final Key? selectedIndicatorKey;
  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final surfaceColor = palette == AppColorPalette.blackMap
        ? Colors.black
        : Colors.white;
    return Material(
      color: selected ? Colors.transparent : surfaceColor,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          key: surfaceKey,
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.cardSelectedTop,
                      palette.cardSelectedBottom,
                    ],
                  )
                : null,
            color: selected ? null : surfaceColor,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(
              color: selected
                  ? AppColors.fgOnDark.withValues(alpha: 0.88)
                  : palette.subtleBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected ? AppShadows.md : AppShadows.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.fgOnDark.withValues(alpha: 0.14)
                      : palette.mutedSurface,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: AppColors.fgOnDark.withValues(alpha: 0.32),
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: selected ? AppColors.fgOnDark : palette.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.x5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? AppColors.fgOnDark : palette.text,
                        fontSize: AppFontSizes.base,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      detail,
                      style: TextStyle(
                        color: selected
                            ? AppColors.fgOnDark.withValues(alpha: 0.88)
                            : palette.mutedText,
                        fontSize: AppFontSizes.sm,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        height: AppLineHeights.snug,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  key: selectedIndicatorKey,
                  size: 21,
                  color: palette.successBottom,
                )
              else if (recommended)
                const _RecommendationBadge()
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 21,
                  color: palette.mutedText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedJourneyInfo extends StatelessWidget {
  const _SelectedJourneyInfo({
    required this.title,
    required this.detail,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final String? detail;
  final JourneyProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      key: const ValueKey('selected-journey-info'),
      color: palette.mutedSurface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x5,
            vertical: AppSpacing.x4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.selectionFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.route_rounded,
                  size: 22,
                  color: palette.primaryDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '현재 선택된 여정',
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: AppFontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      title,
                      softWrap: true,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: AppFontSizes.input,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpacing.x2),
                      Text(
                        detail!,
                        softWrap: true,
                        style: TextStyle(
                          color: palette.primaryDeep,
                          fontSize: AppFontSizes.sm,
                          fontWeight: FontWeight.w600,
                          height: AppLineHeights.normal,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x4),
                    Container(
                      key: const ValueKey('selected-journey-progress-track'),
                      height: 16,
                      decoration: BoxDecoration(
                        color: palette.subtleBorder,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [
                          LinearProgressIndicator(
                            key: const ValueKey('selected-journey-progress'),
                            value: progress.total == 0
                                ? 0
                                : progress.completed / progress.total,
                            minHeight: 16,
                            backgroundColor: Colors.transparent,
                            color: palette.primaryDeep,
                          ),
                          Center(
                            child: Text(
                              '${progress.completed}/${progress.total}',
                              key: const ValueKey(
                                'selected-journey-progress-count',
                              ),
                              maxLines: 1,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color:
                                    progress.total > 0 &&
                                        progress.completed / progress.total >=
                                            0.5
                                    ? AppColors.fgOnDark
                                    : palette.primaryDeep,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                height: 1,
                                shadows: [
                                  Shadow(
                                    color:
                                        progress.total > 0 &&
                                            progress.completed /
                                                    progress.total >=
                                                0.5
                                        ? Colors.black38
                                        : palette.cardSurface,
                                    blurRadius: 1.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Icon(Icons.chevron_right_rounded, color: palette.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyLoadError extends StatelessWidget {
  const _JourneyLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('여정 정보를 불러오지 못했습니다.'),
            const SizedBox(height: AppSpacing.x5),
            filledActionButton(label: '다시 시도', onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
