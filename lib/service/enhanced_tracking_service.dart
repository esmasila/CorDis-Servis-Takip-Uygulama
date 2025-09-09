import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import '../service/user_session.dart';
import 'enhanced_route_service.dart';
import 'distance_notification_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
class EnhancedTrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Stream<Map<String, dynamic>> getServiceStatus({
    required String regionId,
    required String passengerId,
  }) async* {
    yield* _firestore
        .collection('service_status')
        .doc(regionId)
        .snapshots()
        .asyncMap((doc) async {
      if (!doc.exists) {
        return {
          'status': 'inactive',
          'message': 'Servis aktif değil',
          'currentStop': null,
          'nextStop': null,
          'estimatedArrival': null,
        };
      }
      final data = doc.data()!;
      final driverId = data['driverId'];
      if (driverId == null) {
        return {
          'status': 'no_driver',
          'message': 'Şoför atanmamış',
          'currentStop': null,
          'nextStop': null,
          'estimatedArrival': null,
        };
      }
      final currentStop = await EnhancedRouteService.getCurrentStop(driverId, regionId);
      final nextStop = await EnhancedRouteService.getNextStop(driverId, regionId);
      final estimatedArrival = await _calculateEstimatedArrival(
        driverId: driverId,
        passengerId: passengerId,
        regionId: regionId,
      );
      return {
        'status': 'active',
        'message': 'Servis aktif',
        'driverId': driverId,
        'driverName': data['driverName'],
        'vehiclePlate': data['vehiclePlate'],
        'currentStop': currentStop?.toJson(),
        'nextStop': nextStop?.toJson(),
        'estimatedArrival': estimatedArrival,
        'lastUpdate': data['lastUpdate'],
      };
    });
  }
  static Future<Map<String, dynamic>?> _calculateEstimatedArrival({
    required String driverId,
    required String passengerId,
    required String regionId,
  }) async {
    try {
      final driverLocationDoc = await _firestore
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (!driverLocationDoc.exists) return null;
      final driverLocation = driverLocationDoc.data()!;
      final driverLat = driverLocation['lat'].toDouble();
      final driverLng = driverLocation['lng'].toDouble();
      final passengerStopSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (passengerStopSnapshot.docs.isEmpty) return null;
      final stopData = passengerStopSnapshot.docs.first.data();
      final stopLat = stopData['latitude'].toDouble();
      final stopLng = stopData['longitude'].toDouble();
      final distance = Geolocator.distanceBetween(driverLat, driverLng, stopLat, stopLng);
      const averageSpeedKmh = 30.0;
      const averageSpeedMs = averageSpeedKmh * 1000 / 3600;
      final estimatedTimeSeconds = (distance / averageSpeedMs).round();
      final estimatedTimeMinutes = (estimatedTimeSeconds / 60).round();
      return {
        'distanceMeters': distance.round(),
        'estimatedTimeMinutes': estimatedTimeMinutes,
        'estimatedTimeSeconds': estimatedTimeSeconds,
        'stopAddress': stopData['address'],
        'stopLat': stopLat,
        'stopLng': stopLng,
      };
    } catch (e) {
      print('❌ Tahmini varış hesaplama hatası: $e');
      return null;
    }
  }
  static Future<void> updateServiceStatus({
    required String regionId,
    required String driverId,
    required String driverName,
    required String vehiclePlate,
    required double currentLat,
    required double currentLng,
  }) async {
    try {
      await _firestore.collection('service_status').doc(regionId).set({
        'driverId': driverId,
        'driverName': driverName,
        'vehiclePlate': vehiclePlate,
        'currentLat': currentLat,
        'currentLng': currentLng,
        'lastUpdate': FieldValue.serverTimestamp(),
        'isActive': true,
      }, SetOptions(merge: true));
      await DistanceNotificationService.checkDistanceAlerts(
        driverId: driverId,
        regionId: regionId,
        driverLat: currentLat,
        driverLng: currentLng,
      );
    } catch (e) {
      print('❌ Servis durumu güncelleme hatası: $e');
    }
  }
  static Future<void> deactivateService(String regionId) async {
    try {
      await _firestore.collection('service_status').doc(regionId).update({
        'isActive': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Servis deaktivasyonu hatası: $e');
    }
  }
  static Future<String?> getPassengerProfilePhoto(String passengerId) async {
    try {
      final doc = await _firestore.collection('users').doc(passengerId).get();
      if (doc.exists) {
        return doc.data()?['profilePhotoUrl'];
      }
      return null;
    } catch (e) {
      print('❌ Profil fotoğrafı alma hatası: $e');
      return null;
    }
  }
  static Future<List<Map<String, dynamic>>> getStopPassengerProfiles(String stopId) async {
    try {
      final stopDoc = await _firestore.collection('enhanced_stops').doc(stopId).get();
      if (!stopDoc.exists) return [];
      final stopData = stopDoc.data()!;
      final passengerIds = List<String>.from(stopData['passengerIds'] ?? []);
      final passengerNames = List<String>.from(stopData['passengerNames'] ?? []);
      List<Map<String, dynamic>> profiles = [];
      for (int i = 0; i < passengerIds.length; i++) {
        final passengerId = passengerIds[i];
        final passengerName = i < passengerNames.length ? passengerNames[i] : 'Bilinmeyen';
        final profilePhoto = await getPassengerProfilePhoto(passengerId);
        profiles.add({
          'id': passengerId,
          'name': passengerName,
          'profilePhotoUrl': profilePhoto,
        });
      }
      return profiles;
    } catch (e) {
      print('❌ Durak profilleri alma hatası: $e');
      return [];
    }
  }
  static Future<Map<String, dynamic>?> getServiceStatusForPassenger(
    String passengerId,
    String regionId,
  ) async {
    try {
      final doc = await _firestore.collection('service_status').doc(regionId).get();
      if (!doc.exists) {
        return {
          'isActive': false,
          'message': 'Servis aktif değil',
          'currentStop': null,
          'nextStop': null,
          'estimatedArrival': null,
        };
      }
      final data = doc.data()!;
      final driverId = data['driverId'];
      if (driverId == null) {
        return {
          'isActive': false,
          'message': 'Şoför atanmamış',
          'currentStop': null,
          'nextStop': null,
          'estimatedArrival': null,
        };
      }
      final driverLocationDoc = await _firestore
          .collection('live_locations')
          .doc(driverId)
          .get();
      Map<String, dynamic>? driverLocation;
      if (driverLocationDoc.exists) {
        final locationData = driverLocationDoc.data()!;
        driverLocation = {
          'latitude': locationData['lat'],
          'longitude': locationData['lng'],
          'timestamp': locationData['timestamp'],
        };
      }
      final currentStop = await EnhancedRouteService.getCurrentStop(driverId, regionId);
      final nextStop = await EnhancedRouteService.getNextStop(driverId, regionId);
      final estimatedArrival = await _calculateEstimatedArrival(
        driverId: driverId,
        passengerId: passengerId,
        regionId: regionId,
      );
      return {
        'isActive': data['isActive'] ?? false,
        'message': 'Servis aktif',
        'driverId': driverId,
        'driverName': data['driverName'],
        'vehiclePlate': data['vehiclePlate'],
        'driverLocation': driverLocation,
        'currentStop': currentStop?.toJson(),
        'nextStop': nextStop?.toJson(),
        'estimatedArrival': estimatedArrival,
        'lastUpdate': data['lastUpdate'],
      };
    } catch (e) {
      print('❌ Servis durumu alma hatası: $e');
      return null;
    }
  }
  static Future<double?> calculateEstimatedArrival(
    LatLng driverLocation,
    LatLng passengerLocation,
  ) async {
    try {
      final distance = Geolocator.distanceBetween(
        driverLocation.latitude,
        driverLocation.longitude,
        passengerLocation.latitude,
        passengerLocation.longitude,
      );
      const averageSpeedKmh = 30.0;
      const averageSpeedMs = averageSpeedKmh * 1000 / 3600;
      final estimatedTimeSeconds = distance / averageSpeedMs;
      final estimatedTimeMinutes = estimatedTimeSeconds / 60;
      return estimatedTimeMinutes;
    } catch (e) {
      print('❌ Tahmini varış hesaplama hatası: $e');
      return null;
    }
  }
}

// Updated

