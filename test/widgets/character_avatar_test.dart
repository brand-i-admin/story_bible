import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/character.dart';
import 'package:story_bible/widgets/character_avatar.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

Character _person({String name = '아브라함', String? avatarUrl}) {
  return Character(
    id: 'p1',
    code: 'abraham',
    name: name,
    tagline: null,
    description: null,
    avatarUrl: avatarUrl,
    displayOrder: 0,
  );
}

void main() {
  group('CharacterAvatar', () {
    testWidgets('이미지 로드 실패 시 이름 첫 글자 fallback을 표시', (tester) async {
      await tester.pumpWidget(
        _harness(CharacterAvatar(character: _person(name: '아브라함'))),
      );
      // Image.asset이 placeholder를 로드 시도 → 실패 → errorBuilder 호출
      await tester.pumpAndSettle();

      expect(find.text('아'), findsOneWidget);
    });

    testWidgets('이름이 빈 문자열이면 ? fallback', (tester) async {
      await tester.pumpWidget(
        _harness(CharacterAvatar(character: _person(name: ''))),
      );
      await tester.pumpAndSettle();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('이름이 공백만 있어도 ? fallback', (tester) async {
      await tester.pumpWidget(
        _harness(CharacterAvatar(character: _person(name: '   '))),
      );
      await tester.pumpAndSettle();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('size 인자가 Container에 반영된다', (tester) async {
      await tester.pumpWidget(
        _harness(CharacterAvatar(character: _person(), size: 80)),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(ClipOval),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.constraints?.maxWidth, 80);
      expect(container.constraints?.maxHeight, 80);
    });

    testWidgets('기본 크기는 32', (tester) async {
      await tester.pumpWidget(_harness(CharacterAvatar(character: _person())));

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(ClipOval),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.constraints?.maxWidth, 32);
    });

    testWidgets('원형 모양 (BoxShape.circle)을 유지한다', (tester) async {
      await tester.pumpWidget(_harness(CharacterAvatar(character: _person())));

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(ClipOval),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    });
  });
}
