import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/permission_model.dart';
class PermissionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<String?> createPermission({
    required String userId,
    required String userName,
    required PermissionType type,
    required DateTime startDate,
    DateTime? endDate,
    String? reason,
    String? driverId,
  }) async {
    try {
      final permission = PermissionModel(
        id: '',
        userId: userId,
        userName: userName,
        type: type,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
        createdAt: DateTime.now(),
        driverId: driverId,
      );
      await _firestore.collection('permissions').add(permission.toMap());
      return null;
    } catch (e) {
      return 'İzin oluşturulurken hata: $e';
    }
  }
  static Stream<List<PermissionModel>> getUserPermissions(String userId) {
    return _firestore
        .collection('permissions')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PermissionModel.fromMap(doc.id, doc.data()))
            .toList());
  }
  static Stream<List<PermissionModel>> getDriverPassengerPermissions(
      String driverId) {
    return _firestore
        .collection('permissions')
        .where('driverId', isEqualTo: driverId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PermissionModel.fromMap(doc.id, doc.data()))
            .toList());
  }
  static Stream<List<PermissionModel>> getDriverPermissions(String driverId) {
    return _firestore
        .collection('permissions')
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PermissionModel.fromMap(doc.id, doc.data()))
            .toList());
  }
  static Future<String?> cancelPermission(String permissionId) async {
    try {
      await _firestore
          .collection('permissions')
          .doc(permissionId)
          .update({'isActive': false});
      return null;
    } catch (e) {
      return 'İzin iptal edilirken hata: $e';
    }
  }
  static Future<List<PermissionModel>> checkUserPermissionsForDate(
    String userId,
    DateTime date,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('permissions')
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .get();
      return snapshot.docs
          .map((doc) => PermissionModel.fromMap(doc.id, doc.data()))
          .where((permission) => permission.isValidForDate(date))
          .toList();
    } catch (e) {
      return [];
    }
  }
  static Stream<List<PermissionModel>> getTodayActivePermissions(
      String? driverId) {
    Query query =
        _firestore.collection('permissions').where('isActive', isEqualTo: true);
    if (driverId != null) {
      query = query.where('driverId', isEqualTo: driverId);
    }
    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final today = DateTime.now();
      return snapshot.docs
          .map((doc) => PermissionModel.fromMap(
              doc.id, doc.data() as Map<String, dynamic>))
          .where((permission) => permission.isValidForDate(today))
          .toList();
    });
  }
  static Future<List<PermissionModel>> getTodayActivePermissionsFuture(
      String? driverId) async {
    try {
      final today = DateTime.now();
      Query query = _firestore
          .collection('permissions')
          .where('isActive', isEqualTo: true);
      if (driverId != null) {
        query = query.where('driverId', isEqualTo: driverId);
      }
      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => PermissionModel.fromMap(
              doc.id, doc.data() as Map<String, dynamic>))
          .where((permission) => permission.isValidForDate(today))
          .toList();
    } catch (e) {
      return [];
    }
  }
  static Future<String?> createPermissionWithRouteUpdate({
    required String userId,
    required String userName,
    required PermissionType type,
    required DateTime startDate,
    DateTime? endDate,
    String? reason,
    String? driverId,
  }) async {
    try {
      final result = await createPermission(
        userId: userId,
        userName: userName,
        type: type,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
        driverId: driverId,
      );
      if (result != null) return result;
      await _triggerRouteUpdate(userId, driverId);
      print('✅ İzin oluşturuldu ve rota güncellendi');
      return null;
    } catch (e) {
      return 'İzin oluşturma ve rota güncelleme hatası: $e';
    }
  }
  static Future<void> cancelPermissionWithRouteUpdate(
      String permissionId, String userId, String? driverId) async {
    try {
      await cancelPermission(permissionId);
      await _triggerRouteUpdate(userId, driverId);
      print('✅ İzin iptal edildi ve rota güncellendi');
    } catch (e) {
      print('❌ İzin iptal ve rota güncelleme hatası: $e');
    }
  }
  static Future<void> _triggerRouteUpdate(
      String userId, String? driverId) async {
    if (driverId == null || driverId.isEmpty) return;
    try {
      print('🔄 Dinamik rota güncellemesi tetikleniyor...');
      await _deactivatePassengerStopTemporarily(userId);
      await _notifyDriverForRouteRefresh(driverId);
      await _refreshDriverRoute(driverId);
      print('✅ Dinamik rota güncellemesi tamamlandı');
    } catch (e) {
      print('❌ Dinamik rota güncelleme hatası: $e');
    }
  }
  static Future<void> _deactivatePassengerStopTemporarily(String userId) async {
    try {
      final stopsQuery = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: userId)
          .where('isActive', isEqualTo: true)
          .get();
      for (final doc in stopsQuery.docs) {
        await doc.reference.update({
          'temporarilyInactive': true,
          'inactiveReason': 'passenger_permission',
          'inactiveUntil': FieldValue.serverTimestamp(),
        });
      }
      print('📍 Yolcu durağı geçici olarak deaktif edildi');
    } catch (e) {
      print('❌ Durak deaktif etme hatası: $e');
    }
  }
  static Future<void> deactivatePassengerStopForPermission(
      String userId) async {
    await _deactivatePassengerStopTemporarily(userId);
  }
  static Future<void> _notifyDriverForRouteRefresh(String driverId) async {
    try {
      await _firestore.collection('driver_notifications').add({
        'driverId': driverId,
        'type': 'route_refresh',
        'message': 'Yolcu izni nedeniyle rota güncellendi',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'high',
      });
      try {
        final userDoc =
            await _firestore.collection('users').doc(driverId).get();
        final token = userDoc.data()?['fcmToken'];
        if (token != null) {
          await _firestore.collection('notifications').add({
            'userId': driverId,
            'type': 'route_change',
            'title': 'Rota Güncellemesi',
            'body': 'Yolcu izni nedeniyle rota yenilendi.',
            'data': {'type': 'route_change'},
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } catch (_) {}
      print('📨 Şoföre rota yenileme bildirimi gönderildi');
    } catch (e) {
      print('❌ Şoför bildirim hatası: $e');
    }
  }
  static Future<void> _refreshDriverRoute(String driverId) async {
    try {
      await _firestore.collection('route_refresh_triggers').add({
        'driverId': driverId,
        'triggeredBy': 'passenger_permission',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      try {
        final userDoc =
            await _firestore.collection('users').doc(driverId).get();
        if (userDoc.exists) {
          await _firestore.collection('notifications').add({
            'userId': driverId,
            'type': 'route_change',
            'title': 'Rota Güncellendi',
            'body':
                'İzin değişikliği nedeniyle rota ve ETA yeniden hesaplandı.',
            'data': {'type': 'route_change'},
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      } catch (_) {}
      print('🗺️ Şoför rotası yenileme tetiklendi');
    } catch (e) {
      print('❌ Rota yenileme tetikleme hatası: $e');
    }
  }
  static Future<void> reactivatePassengerStop(String userId) async {
    try {
      final stopsQuery = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: userId)
          .where('temporarilyInactive', isEqualTo: true)
          .get();
      for (final doc in stopsQuery.docs) {
        await doc.reference.update({
          'temporarilyInactive': FieldValue.delete(),
          'inactiveReason': FieldValue.delete(),
          'inactiveUntil': FieldValue.delete(),
        });
      }
      print('✅ Yolcu durağı yeniden aktif edildi');
    } catch (e) {
      print('❌ Durak yeniden aktif etme hatası: $e');
    }
  }
  static Future<String?> generateRouteForDateRange({
    required String driverId,
    required String regionId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      print(
          '🗺️ Tarih aralığına göre rota oluşturuluyor: $startDate - $endDate');
      var currentDate =
          DateTime(startDate.year, startDate.month, startDate.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      while (currentDate.isBefore(endDateOnly.add(const Duration(days: 1)))) {
        await _generateRouteForSpecificDate(
            driverId, regionId, currentDate, 'morning');
        await _generateRouteForSpecificDate(
            driverId, regionId, currentDate, 'evening');
        currentDate = currentDate.add(const Duration(days: 1));
      }
      print('✅ Tarih aralığı için rotalar başarıyla oluşturuldu');
      return null;
    } catch (e) {
      print('❌ Tarih aralığı rota oluşturma hatası: $e');
      return 'Rota oluşturma hatası: $e';
    }
  }
  static Future<void> _generateRouteForSpecificDate(
    String driverId,
    String regionId,
    DateTime date,
    String routeType,
  ) async {
    try {
      final result =
          await _firestore.collection('route_generation_requests').add({
        'driverId': driverId,
        'regionId': regionId,
        'routeDate': Timestamp.fromDate(date),
        'routeType': routeType,
        'requestedBy': 'permission_service',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      print('📅 Rota oluşturma talebi gönderildi: $date $routeType');
    } catch (e) {
      print('❌ Rota oluşturma talebi hatası: $e');
    }
  }
}

// Updated

