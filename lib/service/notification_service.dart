import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';
import 'user_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  static NotificationService get instance => _instance;
  static const String webVapidPublicKey =
      'BL5bQ6YgQic0bsKKzYSYfxH7ktrVCerxi0qvoExnsoQQCyurbDyYLvAvUcJSeqUBrIMOtmMmyKLQ8Y7Wce2E-O8';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime? _lastNotificationTime;
  String? _lastNotificationKey;
  final Set<String> _recentMessageIds = {};
  static const int _maxRecentMessageIds = 50;
  static const Duration _duplicateWindow = Duration(seconds: 5);
  static bool _isChatScreenOpen = false;
  static bool _isAppInForeground = true;
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  void setChatScreenOpen(bool isOpen) {
    _isChatScreenOpen = isOpen;
    print('💬 Chat ekranı durumu: ${isOpen ? "açık" : "kapalı"}');
  }
  void setAppForeground(bool isForeground) {
    _isAppInForeground = isForeground;
    print('📱 Uygulama durumu: ${isForeground ? "ön planda" : "arka planda"}');
  }
  Future<void> initialize() async {
    try {
      await _requestPermissions();
      await _initializeLocalNotifications();
      await _setupFCMToken();
      _setupMessageHandlers();
      await startMessageNotifications();
      print('Bildirim servisi başlatıldı');
    } catch (e) {
      print('Bildirim servisi başlatma hatası: $e');
    }
  }
  Future<void> startMessageNotifications() async {
    try {
      final regionId = UserSession.regionId;
      final userId = UserSession.userId;
      final userRole = (UserSession.userRole ?? '').trim();
      if (regionId == null || regionId.isEmpty || userId == null) {
        return;
      }
      await _messageSubscription?.cancel();
      _messageSubscription = _firestore
          .collection('messages')
          .where('regionId', isEqualTo: regionId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data();
          if (data == null) continue;
          final messageId = change.doc.id;
          final senderId = data['senderId'] as String?;
          final senderName = data['senderName'] as String?;
          final content = data['content'] as String?;
          final senderRole = data['senderRole'] as String?;
          final isUrgent = data['isUrgent'] as bool? ?? false;
          if (senderId == userId) continue;
          if (_isChatScreenOpen && _isAppInForeground) {
            print(
                '🔇 Chat ekranı açık ve uygulama ön planda, bildirim gösterilmiyor');
            continue;
          }
          if (_isDuplicateNotification(messageId, senderId, content)) {
            print('🔄 Duplicate bildirim engellendi: $messageId');
            continue;
          }
          await _showMessageNotification(
            messageId: messageId,
            title: senderName ?? 'Bilinmeyen',
            body: content ?? 'Yeni mesaj',
            senderRole: senderRole ?? 'Kullanıcı',
            isUrgent: isUrgent,
          );
        }
      });
      print('✅ Mesaj bildirimleri başlatıldı');
    } catch (e) {
      print('❌ Mesaj bildirimleri başlatma hatası: $e');
    }
  }
  Future<void> refreshMessageNotifications() async {
    await startMessageNotifications();
  }
  Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    print('Bildirim izni durumu: ${settings.authorizationStatus}');
  }
  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) {
      return;
    }
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }
  Future<void> _setupFCMToken() async {
    try {
      final token = await _firebaseMessaging.getToken(
        vapidKey: kIsWeb ? webVapidPublicKey : null,
      );
      if (token != null) {
        await _saveFCMToken(token);
      }
      _firebaseMessaging.onTokenRefresh.listen(_saveFCMToken);
    } catch (e) {
      print('FCM token kurulum hatası: $e');
    }
  }
  Future<void> _saveFCMToken(String token) async {
    try {
      final String? userId =
          UserSession.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) return;
      final String? userRole = UserSession.userRole;
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (userRole == 'Şoför' || userRole == 'driver') {
        try {
          await _firestore.collection('drivers').doc(userId).set({
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print('✅ FCM token drivers koleksiyonuna da kaydedildi: $userId');
          await _firestore.collection('users').doc(userId).set({
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print(
              '✅ Şoför FCM token users koleksiyonunda da güncellendi: $userId');
        } catch (e) {
          print('⚠️ FCM token drivers koleksiyonuna kaydedilemedi: $e');
        }
      }
      if (userRole == 'Yolcu' || userRole == 'passenger') {
        try {
          final userDoc =
              await _firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            final userData = userDoc.data();
            final String? userDriverId = userData?['driverId'] as String?;
            if (userDriverId != null &&
                userDriverId.isNotEmpty &&
                userDriverId != userId) {
              await _firestore.collection('drivers').doc(userDriverId).set({
                'fcmToken': token,
                'lastTokenUpdate': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              print('✅ FCM token atanmış şoföre de kaydedildi: $userDriverId');
            }
          }
        } catch (e) {
          print('⚠️ Atanmış şoföre FCM token kaydedilemedi: $e');
        }
      }
      print('✅ FCM token başarıyla kaydedildi: $userId (role: $userRole)');
    } catch (e) {
      print('❌ FCM token kaydetme hatası: $e');
    }
  }
  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    _handleInitialMessage();
  }
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Ön plan mesajı alındı: ${message.messageId}');
    final String? type = (message.data['type'] as String?);
    if (type != null) {
      final t = type.toLowerCase();
      if (t == 'chat' ||
          t == 'message' ||
          t == 'group_chat' ||
          t == 'chat_message' ||
          t.contains('chat')) {
        print(
            'Chat mesajı - FCM bildirimi bastırıldı, Firestore dinleyicisi yönetecek');
        return;
      }
    }
    try {
      if ((UserSession.userRole ?? '').trim() == 'Şoför') {
        final systemTypes = {
          'distance_alert',
          'stop_arrival',
          'route_change',
          'stop_update'
        };
        if (type != null && !systemTypes.contains(type)) {
          return;
        }
      }
    } catch (_) {}
    await _showLocalNotification(
      title: message.notification?.title ?? 'Bildirim',
      body: message.notification?.body ?? '',
      payload: jsonEncode(message.data),
    );
  }
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    print('Uygulama açıldı, mesaj: ${message.messageId}');
    await _processNotificationData(message.data);
  }
  Future<void> _handleInitialMessage() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      print('İlk mesaj: ${initialMessage.messageId}');
      await _processNotificationData(initialMessage.data);
    }
  }
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) {
      return;
    }
    try {
      final String key = '${title.trim()}|${body.trim()}';
      final now = DateTime.now();
      if (_lastNotificationKey == key && _lastNotificationTime != null) {
        if (now.difference(_lastNotificationTime!).inMilliseconds <
            _duplicateWindow.inMilliseconds) {
          return;
        }
      }
      _lastNotificationKey = key;
      _lastNotificationTime = now;
    } catch (_) {}
    const androidDetails = AndroidNotificationDetails(
      'servis_app_channel',
      'Servis App Bildirimleri',
      channelDescription: 'Servis uygulaması bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _processNotificationData(data);
      } catch (e) {
        print('Bildirim payload işleme hatası: $e');
      }
    }
  }
  Future<void> _processNotificationData(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    switch (type) {
      case 'distance_alert':
        await _handleDistanceAlert(data);
        break;
      case 'stop_update':
        await _handleStopUpdate(data);
        break;
      case 'route_change':
        await _handleRouteChange(data);
        break;
      default:
        print('Bilinmeyen bildirim tipi: $type');
    }
  }
  Future<void> _handleDistanceAlert(Map<String, dynamic> data) async {
    print('Mesafe uyarısı işleniyor: $data');
  }
  Future<void> _handleStopUpdate(Map<String, dynamic> data) async {
    print('Durak güncelleme işleniyor: $data');
  }
  Future<void> _handleRouteChange(Map<String, dynamic> data) async {
    print('Rota değişikliği işleniyor: $data');
  }
  static Future<void> sendNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await NotificationService()._showLocalNotification(
        title: title,
        body: body,
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      print('Bildirim gönderme hatası: $e');
    }
  }
  static Future<void> sendProximityNotification({
    required String userId,
    required String regionId,
    required String type,
    required String message,
    String? title,
    Map<String, dynamic>? data,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'regionId': regionId,
        'type': type,
        'title': title ?? 'Bildirim',
        'body': message,
        'data': data ?? {},
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Yaklaşma bildirimi gönderme hatası: $e');
    }
  }
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'type': 'user_notification',
        'title': title,
        'body': message,
        'data': data ?? {},
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Kullanıcı bildirimi gönderme hatası: $e');
    }
  }
  Future<void> sendDistanceNotification({
    required String userId,
    required String driverName,
    required double distance,
    required String estimatedArrival,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': 'distance_alert',
        'title': 'Servis Yaklaşıyor',
        'body':
            '$driverName ${distance.toStringAsFixed(1)} km uzaklıkta. Tahmini varış: $estimatedArrival',
        'data': {
          'driverName': driverName,
          'distance': distance,
          'estimatedArrival': estimatedArrival,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Mesafe bildirimi gönderme hatası: $e');
    }
  }
  static Future<void> sendEarlyArrivalNotification({
    required String userId,
    required String passengerName,
    required int minutesEarly,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'type': 'early_arrival',
        'title': 'Erken Varış',
        'body': '$passengerName için $minutesEarly dakika erken varış.',
        'data': {
          'passengerName': passengerName,
          'minutesEarly': minutesEarly,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Erken varış bildirimi gönderme hatası: $e');
    }
  }
  Future<void> sendRegionNotification({
    required String regionId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final usersSnapshot = await _firestore
          .collection('users')
          .where('regionId', isEqualTo: regionId)
          .get();
      final batch = _firestore.batch();
      for (final userDoc in usersSnapshot.docs) {
        final notificationRef = _firestore.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': userDoc.id,
          'type': 'region_notification',
          'title': title,
          'body': message,
          'data': data ?? {},
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
      await batch.commit();
    } catch (e) {
      print('Bölge bildirimi gönderme hatası: $e');
    }
  }
  Future<void> sendDriverNotification({
    required String driverId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': driverId,
        'type': 'driver_notification',
        'title': title,
        'body': message,
        'data': data ?? {},
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Sürücü bildirimi gönderme hatası: $e');
    }
  }
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Bildirim okundu işaretleme hatası: $e');
    }
  }
  Stream<QuerySnapshot> getUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Okunmamış bildirim sayısı alma hatası: $e');
      return 0;
    }
  }
  Future<void> sendPushNotification({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _showLocalNotification(
        title: title,
        body: body,
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      print('Push bildirimi gönderme hatası: $e');
    }
  }
  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      if (kIsWeb) {
        return;
      }
      const androidDetails = AndroidNotificationDetails(
        'scheduled_channel',
        'Zamanlanmış Bildirimler',
        channelDescription: 'Zamanlanmış servis bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const details =
          NotificationDetails(android: androidDetails, iOS: iosDetails);
      await _localNotifications.zonedSchedule(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      print('Zamanlanmış bildirim hatası: $e');
    }
  }
  Future<void> clearAllNotifications() async {
    if (kIsWeb) return;
    await _localNotifications.cancelAll();
  }
  Future<void> cancelNotification(int notificationId) async {
    if (kIsWeb) return;
    await _localNotifications.cancel(notificationId);
  }
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      payload: payload,
    );
  }
  bool _isDuplicateNotification(
      String messageId, String? senderId, String? content) {
    final key = '$messageId-$senderId-$content';
    if (_lastNotificationKey == key &&
        _lastNotificationTime != null &&
        DateTime.now().difference(_lastNotificationTime!).inSeconds < 5) {
      return true;
    }
    if (_recentMessageIds.contains(messageId)) {
      return true;
    }
    _lastNotificationKey = key;
    _lastNotificationTime = DateTime.now();
    _recentMessageIds.add(messageId);
    if (_recentMessageIds.length > _maxRecentMessageIds) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
    return false;
  }
  Future<void> _showMessageNotification({
    required String messageId,
    required String title,
    required String body,
    required String senderRole,
    required bool isUrgent,
  }) async {
    try {
      final notificationTitle = isUrgent ? '🚨 Acil Mesaj' : '💬 Yeni Mesaj';
      final notificationBody = '$title ($senderRole): $body';
      await _showLocalNotification(
        title: notificationTitle,
        body: notificationBody,
        payload: messageId,
      );
      print('📱 Bildirim gösterildi: $notificationTitle - $notificationBody');
    } catch (e) {
      print('❌ Bildirim gösterme hatası: $e');
    }
  }
  Future<void> dispose() async {
    try {
      await _messageSubscription?.cancel();
      _messageSubscription = null;
    } catch (_) {}
    await clearAllNotifications();
  }
}

// Updated

