import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import 'route_optimization_service.dart';
class ArrivalTimeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final RouteOptimizationService _routeService = RouteOptimizationService();
  static Future<Map<String, dynamic>?> calculateArrivalTime({
    required String passengerId,
    required String driverId,
  }) async {
    try {
      final driverLocationDoc = await _firestore
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (!driverLocationDoc.exists) {
        return null;
      }
      final driverData = driverLocationDoc.data()!;
      final driverPosition = Position(
        latitude: driverData['lat'],
        longitude: driverData['lng'],
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final stopsQuery = await _firestore
          .collection('stops')
          .where('assignedPassengerIds', arrayContains: passengerId)
          .limit(1)
          .get();
      if (stopsQuery.docs.isEmpty) {
        return null;
      }
      final stopDoc = stopsQuery.docs.first;
      final stopData = stopDoc.data();
      final passengerStop = StopModel(
        id: stopDoc.id,
        driverId: driverId,
        passengerName: stopData['name'] ?? 'Durak',
        address: stopData['address'] ?? '',
        lat: stopData['latitude'] ?? 0.0,
        lng: stopData['longitude'] ?? 0.0,
        date: DateTime.now(),
        order: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        passengerIds: List<String>.from(stopData['assignedPassengerIds'] ?? []),
      );
      final allStopsQuery = await _firestore
          .collection('stops')
          .where('driverId', isEqualTo: driverId)
          .get();
      final allStops = allStopsQuery.docs.map((doc) {
        final data = doc.data();
        return StopModel(
          id: doc.id,
          driverId: driverId,
          passengerName: data['name'] ?? 'Durak',
          address: data['address'] ?? '',
          lat: data['latitude'] ?? 0.0,
          lng: data['longitude'] ?? 0.0,
          date: DateTime.now(),
          order: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          passengerIds: List<String>.from(data['assignedPassengerIds'] ?? []),
        );
      }).toList();
      final optimizedStops = await _routeService.optimizeRouteFromCurrentLocation(
        driverPosition,
        allStops,
      );
      int passengerStopIndex = -1;
      for (int i = 0; i < optimizedStops.length; i++) {
        if (optimizedStops[i].id == passengerStop.id) {
          passengerStopIndex = i;
          break;
        }
      }
      if (passengerStopIndex == -1) {
        return null;
      }
      int estimatedMinutes = 0;
      estimatedMinutes += 5;
      for (int i = 0; i <= passengerStopIndex; i++) {
        estimatedMinutes += 3;
        if (i < passengerStopIndex) {
          estimatedMinutes += 4;
        }
      }
      if (driverData['speed'] != null && driverData['speed'] > 0) {
        estimatedMinutes = (estimatedMinutes * 0.8).round();
      }
      final arrivalTime = DateTime.now().add(Duration(minutes: estimatedMinutes));
      return {
        'estimatedMinutes': estimatedMinutes,
        'arrivalTime': arrivalTime,
        'stopName': passengerStop.passengerName,
        'stopAddress': passengerStop.address,
        'stopOrder': passengerStopIndex + 1,
        'totalStops': optimizedStops.length,
        'driverDistance': _calculateDistance(
          driverPosition.latitude,
          driverPosition.longitude,
          passengerStop.lat,
          passengerStop.lng,
        ),
      };
    } catch (e) {
      print('Varış süresi hesaplama hatası: $e');
      return null;
    }
  }
  static Future<bool> isDriverActive(String driverId) async {
    try {
      final driverLocationDoc = await _firestore
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (!driverLocationDoc.exists) {
        return false;
      }
      final data = driverLocationDoc.data()!;
      final lastUpdate = (data['timestamp'] as Timestamp?)?.toDate();
      if (lastUpdate == null) {
        return false;
      }
      final now = DateTime.now();
      final difference = now.difference(lastUpdate).inMinutes;
      return difference <= 5;
    } catch (e) {
      print('Şoför aktiflik kontrolü hatası: $e');
      return false;
    }
  }
  static Stream<Map<String, dynamic>?> getArrivalTimeStream({
    required String passengerId,
    required String driverId,
  }) {
    return Stream.periodic(const Duration(seconds: 30), (count) async {
      return await calculateArrivalTime(
        passengerId: passengerId,
        driverId: driverId,
      );
    }).asyncMap((future) => future);
  }
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
}
