import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('프로필 헤더는 샬롬 인사와 님 호칭을 닉네임 앞뒤에 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('Text.rich'));
    expect(source, contains("text: '샬롬! 🙌 '"));
    expect(source, contains("text: '님'"));
    expect(source, contains("'오늘도 말씀 안에서\\n승리하는 하루 되세요!'"));
    expect(
      source,
      contains('_buildCurrentUserAvatar(profile: profile, size: 56)'),
    );
  });

  test('프로필 활동 탭은 밝은 레일과 선택색 본문 표면을 연결한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_profileTabRailDecoration'));
    expect(source, contains('_profileLinkedTabGroupDecoration'));
    expect(source, contains('_profileLinkedTabBodyDecoration'));
    expect(source, contains('_profileSelectedTabSurface'));
    expect(source, contains('_profileSelectedTabButtonSurface'));
    expect(source, contains('_ProfileIconTabButton'));
    expect(source, contains('AppColors.fgOnDark'));
    expect(source, contains('palette.cardUnselectedTop'));
    expect(source, contains('palette.cardUnselectedBottom'));
    expect(source, contains('Icons.edit_note_rounded'));
    expect(source, contains('Icons.self_improvement_rounded'));
    expect(source, contains('Icons.bookmark_rounded'));
    expect(source, contains('Icons.menu_book_rounded'));
    expect(source, contains('_profileIconTabHeight = 44'));
    expect(source, contains('height: _profileIconTabHeight'));
    expect(source, contains('child: Row('));
    expect(source, contains('Flexible('));
    expect(source, contains('child: Icon(icon, color: accent, size: 16.5)'));
    expect(source, contains('alignment: Alignment.center'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.center'));
    expect(source, contains('_profileLeftCardChromeHeight = 90'));
    expect(source, contains('return 258;'));
    expect(source, isNot(contains('labelBelow')));
    expect(source, isNot(contains('fgOnDark.withValues(alpha: 0.92)')));
    expect(source, isNot(contains('floatingPanelDecoration')));
    expect(source, isNot(contains('_ProfileTabContentConnector')));
    expect(source, isNot(contains('math.min(constraints.maxWidth, 336.0)')));
  });

  test('프로필 기록 영역은 이야기 탐험과 이야기 통계 카드를 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_ProfileRecordsDashboard'));
    expect(source, contains('_ProfileCompletedRatioText'));
    expect(source, contains('_ProfileStoryExplorationPanel'));
    expect(source, contains('_ProfileStoryStatsPanel'));
    expect(source, contains('_ProfileEmotionStatsGrid'));
    expect(source, contains('_StoryProgressMiniCard'));
    expect(source, contains('_ProfileQuizStatsColumn'));
    expect(source, contains("'이야기 탐험'"));
    expect(source, contains("'이야기 통계'"));
    expect(source, contains("'내가 새긴 감정들'"));
    expect(source, contains("'다음 이야기'"));
    expect(source, contains('BoxConstraints(minHeight: 32)'));
    expect(source, contains('final itemGap = largeText ? 2.0 : 5.0'));
    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, contains('Axis.vertical'));
    expect(source, isNot(contains("label: '통독 진행률'")));
    expect(source, isNot(contains('_ProfileRecordsStatsPanel')));
    expect(source, isNot(contains('textScale >= 1.3')));
  });

  test('프로필 기록 진행률은 긴 progress bar와 작은 숫자로 표시한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('_StoryProgressMiniCard'));
    expect(source, contains('LinearProgressIndicator'));
    expect(source, contains('minHeight: 6'));
    expect(source, contains('fontSize: 14'));
    expect(source, contains('color: palette.successBottom'));
    expect(
      source,
      isNot(contains("final valueLabel = '\$completed/\$total';")),
    );
    expect(source, isNot(contains("replaceFirst('/', ' / ')")));
    expect(source, isNot(contains('_ProfileProgressDonut')));
    expect(source, isNot(contains("valueSuffix: '장'")));
    expect(source, isNot(contains("'퀴즈를 풀면 기록이 쌓여요.'")));
  });

  test('이야기 진행률 팝업은 전체/완료/미완료 필터를 제공한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(pageSource, contains('enum _StoryProgressFilter'));
    expect(source, contains('_StoryProgressFilterTabs'));
    expect(source, contains("label: '전체'"));
    expect(source, contains("label: '완료'"));
    expect(source, contains("label: '미완료'"));
    expect(source, contains('filteredEvents'));
  });

  test('저장한 이야기 미리보기는 썸네일 카드 높이를 확보한다', () {
    final source = File(
      'lib/widgets/profile/profile_left_panel.dart',
    ).readAsStringSync();

    expect(source, contains('return 228;'));
    expect(source, contains('EdgeInsets.fromLTRB(2, 8, 20, 8)'));
  });

  test('시대 선택 칩은 공용으로 다이어리 역할색을 사용한다', () {
    final source = File('lib/widgets/v2/era_pick_rows.dart').readAsStringSync();

    expect(source, contains('palette.currentAccentDeep'));
    expect(source, isNot(contains('palette.cardSelectedTop')));
    expect(source, isNot(contains('selectedAccent')));
  });

  test('프로필 진행률 섹션은 다이어리 본문 표면만 밝은 레일 안에 담는다', () {
    final source = File(
      'lib/widgets/profile/profile_progress_section.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/widgets/profile_tab_page.dart',
    ).readAsStringSync();

    expect(source, contains('accent: palette.currentAccentDeep'));
    expect(source, contains('_profileLinkedTabGroupDecoration'));
    expect(source, contains('_profileLinkedTabBodyDecoration'));
    expect(source, contains('selectedAccent'));
    expect(source, contains('ProfileEmotionDiary'));
    expect(source, isNot(contains('_profileProgressTabAccent(palette)')));
    expect(source, isNot(contains('Icons.directions_walk_rounded')));
    expect(source, isNot(contains('Icons.place_rounded')));
    expect(source, isNot(contains('_ProfileIconTabButton')));
    expect(source, isNot(contains('_profileProgressTabBar')));
    expect(source, isNot(contains('floatingPanelDecoration')));
    expect(pageSource, contains('_profileSectionsFrame'));
    expect(pageSource, contains('floatingPanelDecoration'));
    expect(pageSource, contains('scrollBody: false'));
    expect(source, isNot(contains('_ProfileTabContentConnector')));
    expect(source, isNot(contains('_profileProgressTabIndex()')));
  });

  test('기도 empty 상태의 추가 버튼은 동행 일지와 같은 초록 원형 톤을 사용한다', () {
    final source = File(
      'lib/widgets/profile/profile_intercessory_prayer.dart',
    ).readAsStringSync();
    final glowSource = File(
      'lib/widgets/profile/glowing_add_button.dart',
    ).readAsStringSync();
    final emptyStateSource = source
        .split('Widget _intercessoryPrayerFab')
        .first;

    expect(emptyStateSource, contains('_profilePrayerEmptyAddButton'));
    expect(emptyStateSource, contains('ProfileGlowingAddButton'));
    expect(glowSource, contains('AnimationController'));
    expect(glowSource, contains('repeat(reverse: true, count: 2)'));
    expect(glowSource, contains("ValueKey('profile-add-button-pulse-ring')"));
    expect(glowSource, contains('Colors.white.withValues(alpha: 0.88)'));
    expect(glowSource, contains('AppColors.greenTint2'));
    expect(glowSource, contains('AppColors.greenBot'));
    expect(
      emptyStateSource,
      isNot(contains("colors: [Color(0xFFD99F4A), Color(0xFFB26B28)]")),
    );
  });
}
