import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/login_required_dialog.dart';

void main() {
  testWidgets('로그인 팝업은 내정보 안내와 이동 버튼을 사용한다', (tester) async {
    var openedMyInfo = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLoginRequiredDialog(
                context: context,
                message: '퀴즈를 풀려면 로그인이 필요해요.',
                onOpenMyInfo: () => openedMyInfo = true,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('퀴즈를 풀려면 로그인이 필요해요.'), findsOneWidget);
    expect(find.text('내정보 화면에서 로그인한 뒤 다시 이용해 주세요.'), findsOneWidget);
    expect(find.text('프로필 화면에서 로그인한 뒤 다시 이용해 주세요.'), findsNothing);
    expect(find.text('내정보로 이동'), findsOneWidget);
    expect(find.text('프로필로 이동'), findsNothing);

    await tester.tap(find.text('내정보로 이동'));
    await tester.pumpAndSettle();

    expect(openedMyInfo, isTrue);
    expect(find.text('로그인이 필요해요'), findsNothing);
  });
}
