import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:story_bible/data/notification_repository.dart';
import 'package:story_bible/models/app_notification.dart';
import 'package:story_bible/state/auth_providers.dart';
import 'package:story_bible/state/notification_providers.dart';
import 'package:story_bible/widgets/notification/notification_bell_button.dart';
import 'package:story_bible/widgets/notification/notification_dropdown.dart';

class _MockNotificationRepository extends Mock
    implements NotificationRepository {}

void main() {
  testWidgets('모두 읽음 직후 배지를 숨기고 빈 알림 문구를 보여준다', (tester) async {
    final repository = _MockNotificationRepository();
    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-05-26T00:00:00Z',
    );
    var unreadCount = 1;
    var unreadItems = [
      AppNotification(
        id: 'notification-1',
        source: NotificationSource.personal,
        type: AppNotificationType.quizCompleted,
        title: '퀴즈 완료',
        body: '복습할 알림이 있어요.',
        deepLink: '/profile',
        payload: const <String, dynamic>{},
        isRead: false,
        createdAt: DateTime.utc(2026, 5, 26),
      ),
    ];

    when(
      () => repository.watchUnreadCount(),
    ).thenAnswer((_) => Stream<int>.value(unreadCount));
    when(
      () => repository.fetchNotifications(limit: 5, onlyUnread: true),
    ).thenAnswer((_) async => unreadItems);
    when(() => repository.markAllRead()).thenAnswer((_) async {
      unreadCount = 0;
      unreadItems = const <AppNotification>[];
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInUserProvider.overrideWithValue(user),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: NotificationBellButton(
                onNavigate: (_) {},
                onOpenHistory: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('!'), findsOneWidget);

    await tester.tap(find.byType(NotificationBellButton));
    await tester.pumpAndSettle();
    expect(find.text('퀴즈 완료'), findsOneWidget);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(find.text('!'), findsNothing);
    expect(find.text('새로운 알림이 없어요'), findsOneWidget);
    verify(() => repository.markAllRead()).called(1);
  });

  testWidgets('좁은 화면에서도 알림 드롭다운을 화면 안에 연다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MockNotificationRepository();
    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-05-26T00:00:00Z',
    );

    when(
      () => repository.watchUnreadCount(),
    ).thenAnswer((_) => Stream<int>.value(0));
    when(
      () => repository.fetchNotifications(limit: 5, onlyUnread: true),
    ).thenAnswer((_) async => const <AppNotification>[]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInUserProvider.overrideWithValue(user),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: NotificationBellButton(
                onNavigate: (_) {},
                onOpenHistory: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotificationBellButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(NotificationDropdown)).width,
      lessThanOrEqualTo(304),
    );
  });
}
