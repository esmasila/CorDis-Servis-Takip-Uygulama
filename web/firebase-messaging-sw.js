/* Firebase Messaging Service Worker for Flutter Web */

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: 'AIzaSyDU9DVmj9Et8DmJVeEahvPX2jlgm7e3Ipw',
    appId: '1:283736871966:web:78e0052aea544581800a0f',
    messagingSenderId: '283736871966',
    projectId: 'servis-takip-uygulama',
    authDomain: 'servis-takip-uygulama.firebaseapp.com',
    storageBucket: 'servis-takip-uygulama.firebasestorage.app',
    measurementId: 'G-BD67ZE7ETF',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
    const title = (payload.notification && payload.notification.title) || 'Bildirim';
    const options = {
        body: (payload.notification && payload.notification.body) || '',
        icon: '/icons/Icon-192.png',
        data: payload.data || {},
    };
    self.registration.showNotification(title, options);
});

// Click handling
self.addEventListener('notificationclick', function (event) {
    event.notification.close();
    const targetUrl = event.notification?.data?.click_action || '/';
    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then(windowClients => {
            for (let client of windowClients) {
                if (client.url.includes(self.location.origin)) {
                    return client.focus();
                }
            }
            return clients.openWindow(targetUrl);
        })
    );
});


