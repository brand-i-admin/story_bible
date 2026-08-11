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
    final selectedUnitTitles =
        buildJourneyEraGroups(events: catalog.events, eras: catalog.eras)
            .expand((group) => group.units)
            .where((unit) => selection.unitKeys.contains(unit.key))
            .map((unit) => unit.title)
            .toList(growable: false);
    final selectionTitle = switch (selection.source) {
      JourneySource.all => '전체 순서',
      JourneySource.segments => _unitSelectionTitle(selectedUnitTitles),
      JourneySource.book => selection.displayLabel,
      JourneySource.person => selection.displayLabel,
    };
    final selectionDetail =
        selection.scope == JourneyScope.units && selectedUnitTitles.isNotEmpty
        ? '선택 구간 · ${selectedUnitTitles.join(' · ')}'
        : null;
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
          '아래 4가지 버튼에서 여정 방식을 선택해주세요',
          style: TextStyle(
            color: AppPaletteTheme.of(context).text,
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.x5),
        Wrap(
          spacing: AppSpacing.x3,
          runSpacing: AppSpacing.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '시간 순으로 차근차근',
              style: TextStyle(
                color: AppPaletteTheme.of(context).text,
                fontSize: AppFontSizes.input,
                fontWeight: FontWeight.w700,
              ),
            ),
            const _RecommendationBadge(),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _JourneyChoiceCard(
                  key: const ValueKey('journey-choice-all'),
                  icon: Icons.route_rounded,
                  title: '1. 전체 순서',
                  detail: '성경 전체 이야기를 시간 순으로 걸어요',
                  selected: selection.source == JourneySource.all,
                  onTap: () => _confirmAllJourney(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: _JourneyChoiceCard(
                  key: const ValueKey('journey-choice-segments'),
                  icon: Icons.checklist_rounded,
                  title: '2. 일부 구간 선택',
                  detail: '원하는 시대와 소분류를 골라요',
                  selected: selection.source == JourneySource.segments,
                  onTap: () => _openPartial(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x8),
        Text(
          '특정 방식으로 시작하기',
          style: TextStyle(
            color: AppPaletteTheme.of(context).text,
            fontSize: AppFontSizes.input,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _JourneyChoiceCard(
                  key: const ValueKey('journey-choice-book'),
                  icon: Icons.menu_book_rounded,
                  title: '3. 성경책으로 찾기',
                  detail: '구약·신약 66권에서 찾아요',
                  selected: selection.source == JourneySource.book,
                  onTap: () => _openBooks(context),
                ),
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: _JourneyChoiceCard(
                  key: const ValueKey('journey-choice-person'),
                  icon: Icons.person_search_rounded,
                  title: '4. 인물로 찾기',
                  detail: '인물이나 활동 시대로 찾아요',
                  selected: selection.source == JourneySource.person,
                  onTap: () => _openPeople(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x8),
        Text(
          '선택된 이야기 정보',
          style: TextStyle(
            color: AppPaletteTheme.of(context).text,
            fontSize: AppFontSizes.input,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        _SelectedJourneyInfo(
          title: selectionTitle,
          detail: selectionDetail,
          progress: currentProgress,
        ),
        const SizedBox(height: AppSpacing.x7),
        SizedBox(
          width: double.infinity,
          child: filledActionButton(
            label: '이 여정으로 홈 보기',
            minHeight: 42,
            fontSize: AppFontSizes.base,
            fontWeight: FontWeight.w700,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  String _unitSelectionTitle(List<String> titles) {
    if (titles.isEmpty) return '선택한 시대 구간';
    if (titles.length == 1) return titles.first;
    return '${titles.first} 외 ${titles.length - 1}개 구간';
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
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final surfaceColor = palette == AppColorPalette.blackMap
        ? Colors.black
        : Colors.white;
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(
              color: selected ? palette.selectedBorder : palette.subtleBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected ? AppShadows.green : AppShadows.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? palette.successBottom : palette.primary,
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: AppFontSizes.base,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: AppSpacing.x1),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: palette.successBottom,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                detail,
                style: TextStyle(
                  color: selected ? palette.primaryDeep : palette.mutedText,
                  fontSize: AppFontSizes.xs,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  height: AppLineHeights.snug,
                ),
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
  });

  final String title;
  final String? detail;
  final JourneyProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: const ValueKey('selected-journey-info'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x5,
        vertical: AppSpacing.x4,
      ),
      decoration: BoxDecoration(
        color: palette.mutedSurface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('selected-journey-info-accent'),
              width: 4,
              decoration: BoxDecoration(
                color: palette.currentAccentDeep,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    softWrap: true,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: AppFontSizes.base,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      detail!,
                      style: TextStyle(
                        color: palette.primaryDeep,
                        fontSize: AppFontSizes.sm,
                        fontWeight: FontWeight.w600,
                        height: AppLineHeights.normal,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    '${progress.total}개 이야기 중 ${progress.completed}개 해결',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: AppFontSizes.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
