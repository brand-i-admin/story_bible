// FCM Service Worker — Flutter Web 푸시 수신.
//
// 브라우저가 웹 푸시를 받으려면 루트 경로에 이 파일이 있어야 한다.
// lib/services/push_service.dart 의 getToken(vapidKey: ...) 이 호출되면
// 이 SW 가 자동 등록된다.
//
// Firebase config 값은 lib/firebase_options.dart 의 web 섹션과 동일해야 한다
// (flutterfire configure 재실행 시 양쪽 모두 갱신 필요).

importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC7pyz5ZQ7GUnXQFezMUs_CZevYbYb7I0I',
  appId: '1:196457947669:web:a12ecb5408f22cc46f641c',
  messagingSenderId: '196457947669',
  projectId: 'story-bible-491907',
  authDomain: 'story-bible-491907.firebaseapp.com',
  storageBucket: 'story-bible-491907.firebasestorage.app',
});

const messaging = firebase.messaging();

// 백그라운드 수신 — 브라우저 알림 표시.
// Notification 페이로드가 있으면 FCM 이 자동 표시하지만, 데이터 전용 메시지나
// 커스텀 action 을 위해 명시적으로 showNotification 을 호출.
messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) || '알림';
  const body = (payload.notification && payload.notification.body) || '';
  const link = (payload.data && payload.data.deep_link) || '/';
  self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    data: { link: link },
  });
});

// 알림 클릭 시: 이미 열린 앱 탭이 있으면 focus + deep_link 전달,
// 없으면 새 창으로 deep_link 를 연다. 앱 쪽은 아직 Service Worker 메시지
// 리스너를 달지 않아 단순 라우팅만 실행된다.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || '/';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const c of clientList) {
          if (c.url.indexOf(self.location.origin) === 0) {
            c.focus();
            c.postMessage({ type: 'fcm_deep_link', link: link });
            return;
          }
        }
        if (clients.openWindow) return clients.openWindow(link);
      }),
  );
});
