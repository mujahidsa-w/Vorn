// Service worker for background push on the web app (PWA).
// Keep this config in sync with DefaultFirebaseOptions.web in lib/firebase_options.dart.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REPLACE_WEB_API_KEY',
  authDomain: 'ms-company-e7166.firebaseapp.com',
  projectId: 'ms-company-e7166',
  storageBucket: 'ms-company-e7166.firebasestorage.app',
  messagingSenderId: '400730863326',
  appId: 'REPLACE_WEB_APP_ID',
});

// Messages that include a "notification" block are shown by the browser on their own.
// This handler covers data-only messages.
const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) || 'Vexo';
  const body = (payload.notification && payload.notification.body) || 'رسالة جديدة';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    tag: (payload.data && payload.data.roomId) || 'vexo',
  });
});

// Tapping a notification opens the app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return clients.openWindow('/');
    }),
  );
});
