import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../service/user_session.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
class DistanceNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Future<void> setDistanceAlert(
    String passengerId,
    LatLng passengerLocation,
    double alertDistanceMeters,
  ) async {
    try {
      final regionId = UserSession.regionId ?? '';
      await _firestore.collection('distance_alerts').doc(passengerId).set({
        'passengerId': passengerId,
        'regionId': regionId,
        'alertDistanceMeters': alertDistanceMeters,
        'passengerLat': passengerLocation.latitude,
        'passengerLng': passengerLocation.longitude,
        'isActive': true,
        'repeat': true,
        'isInside': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastChecked': FieldValue.serverTimestamp(),
      });
      print('🔔 Mesafe uyarısı ayarlandı: ${alertDistanceMeters}m');
    } catch (e) {
      print('❌ Mesafe uyarısı ayarlama hatası: $e');
    }
  }
  Future<void> removeDistanceAlert(String passengerId) async {
    try {
      await _firestore.collection('distance_alerts').doc(passengerId).update({
        'isActive': false,
        'removedAt': FieldValue.serverTimestamp(),
      });
      print('🔕 Mesafe uyarısı kaldırıldı');
    } catch (e) {
      print('❌ Mesafe uyarısı kaldırma hatası: $e');
    }
  }
  static Future<void> checkDistanceAlerts({
    required String driverId,
    required String regionId,
    required double driverLat,
    required double driverLng,
  }) async {
    try {
      final alertsSnapshot = await _firestore
          .collection('distance_alerts')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      for (var alertDoc in alertsSnapshot.docs) {
        final alertData = alertDoc.data();
        final alertDistance = alertData['alertDistanceMeters'].toDouble();
        final passengerLat = alertData['passengerLat'].toDouble();
        final passengerLng = alertData['passengerLng'].toDouble();
        final bool isInside = (alertData['isInside'] ?? false) == true;
        final double hysteresis = 30.0;
        final distance = Geolocator.distanceBetween(
          driverLat,
          driverLng,
          passengerLat,
          passengerLng,
        );
        if (distance <= alertDistance && (!isInside)) {
          await alertDoc.reference.update({
            'isInside': true,
            'triggeredAt': FieldValue.serverTimestamp(),
            'actualDistance': distance,
            'lastChecked': FieldValue.serverTimestamp(),
          });
        } else if (distance > (alertDistance + hysteresis) && isInside) {
          await alertDoc.reference.update({
            'isInside': false,
            'lastChecked': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('❌ Mesafe uyarısı kontrolü hatası: $e');
    }
  }
  static Future<Map<String, dynamic>?> getActiveDistanceAlert(
      String passengerId) async {
    try {
      final doc =
          await _firestore.collection('distance_alerts').doc(passengerId).get();
      if (doc.exists && doc.data()!['isActive'] == true) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Mesafe uyarısı alma hatası: $e');
      return null;
    }
  }
  Future<bool> isDistanceAlertActive(String passengerId) async {
    try {
      final doc =
          await _firestore.collection('distance_alerts').doc(passengerId).get();
      return doc.exists && doc.data()!['isActive'] == true;
    } catch (e) {
      print('❌ Mesafe uyarısı durumu kontrol hatası: $e');
      return false;
    }
  }
  Future<void> disableDistanceAlert(String passengerId) async {
    try {
      await _firestore.collection('distance_alerts').doc(passengerId).update({
        'isActive': false,
        'disabledAt': FieldValue.serverTimestamp(),
      });
      print('🔕 Mesafe uyarısı devre dışı bırakıldı');
    } catch (e) {
      print('❌ Mesafe uyarısı devre dışı bırakma hatası: $e');
    }
  }
  Future<void> enableDistanceAlert(String passengerId, double distance) async {
    try {
      final ref = _firestore.collection('distance_alerts').doc(passengerId);
      final snap = await ref.get();
      double? lat;
      double? lng;
      String? regionId = UserSession.regionId;
      if (!snap.exists) {
        try {
          final stopSnap = await _firestore
              .collection('enhanced_stops')
              .where('isActive', isEqualTo: true)
              .where('passengerIds', arrayContains: passengerId)
              .limit(1)
              .get();
          if (stopSnap.docs.isNotEmpty) {
            final d = stopSnap.docs.first.data();
            lat = (d['latitude'] ?? d['lat'])?.toDouble();
            lng = (d['longitude'] ?? d['lng'])?.toDouble();
            regionId = (d['regionId'] as String?) ?? regionId;
          }
        } catch (_) {}
        if (lat == null || lng == null) {
          try {
            final pos = await Geolocator.getCurrentPosition();
            lat = pos.latitude;
            lng = pos.longitude;
          } catch (_) {}
        }
        await ref.set({
          'passengerId': passengerId,
          'regionId': regionId ?? '',
          'alertDistanceMeters': distance,
          if (lat != null) 'passengerLat': lat,
          if (lng != null) 'passengerLng': lng,
          'isActive': true,
          'repeat': true,
          'isInside': false,
          'createdAt': FieldValue.serverTimestamp(),
          'lastChecked': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print('🔔 Mesafe uyarısı oluşturuldu: ${distance}m');
      } else {
        await ref.update({
          'isActive': true,
          'alertDistanceMeters': distance,
          'repeat': true,
          'isInside': false,
          'enabledAt': FieldValue.serverTimestamp(),
        });
        print('🔔 Mesafe uyarısı etkinleştirildi: ${distance}m');
      }
    } catch (e) {
      print('❌ Mesafe uyarısı etkinleştirme hatası: $e');
    }
  }
}

// Updated

