import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import 'route_optimization_service.dart';
class RouteService {
  static final RouteService _instance = RouteService._internal();
  factory RouteService() => _instance;
  RouteService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RouteOptimizationService _optimizationService = RouteOptimizationService();
  Future<String?> createRoute({
    required String driverId,
    required Position startPosition,
    required List<StopModel> stops,
    String? regionId,
  }) async {
    try {
      final optimizedStops = await _optimizationService.optimizeRouteFromCurrentLocation(
        startPosition,
        stops,
      );
      final routeData = {
        'driverId': driverId,
        'regionId': regionId,
        'startPosition': {
          'lat': startPosition.latitude,
          'lng': startPosition.longitude,
        },
        'stops': optimizedStops.map((stop) => {
          'id': stop.id,
          'name': stop.name,
          'address': stop.address,
          'lat': stop.lat,
          'lng': stop.lng,
          'passengerCount': stop.passengerCount,
          'isCompleted': false,
          'completedAt': null,
        }).toList(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'totalDistance': 0.0,
        'estimatedDuration': 0,
      };
      final docRef = await _firestore.collection('routes').add(routeData);
      return docRef.id;
    } catch (e) {
      print('Rota oluşturma hatası: $e');
      return null;
    }
  }
  Future<String?> createRouteLog({
    required String routeId,
    required String driverId,
    required Position startLocation,
    required List<StopModel> plannedStops,
  }) async {
    try {
      final docRef = await _firestore.collection('route_logs').add({
        'routeId': routeId,
        'driverId': driverId,
        'startLocation': {
          'lat': startLocation.latitude,
          'lng': startLocation.longitude,
        },
        'plannedStops': plannedStops.map((stop) => stop.toMap()).toList(),
        'startTime': FieldValue.serverTimestamp(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      print('Rota log oluşturma hatası: $e');
      return null;
    }
  }
  Future<bool> completeStop({
    required String routeId,
    required String stopId,
    DateTime? completedAt,
  }) async {
    try {
      final routeRef = _firestore.collection('routes').doc(routeId);
      final routeDoc = await routeRef.get();
      if (!routeDoc.exists) return false;
      final routeData = routeDoc.data()!;
      final stops = List<Map<String, dynamic>>.from(routeData['stops'] ?? []);
      int completedStopIndex = -1;
      for (int i = 0; i < stops.length; i++) {
        if (stops[i]['id'] == stopId) {
          stops[i]['isCompleted'] = true;
          stops[i]['completedAt'] = completedAt ?? FieldValue.serverTimestamp();
          completedStopIndex = i;
          break;
        }
      }
      final completedCount = stops.where((stop) => stop['isCompleted'] == true).length;
      final totalStops = stops.length;
      String routeStatus = 'active';
      if (completedCount == totalStops) {
        routeStatus = 'completed';
      }
      await routeRef.update({
        'stops': stops,
        'status': routeStatus,
        'completedStops': completedCount,
        'totalStops': totalStops,
        'updatedAt': FieldValue.serverTimestamp(),
        if (routeStatus == 'completed') 'completedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('stop_logs').add({
        'routeId': routeId,
        'stopId': stopId,
        'driverId': routeData['driverId'],
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'completion',
        'stopIndex': completedStopIndex,
        'completedCount': completedCount,
        'totalStops': totalStops,
      });
      print('✅ Durak tamamlandı: $stopId ($completedCount/$totalStops)');
      return true;
    } catch (e) {
      print('Durak tamamlama hatası: $e');
      return false;
    }
  }
  Future<Map<String, dynamic>?> getNextIncompleteStop(String routeId) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) return null;
      final routeData = routeDoc.data()!;
      final stops = List<Map<String, dynamic>>.from(routeData['stops'] ?? []);
      for (final stop in stops) {
        if (stop['isCompleted'] != true) {
          return stop;
        }
      }
      return null;
    } catch (e) {
      print('Sıradaki durak getirme hatası: $e');
      return null;
    }
  }
  Future<List<Map<String, dynamic>>> getIncompleteStops(String routeId) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) return [];
      final routeData = routeDoc.data()!;
      final stops = List<Map<String, dynamic>>.from(routeData['stops'] ?? []);
      return stops.where((stop) => stop['isCompleted'] != true).toList();
    } catch (e) {
      print('Tamamlanmamış durakları getirme hatası: $e');
      return [];
    }
  }
  Future<void> _createStopLog({
    required String routeId,
    required String stopId,
    required String driverId,
    required Position position,
  }) async {
    try {
      await _firestore.collection('stop_logs').add({
        'routeId': routeId,
        'stopId': stopId,
        'driverId': driverId,
        'position': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'arrival',
      });
    } catch (e) {
      print('Stop log oluşturma hatası: $e');
    }
  }
  Future<Map<String, dynamic>?> getActiveRoute(String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
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
  Future<bool> completeRoute({
    required String routeId,
    Position? endLocation,
  }) async {
    try {
      final updateData = {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (endLocation != null) {
        updateData['endLocation'] = {
          'lat': endLocation.latitude,
          'lng': endLocation.longitude,
        };
      }
      await _firestore.collection('routes').doc(routeId).update(updateData);
      return true;
    } catch (e) {
      print('Rota tamamlama hatası: $e');
      return false;
    }
  }
  Future<bool> cancelRoute(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Rota iptal etme hatası: $e');
      return false;
    }
  }
  Stream<QuerySnapshot> getRouteHistory(String driverId) {
    return _firestore
        .collection('routes')
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
  Stream<QuerySnapshot> getStopLogs(String routeId) {
    return _firestore
        .collection('stop_logs')
        .where('routeId', isEqualTo: routeId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}



 Again


