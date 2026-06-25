import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/inline_login_prompt_card.dart';

void main() {
  testWidgets('소셜 로그인 버튼만 보여주고 이메일 입력란은 숨긴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineLoginPromptCard(
            title: '프로필을 보려면 로그인이 필요해요',
            description: '프로필과 공부 기록은 로그인 후 사용할 수 있어요.',
            onSignedIn: () async {},
          ),
        ),
      ),
    );

    expect(find.text('카카오로 로그인'), findsOneWidget);
    expect(find.text('Google로 로그인'), findsOneWidget);
    expect(find.text('로그인'), findsNothing);
    expect(find.text('회원가입'), findsNothing);
    expect(find.widgetWithText(TextField, '이메일'), findsNothing);
    expect(find.widgetWithText(TextField, '비밀번호'), findsNothing);
    expect(find.text('이메일로 회원가입'), findsNothing);
  });
}
