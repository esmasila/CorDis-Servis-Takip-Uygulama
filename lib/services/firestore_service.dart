import 'package:cloud_firestore/cloud_firestore.dart';
class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<Map<String, dynamic>?> getActiveRouteForDriver(String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }
      return null;
    } catch (e) {
      print('Aktif rota getirme hatası: $e');
      return null;
    }
  }
  static Future<Map<String, dynamic>?> getActiveRouteForPassenger(String passengerId) async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }
      return null;
    } catch (e) {
      print('Aktif rota getirme hatası: $e');
      return null;
    }
  }
  static Future<bool> updateRouteStatus(String routeId, bool isActive) async {
    try {
      await _firestore
          .collection('routes')
          .doc(routeId)
          .update({'isActive': isActive});
      return true;
    } catch (e) {
      print('Rota durumu güncelleme hatası: $e');
      return false;
    }
  }
  static Future<bool> updateDriverLocation(String driverId, double latitude, double longitude) async {
    try {
      await _firestore
          .collection('drivers')
          .doc(driverId)
          .update({
        'currentLocation': {
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': FieldValue.serverTimestamp(),
        }
      });
      return true;
    } catch (e) {
      print('Şoför konumu güncelleme hatası: $e');
      return false;
    }
  }
  static Future<bool> updateStopStatus(String stopId, String status) async {
    try {
      await _firestore
          .collection('stops')
          .doc(stopId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Durak durumu güncelleme hatası: $e');
      return false;
    }
  }
  static Future<Map<String, dynamic>?> getPassengerInfo(String passengerId) async {
    try {
      final doc = await _firestore
          .collection('passengers')
          .doc(passengerId)
          .get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('Yolcu bilgileri getirme hatası: $e');
      return null;
    }
  }
  static Future<Map<String, dynamic>?> getDriverInfo(String driverId) async {
    try {
      final doc = await _firestore
          .collection('drivers')
          .doc(driverId)
          .get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('Şoför bilgileri getirme hatası: $e');
      return null;
    }
  }
}





