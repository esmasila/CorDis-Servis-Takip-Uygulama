import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'user_session.dart';
import 'location_service.dart';

class ProximityNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static Timer? _proximityCheckTimer;
  static StreamSubscription<Position>? _locationStream;
  static bool _isInitialized = false;
  static bool _isTracking = false;
  static String? _activePassengerId;
  static String? _activeDriverId;
  static String? _activeRegionId;
  static const double _defaultProximityDistance = 500.0;
  static const Duration _checkInterval = Duration(seconds: 30);
  static const Duration _notificationCooldown = Duration(minutes: 8);
  static final Map<String, DateTime> _lastNotificationTimes = {};
  static final Map<String, DateTime> _lastProximityNotificationTimes = {};
  static const Duration _proximityNotificationCooldown = Duration(minutes: 10);
  static Future<void> initialize() async {
    if (_isInitialized) return;
    print('📍 Yakınlık bildirimi servisi başlatılıyor...');
    await _initializeNotifications();
    _isInitialized = true;
    print('✅ Yakınlık bildirimi servisi başlatıldı');
  }

  static Future<void> _initializeNotifications() async {
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
    await _notifications.initialize(initSettings);
  }

  static Future<void> startProximityTracking(
      {String? passengerId, String? driverId}) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_isTracking) {
      print('⚠️ Yakınlık takibi zaten aktif');
      return;
    }
    print('🎯 Yakınlık takibi başlatılıyor...');
    final hasPermission = await LocationService().checkAndRequestPermissions();
    if (!hasPermission) {
      print('❌ Konum izni yok - yakınlık takibi başlatılamadı');
      return;
    }
    final String? resolvedPassengerId = passengerId ?? UserSession.userId;
    if (resolvedPassengerId == null) {
      print('❌ Yolcu ID bulunamadı');
      return;
    }
    String? resolvedDriverId = driverId ?? UserSession.driverId;
    final String? resolvedRegionId = UserSession.regionId;
    try {
      if ((resolvedDriverId == null || resolvedDriverId.isEmpty) &&
          resolvedRegionId != null &&
          resolvedRegionId.isNotEmpty) {
        final statusDoc = await _firestore
            .collection('service_status')
            .doc(resolvedRegionId)
            .get();
        if (statusDoc.exists) {
          resolvedDriverId = statusDoc.data()?['driverId'];
        }
      }
    } catch (e) {
      print('⚠️ Aktif şoför çözümleme hatası: $e');
    }
    if (resolvedDriverId == null || resolvedDriverId.isEmpty) {
      print('⚠️ Aktif şoför bulunamadı, yakınlık takibi başlatılmadı');
      return;
    }
    _activePassengerId = resolvedPassengerId;
    _activeDriverId = resolvedDriverId;
    _activeRegionId = resolvedRegionId;
    _proximityCheckTimer = Timer.periodic(_checkInterval, (timer) async {
      await _checkProximityOnce();
    });
    await _checkProximityOnce();
    _isTracking = true;
    print('✅ Yakınlık takibi başlatıldı');
  }

  static Future<void> stopProximityTracking() async {
    _proximityCheckTimer?.cancel();
    _locationStream?.cancel();
    _isTracking = false;
    print('🛑 Yakınlık takibi durduruldu');
  }

  static Future<void> _checkProximityOnce() async {
    try {
      if (_activePassengerId == null || _activeDriverId == null) return;
      final Position? userPosition =
          await LocationService().getCurrentPosition();
      if (userPosition == null) return;
      double? driverLat;
      double? driverLng;
      try {
        final liveDoc = await _firestore
            .collection('live_locations')
            .doc(_activeDriverId)
            .get();
        if (liveDoc.exists) {
          final d = liveDoc.data()!;
          driverLat = (d['lat'] as num?)?.toDouble();
          driverLng = (d['lng'] as num?)?.toDouble();
        }
      } catch (_) {}
      if (driverLat == null || driverLng == null) {
        try {
          final driverDoc =
              await _firestore.collection('drivers').doc(_activeDriverId).get();
          if (driverDoc.exists) {
            final dd = driverDoc.data()!;
            driverLat = (dd['currentLat'] as num?)?.toDouble();
            driverLng = (dd['currentLng'] as num?)?.toDouble();
            final GeoPoint? gp = dd['currentLocation'] as GeoPoint?;
            driverLat ??= gp?.latitude;
            driverLng ??= gp?.longitude;
          }
        } catch (_) {}
      }
      if (driverLat == null || driverLng == null) {
        return;
      }
      final double distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        driverLat,
        driverLng,
      );
      final double proximityDistance =
          await _getUserProximityDistance(_activePassengerId!);
      if (distance <= proximityDistance) {
        Map<String, dynamic> driverData = {'name': 'Şoför'};
        try {
          final ddoc =
              await _firestore.collection('drivers').doc(_activeDriverId).get();
          if (ddoc.exists) driverData = ddoc.data()!;
        } catch (_) {}
        await _handleProximityDetected(
          _activeDriverId!,
          driverData,
          distance,
          _activePassengerId!,
        );
        await _saveProximityData(
          _activePassengerId!,
          _activeDriverId!,
          distance,
          userPosition,
          GeoPoint(driverLat, driverLng),
        );
      }
    } catch (e) {
      print('❌ Yakınlık kontrolü hatası: $e');
    }
  }

  static Future<void> _checkDriverProximity(
    String driverId,
    Map<String, dynamic> driverData,
    Position userPosition,
    String userId,
  ) async {
    try {
      final driverLocation = driverData['currentLocation'] as GeoPoint?;
      if (driverLocation == null) return;
      final distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        driverLocation.latitude,
        driverLocation.longitude,
      );
      final proximityDistance = await _getUserProximityDistance(userId);
      if (distance <= proximityDistance) {
        await _handleProximityDetected(
          driverId,
          driverData,
          distance,
          userId,
        );
      }
      await _saveProximityData(
        userId,
        driverId,
        distance,
        userPosition,
        driverLocation,
      );
    } catch (e) {
      print('❌ Şoför yakınlık kontrolü hatası: $e');
    }
  }

  static Future<void> _handleProximityDetected(
    String driverId,
    Map<String, dynamic> driverData,
    double distance,
    String userId,
  ) async {
    try {
      final String notificationKey = '${driverId}_${userId}';
      final lastNotification = _lastProximityNotificationTimes[notificationKey];
      final now = DateTime.now();
      if (lastNotification != null &&
          now.difference(lastNotification) < _proximityNotificationCooldown) {
        print('⚠️ Bildirim cooldown süresi: ${driverId} -> ${userId}');
        return;
      }
      final driverName = driverData['name'] ?? 'Şoför';
      final title = '🚌 Servis Yaklaşıyor';
      final body = '$driverName ${distance.toStringAsFixed(0)}m uzaklıkta';
      await _showProximityNotification(title, body);
      _lastProximityNotificationTimes[notificationKey] = now;
      _cleanupOldNotificationTimes();
      print('✅ Yakınlık bildirimi gösterildi: $driverName -> $distance m');
    } catch (e) {
      print('❌ Yakınlık bildirimi hatası: $e');
    }
  }

  static Future<void> _showProximityNotification(
      String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'proximity_channel',
        'Yakınlık Bildirimleri',
        channelDescription: 'Şoför yakınlık bildirimleri',
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
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (e) {
      print('❌ Yakınlık bildirimi gösterme hatası: $e');
    }
  }

  static Future<double> _getUserProximityDistance(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final proximityDistance = data['proximityDistance'];
        if (proximityDistance != null) {
          if (proximityDistance is int) {
            return proximityDistance.toDouble();
          } else if (proximityDistance is double) {
            return proximityDistance;
          }
        }
        return _defaultProximityDistance;
      }
    } catch (e) {
      print('❌ Kullanıcı yakınlık ayarı alma hatası: $e');
    }
    return _defaultProximityDistance;
  }

  static void _cleanupOldNotificationTimes() {
    final now = DateTime.now();
    _lastNotificationTimes.removeWhere(
        (key, value) => now.difference(value) > _notificationCooldown);
    _lastProximityNotificationTimes.removeWhere(
        (key, value) => now.difference(value) > _proximityNotificationCooldown);
  }

  static Future<void> _saveProximityData(
    String userId,
    String driverId,
    double distance,
    Position userPosition,
    GeoPoint driverLocation,
  ) async {
    try {
      await _firestore.collection('proximity_data').add({
        'userId': userId,
        'driverId': driverId,
        'distance': distance,
        'userLocation': GeoPoint(
          userPosition.latitude,
          userPosition.longitude,
        ),
        'driverLocation': driverLocation,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateTime.now().toIso8601String().split('T')[0],
      });
    } catch (e) {
      print('❌ Yakınlık verisi kaydetme hatası: $e');
    }
  }

  static Future<void> _logProximityEvent(
    String userId,
    String driverId,
    double distance,
    String eventType,
  ) async {
    try {
      await _firestore.collection('proximity_events').add({
        'userId': userId,
        'driverId': driverId,
        'distance': distance,
        'eventType': eventType,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateTime.now().toIso8601String().split('T')[0],
      });
    } catch (e) {
      print('❌ Yakınlık olayı kaydetme hatası: $e');
    }
  }

  static Future<void> updateUserProximitySettings(
    String userId,
    double proximityDistance,
    bool enableNotifications,
  ) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'proximityDistance': proximityDistance.toDouble(),
        'enableProximityNotifications': enableNotifications,
        'proximitySettingsUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Yakınlık ayarları güncellendi: ${proximityDistance}m');
    } catch (e) {
      print('❌ Yakınlık ayarları güncelleme hatası: $e');
      throw e;
    }
  }

  static Future<void> checkProximityInBackground() async {
    if (!_isInitialized) {
      await initialize();
    }
    await _checkProximityOnce();
  }

  static Future<List<Map<String, dynamic>>> getProximityHistory(
    String userId, {
    int limit = 50,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore
          .collection('proximity_events')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(limit);
      if (startDate != null) {
        query = query.where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Yakınlık geçmişi alma hatası: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> getDailyProximityStats(
    String userId,
    DateTime date,
  ) async {
    try {
      final dateString = date.toIso8601String().split('T')[0];
      final eventsSnapshot = await _firestore
          .collection('proximity_events')
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: dateString)
          .get();
      final dataSnapshot = await _firestore
          .collection('proximity_data')
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: dateString)
          .get();
      final events = eventsSnapshot.docs.map((doc) => doc.data()).toList();
      final dataPoints = dataSnapshot.docs.map((doc) => doc.data()).toList();
      final totalEvents = events.length;
      final uniqueDrivers = events.map((e) => e['driverId']).toSet().length;
      final avgDistance = dataPoints.isNotEmpty
          ? dataPoints
                  .map((d) => d['distance'] as double)
                  .reduce((a, b) => a + b) /
              dataPoints.length
          : 0.0;
      final minDistance = dataPoints.isNotEmpty
          ? dataPoints.map((d) => d['distance'] as double).reduce(min)
          : 0.0;
      return {
        'date': dateString,
        'totalEvents': totalEvents,
        'uniqueDrivers': uniqueDrivers,
        'averageDistance': avgDistance,
        'minimumDistance': minDistance,
        'totalDataPoints': dataPoints.length,
      };
    } catch (e) {
      print('❌ Günlük yakınlık istatistikleri hatası: $e');
      return {
        'error': e.toString(),
        'date': date.toIso8601String().split('T')[0],
      };
    }
  }

  static Future<double> getNotificationDistance(String userId) async {
    return await _getUserProximityDistance(userId);
  }

  static Future<void> updateNotificationDistance(
    double distance, {
    String? passengerId,
  }) async {
    final userId = passengerId ?? UserSession.userId;
    if (userId == null) {
      throw Exception('Kullanıcı ID bulunamadı');
    }
    await updateUserProximitySettings(userId, distance, true);
  }

  static bool get isInitialized => _isInitialized;
  static bool get isTracking => _isTracking;
  static int get activeTimerCount =>
      _proximityCheckTimer?.isActive == true ? 1 : 0;
  static Future<void> dispose() async {
    await stopProximityTracking();
    _lastNotificationTimes.clear();
    _isInitialized = false;
    print('🛑 Yakınlık bildirimi servisi kapatıldı');
  }
}



 Again


