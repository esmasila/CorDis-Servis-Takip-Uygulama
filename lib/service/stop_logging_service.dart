import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
class StopLoggingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Future<String?> logStopArrival({
    required String driverId,
    required String stopId,
    required String routeId,
    required Position driverPosition,
    required StopModel stop,
    List<String>? passengerIds,
  }) async {
    try {
      final logData = {
        'driverId': driverId,
        'stopId': stopId,
        'routeId': routeId,
        'stopName': stop.name,
        'stopAddress': stop.address,
        'stopCoordinates': {
          'lat': stop.lat,
          'lng': stop.lng,
        },
        'driverPosition': {
          'lat': driverPosition.latitude,
          'lng': driverPosition.longitude,
        },
        'passengerIds': passengerIds ?? [],
        'passengerCount': passengerIds?.length ?? 0,
        'arrivalTime': FieldValue.serverTimestamp(),
        'status': 'arrived',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final docRef = await _firestore
          .collection('stop_logs')
          .add(logData);
      await _updateStopStatus(stopId, 'visited');
      return docRef.id;
    } catch (e) {
      print('Durak varış kaydı hatası: $e');
      return null;
    }
  }
  Future<bool> logStopDeparture({
    required String logId,
    required Position driverPosition,
  }) async {
    try {
      await _firestore
          .collection('stop_logs')
          .doc(logId)
          .update({
        'departureTime': FieldValue.serverTimestamp(),
        'departurePosition': {
          'lat': driverPosition.latitude,
          'lng': driverPosition.longitude,
        },
        'status': 'departed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Durak ayrılış kaydı hatası: $e');
      return false;
    }
  }
  Future<String?> logRouteStart({
    required String driverId,
    required String routeId,
    required Position startPosition,
    required List<StopModel> plannedStops,
  }) async {
    try {
      final routeLogData = {
        'driverId': driverId,
        'routeId': routeId,
        'startPosition': {
          'lat': startPosition.latitude,
          'lng': startPosition.longitude,
        },
        'plannedStops': plannedStops.map((stop) => {
          'stopId': stop.id,
          'name': stop.name,
          'address': stop.address,
          'coordinates': {
            'lat': stop.lat,
            'lng': stop.lng,
          },
          'passengerCount': stop.passengerIds?.length ?? 0,
        }).toList(),
        'totalStops': plannedStops.length,
        'startTime': FieldValue.serverTimestamp(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final docRef = await _firestore
          .collection('route_logs')
          .add(routeLogData);
      return docRef.id;
    } catch (e) {
      print('Rota başlangıç kaydı hatası: $e');
      return null;
    }
  }
  Future<bool> logRouteEnd({
    required String routeLogId,
    required Position endPosition,
  }) async {
    try {
      await _firestore
          .collection('route_logs')
          .doc(routeLogId)
          .update({
        'endPosition': {
          'lat': endPosition.latitude,
          'lng': endPosition.longitude,
        },
        'endTime': FieldValue.serverTimestamp(),
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Rota bitiş kaydı hatası: $e');
      return false;
    }
  }
  Stream<QuerySnapshot> getDriverStopLogs(String driverId) {
    return _firestore
        .collection('stop_logs')
        .where('driverId', isEqualTo: driverId)
        .orderBy('arrivalTime', descending: true)
        .snapshots();
  }
  Stream<QuerySnapshot> getAllStopLogs() {
    return _firestore
        .collection('stop_logs')
        .orderBy('arrivalTime', descending: true)
        .snapshots();
  }
  Stream<QuerySnapshot> getDriverRouteLogs(String driverId) {
    return _firestore
        .collection('route_logs')
        .where('driverId', isEqualTo: driverId)
        .orderBy('startTime', descending: true)
        .snapshots();
  }
  Stream<QuerySnapshot> getAllRouteLogs() {
    return _firestore
        .collection('route_logs')
        .orderBy('startTime', descending: true)
        .snapshots();
  }
  Future<QuerySnapshot> getLogsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? driverId,
  }) async {
    Query query = _firestore.collection('stop_logs');
    if (driverId != null) {
      query = query.where('driverId', isEqualTo: driverId);
    }
    query = query
        .where('arrivalTime', isGreaterThanOrEqualTo: startDate)
        .where('arrivalTime', isLessThanOrEqualTo: endDate)
        .orderBy('arrivalTime', descending: true);
    return await query.get();
  }
  Future<Map<String, dynamic>> getStopStatistics(String driverId) async {
    try {
      final snapshot = await _firestore
          .collection('stop_logs')
          .where('driverId', isEqualTo: driverId)
          .get();
      final totalStops = snapshot.docs.length;
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayStops = snapshot.docs.where((doc) {
        final arrivalTime = (doc.data()['arrivalTime'] as Timestamp?)?.toDate();
        return arrivalTime != null && arrivalTime.isAfter(todayStart);
      }).length;
      final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
      final weekStops = snapshot.docs.where((doc) {
        final arrivalTime = (doc.data()['arrivalTime'] as Timestamp?)?.toDate();
        return arrivalTime != null && arrivalTime.isAfter(thisWeekStart);
      }).length;
      return {
        'totalStops': totalStops,
        'todayStops': todayStops,
        'weekStops': weekStops,
        'averageStopsPerDay': totalStops > 0 ? (totalStops / 30).round() : 0,
      };
    } catch (e) {
      print('İstatistik hesaplama hatası: $e');
      return {
        'totalStops': 0,
        'todayStops': 0,
        'weekStops': 0,
        'averageStopsPerDay': 0,
      };
    }
  }
  Future<void> _updateStopStatus(String stopId, String status) async {
    try {
      await _firestore
          .collection('stops')
          .doc(stopId)
          .update({
        'status': status,
        'lastVisited': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Durak durumu güncelleme hatası: $e');
    }
  }
  bool isNearStop(Position currentPosition, StopModel stop, {double radiusInMeters = 50.0}) {
    final distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      stop.lat,
      stop.lng,
    );
    return distance <= radiusInMeters;
  }
  Future<String?> checkAndLogStopArrival({
    required String driverId,
    required String routeId,
    required Position currentPosition,
    required List<StopModel> remainingStops,
  }) async {
    for (final stop in remainingStops) {
      if (isNearStop(currentPosition, stop)) {
        return await logStopArrival(
          driverId: driverId,
          stopId: stop.id!,
          routeId: routeId,
          driverPosition: currentPosition,
          stop: stop,
          passengerIds: stop.passengerIds,
        );
      }
    }
    return null;
  }
}





