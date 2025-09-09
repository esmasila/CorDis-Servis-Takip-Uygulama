import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stop_model.dart';
import '../models/driver_model.dart';
import '../models/user_model.dart';
class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<List<StopModel>> getStopsForDriver(String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      return querySnapshot.docs
          .map((doc) => StopModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Şoför durakları alma hatası: $e');
      return [];
    }
  }
  static Future<List<StopModel>> getStopsForRegion(String regionId) async {
    try {
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      return querySnapshot.docs
          .map((doc) => StopModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Bölge durakları alma hatası: $e');
      return [];
    }
  }
  static Future<void> updateStopStatus(String stopId, String status) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'status': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Durak durumu güncelleme hatası: $e');
    }
  }
  static Future<void> markStopAsCompleted(String stopId) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'isCompleted': true,
        'completedAt': FieldValue.serverTimestamp(),
        'status': 'completed',
      });
    } catch (e) {
      print('Durak tamamlama hatası: $e');
    }
  }
  static Future<List<StopModel>> getTodayStops(String driverId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt')
          .orderBy('order')
          .get();
      return querySnapshot.docs
          .map((doc) => StopModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Bugünkü durakları alma hatası: $e');
      try {
        final querySnapshot = await _firestore
            .collection('enhanced_stops')
            .where('driverId', isEqualTo: driverId)
            .where('isActive', isEqualTo: true)
            .orderBy('order')
            .get();
        return querySnapshot.docs
            .map((doc) => StopModel.fromFirestore(doc))
            .toList();
      } catch (e2) {
        print('Basit durak sorgusu hatası: $e2');
        return [];
      }
    }
  }
  static Future<DriverModel?> getDriver(String driverId) async {
    try {
      final doc = await _firestore.collection('drivers').doc(driverId).get();
      if (doc.exists) {
        return DriverModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Şoför alma hatası: $e');
      return null;
    }
  }
  static Future<DriverModel?> getDriverById(String driverId) async {
    return await getDriver(driverId);
  }
  static Future<Map<String, dynamic>?> getDriverLocation(
      String driverId) async {
    try {
      final doc =
          await _firestore.collection('live_locations').doc(driverId).get();
      if (doc.exists) {
        final data = doc.data()!;
        return {
          'latitude': data['lat'],
          'longitude': data['lng'],
          'timestamp': data['timestamp'],
          'driverId': data['driverId'],
        };
      }
      return null;
    } catch (e) {
      print('Şoför konumu alma hatası: $e');
      return null;
    }
  }
  static Future<List<DriverModel>> getDriversForRegion(String regionId) async {
    try {
      final querySnapshot = await _firestore
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      return querySnapshot.docs
          .map((doc) => DriverModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Bölge şoförleri alma hatası: $e');
      return [];
    }
  }
  static Future<void> updateDriverLocation(
      String driverId, double lat, double lng) async {
    try {
      await _firestore.collection('live_locations').doc(driverId).set({
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'driverId': driverId,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Şoför konumu güncelleme hatası: $e');
    }
  }
  static Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Kullanıcı alma hatası: $e');
      return null;
    }
  }
  static Future<void> updateUserProfile(
      String userId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        ...data,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Kullanıcı profili güncelleme hatası: $e');
    }
  }
  static Future<void> sendNotificationToUser(
      String userId, String title, String message) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': title,
        'message': message,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Bildirim gönderme hatası: $e');
    }
  }
  static Future<void> sendNotificationToRegion(
      String regionId, String title, String message) async {
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
          'title': title,
          'message': message,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      print('Bölge bildirimi gönderme hatası: $e');
    }
  }
  static Future<Map<String, dynamic>?> getActiveRouteForDriver(
      String driverId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> querySnapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        querySnapshot = await _firestore
            .collection('routes')
            .where('driverId', isEqualTo: driverId)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
      }
      if (querySnapshot.docs.isEmpty) {
        final fallback = await _firestore
            .collection('routes')
            .where('driverId', isEqualTo: driverId)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        if (fallback.docs.isNotEmpty) {
          final doc = fallback.docs.first;
          final data = doc.data();
          final status = (data['status'] ?? '').toString();
          final isActive = (data['isActive'] ?? false) == true;
          if (isActive ||
              (status.isNotEmpty &&
                  status != 'completed' &&
                  status != 'cancelled')) {
            return {'id': doc.id, ...data};
          }
        }
        return null;
      }
      final doc = querySnapshot.docs.first;
      return {
        'id': doc.id,
        ...doc.data(),
      };
    } catch (e) {
      print('Aktif rota alma hatası: $e');
      return null;
    }
  }
  static Future<void> updateRoute(
      String driverId, List<Map<String, dynamic>> route) async {
    try {
      await _firestore.collection('routes').doc(driverId).set({
        'driverId': driverId,
        'route': route,
        'lastUpdated': FieldValue.serverTimestamp(),
        'isActive': true,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Rota güncelleme hatası: $e');
    }
  }
  static Future<List<Map<String, dynamic>>> getRoute(String driverId) async {
    try {
      final doc = await _firestore.collection('routes').doc(driverId).get();
      if (doc.exists) {
        final data = doc.data()!;
        return List<Map<String, dynamic>>.from(data['route'] ?? []);
      }
      return [];
    } catch (e) {
      print('Rota alma hatası: $e');
      return [];
    }
  }
  static Future<void> sendMessage(
      String fromUserId, String toUserId, String message) async {
    try {
      await _firestore.collection('messages').add({
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
    }
  }
  static Stream<QuerySnapshot> getMessages(String userId1, String userId2) {
    return _firestore
        .collection('messages')
        .where('fromUserId', whereIn: [userId1, userId2])
        .where('toUserId', whereIn: [userId1, userId2])
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }
  static Future<bool> documentExists(
      String collection, String documentId) async {
    try {
      final doc = await _firestore.collection(collection).doc(documentId).get();
      return doc.exists;
    } catch (e) {
      print('Doküman varlık kontrolü hatası: $e');
      return false;
    }
  }
  static Future<void> deleteDocument(
      String collection, String documentId) async {
    try {
      await _firestore.collection(collection).doc(documentId).delete();
    } catch (e) {
      print('Doküman silme hatası: $e');
    }
  }
  static Future<void> updateDocument(
      String collection, String documentId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection(collection).doc(documentId).update({
        ...data,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Doküman güncelleme hatası: $e');
    }
  }
}





