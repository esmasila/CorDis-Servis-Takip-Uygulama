import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
class RouteHistoryService {
  static final Map<String, StreamSubscription> _trackingSubscriptions = {};
  static final Map<String, List<RouteHistoryEntry>> _cachedHistory = {};
  static Future<void> recordStopVisit({
    required String driverId,
    required String stopId,
    required String passengerId,
    required LatLng stopLocation,
    required LatLng actualLocation,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final distanceFromStop = Geolocator.distanceBetween(
        stopLocation.latitude,
        stopLocation.longitude,
        actualLocation.latitude,
        actualLocation.longitude,
      );
      final historyEntry = RouteHistoryEntry(
        id: '',
        driverId: driverId,
        stopId: stopId,
        passengerId: passengerId,
        visitedAt: DateTime.now(),
        stopLocation: stopLocation,
        actualLocation: actualLocation,
        distanceFromStop: distanceFromStop,
        additionalData: additionalData ?? {},
      );
      final docRef = await FirebaseFirestore.instance
          .collection('route_history')
          .add(historyEntry.toMap());
      final updatedEntry = historyEntry.copyWith(id: docRef.id);
      _addToCache(driverId, updatedEntry);
      print('Durak ziyareti kaydedildi: $stopId');
      await _updateStopStatus(stopId, 'visited');
    } catch (e) {
      print('Durak ziyareti kaydetme hatası: $e');
      rethrow;
    }
  }
  static void startRouteTracking(String driverId) {
    stopRouteTracking(driverId);
    print('Rota takibi başlatılıyor: $driverId');
    _trackingSubscriptions[driverId] = FirebaseFirestore.instance
        .collection('live_locations')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final driverLocation = LatLng(
          data['latitude'],
          data['longitude'],
        );
        _checkNearbyStops(driverId, driverLocation);
      }
    });
  }
  static void stopRouteTracking(String driverId) {
    _trackingSubscriptions[driverId]?.cancel();
    _trackingSubscriptions.remove(driverId);
    print('Rota takibi durduruldu: $driverId');
  }
  static Future<void> _checkNearbyStops(
    String driverId,
    LatLng driverLocation,
  ) async {
    try {
      final stopsQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .where('status', whereIn: ['pending', 'approaching'])
          .get();
      for (final stopDoc in stopsQuery.docs) {
        final stopData = stopDoc.data();
        final stopLocation = LatLng(
          stopData['latitude'],
          stopData['longitude'],
        );
        final distance = Geolocator.distanceBetween(
          driverLocation.latitude,
          driverLocation.longitude,
          stopLocation.latitude,
          stopLocation.longitude,
        );
        if (distance <= 50) {
          await _handleStopApproach(
            driverId,
            stopDoc.id,
            stopData,
            driverLocation,
            distance,
          );
        }
        else if (distance <= 100 && stopData['status'] != 'approaching') {
          await _updateStopStatus(stopDoc.id, 'approaching');
        }
      }
    } catch (e) {
      print('Yakın durak kontrolü hatası: $e');
    }
  }
  static Future<void> _handleStopApproach(
    String driverId,
    String stopId,
    Map<String, dynamic> stopData,
    LatLng driverLocation,
    double distance,
  ) async {
    try {
      final existingVisit = await FirebaseFirestore.instance
          .collection('route_history')
          .where('driverId', isEqualTo: driverId)
          .where('stopId', isEqualTo: stopId)
          .where('visitedAt', isGreaterThan: 
              Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))))
          .limit(1)
          .get();
      if (existingVisit.docs.isNotEmpty) {
        return;
      }
      await recordStopVisit(
        driverId: driverId,
        stopId: stopId,
        passengerId: stopData['passengerId'],
        stopLocation: LatLng(
          stopData['latitude'],
          stopData['longitude'],
        ),
        actualLocation: driverLocation,
        additionalData: {
          'autoDetected': true,
          'detectionDistance': distance,
          'stopOrder': stopData['order'],
        },
      );
      print('Otomatik durak ziyareti kaydedildi: $stopId');
    } catch (e) {
      print('Durak yaklaşma işleme hatası: $e');
    }
  }
  static Future<void> _updateStopStatus(
    String stopId,
    String status,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .doc(stopId)
          .update({
        'status': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Durak durumu güncelleme hatası: $e');
    }
  }
  static Future<List<RouteHistoryEntry>> getRouteHistory({
    required String driverId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('route_history')
          .where('driverId', isEqualTo: driverId)
          .orderBy('visitedAt', descending: true)
          .limit(limit);
      if (startDate != null) {
        query = query.where('visitedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('visitedAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      final querySnapshot = await query.get();
      final history = querySnapshot.docs
          .map((doc) => RouteHistoryEntry.fromFirestore(doc))
          .toList();
      _cachedHistory[driverId] = history;
      return history;
    } catch (e) {
      print('Rota geçmişi getirme hatası: $e');
      return _cachedHistory[driverId] ?? [];
    }
  }
  static Future<List<RouteHistoryEntry>> getPassengerHistory({
    required String passengerId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('route_history')
          .where('passengerId', isEqualTo: passengerId)
          .orderBy('visitedAt', descending: true)
          .limit(limit);
      if (startDate != null) {
        query = query.where('visitedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('visitedAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      final querySnapshot = await query.get();
      return querySnapshot.docs
          .map((doc) => RouteHistoryEntry.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Yolcu geçmişi getirme hatası: $e');
      return [];
    }
  }
  static Future<RouteSummary> getDailySummary({
    required String driverId,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    try {
      final history = await getRouteHistory(
        driverId: driverId,
        startDate: startOfDay,
        endDate: endOfDay,
      );
      return RouteSummary.fromHistory(history, targetDate);
    } catch (e) {
      print('Günlük özet getirme hatası: $e');
      return RouteSummary.empty(targetDate);
    }
  }
  static Stream<List<RouteHistoryEntry>> getRealtimeRouteHistory(
    String driverId,
  ) {
    return FirebaseFirestore.instance
        .collection('route_history')
        .where('driverId', isEqualTo: driverId)
        .where('visitedAt', isGreaterThan: 
            Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 12))))
        .orderBy('visitedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RouteHistoryEntry.fromFirestore(doc))
            .toList());
  }
  static void _addToCache(String driverId, RouteHistoryEntry entry) {
    if (!_cachedHistory.containsKey(driverId)) {
      _cachedHistory[driverId] = [];
    }
    _cachedHistory[driverId]!.insert(0, entry);
    if (_cachedHistory[driverId]!.length > 100) {
      _cachedHistory[driverId] = _cachedHistory[driverId]!.take(100).toList();
    }
  }
  static Future<void> cleanupOldHistory() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      final oldHistoryQuery = await FirebaseFirestore.instance
          .collection('route_history')
          .where('visitedAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in oldHistoryQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Eski geçmiş verileri temizlendi: ${oldHistoryQuery.docs.length} kayıt');
    } catch (e) {
      print('Geçmiş veri temizleme hatası: $e');
    }
  }
  static Stream<List<Map<String, dynamic>>> getRouteHistoryStream(
    String passengerId,
  ) {
    return FirebaseFirestore.instance
        .collection('route_history')
        .where('passengerId', isEqualTo: passengerId)
        .orderBy('visitedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'stopId': data['stopId'],
            'visitedAt': data['visitedAt'],
            'distanceFromStop': data['distanceFromStop'],
            'additionalData': data['additionalData'] ?? {},
            'status': 'completed',
          };
        }).toList());
  }
  static void stopAllTracking() {
    for (final subscription in _trackingSubscriptions.values) {
      subscription.cancel();
    }
    _trackingSubscriptions.clear();
    _cachedHistory.clear();
  }
}
class RouteHistoryEntry {
  final String id;
  final String driverId;
  final String stopId;
  final String passengerId;
  final DateTime visitedAt;
  final LatLng stopLocation;
  final LatLng actualLocation;
  final double distanceFromStop;
  final Map<String, dynamic> additionalData;
  RouteHistoryEntry({
    required this.id,
    required this.driverId,
    required this.stopId,
    required this.passengerId,
    required this.visitedAt,
    required this.stopLocation,
    required this.actualLocation,
    required this.distanceFromStop,
    required this.additionalData,
  });
  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'stopId': stopId,
      'passengerId': passengerId,
      'visitedAt': Timestamp.fromDate(visitedAt),
      'stopLocation': GeoPoint(stopLocation.latitude, stopLocation.longitude),
      'actualLocation': GeoPoint(actualLocation.latitude, actualLocation.longitude),
      'distanceFromStop': distanceFromStop,
      'additionalData': additionalData,
    };
  }
  factory RouteHistoryEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final stopGeoPoint = data['stopLocation'] as GeoPoint;
    final actualGeoPoint = data['actualLocation'] as GeoPoint;
    return RouteHistoryEntry(
      id: doc.id,
      driverId: data['driverId'],
      stopId: data['stopId'],
      passengerId: data['passengerId'],
      visitedAt: (data['visitedAt'] as Timestamp).toDate(),
      stopLocation: LatLng(stopGeoPoint.latitude, stopGeoPoint.longitude),
      actualLocation: LatLng(actualGeoPoint.latitude, actualGeoPoint.longitude),
      distanceFromStop: data['distanceFromStop']?.toDouble() ?? 0.0,
      additionalData: Map<String, dynamic>.from(data['additionalData'] ?? {}),
    );
  }
  RouteHistoryEntry copyWith({
    String? id,
    String? driverId,
    String? stopId,
    String? passengerId,
    DateTime? visitedAt,
    LatLng? stopLocation,
    LatLng? actualLocation,
    double? distanceFromStop,
    Map<String, dynamic>? additionalData,
  }) {
    return RouteHistoryEntry(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      stopId: stopId ?? this.stopId,
      passengerId: passengerId ?? this.passengerId,
      visitedAt: visitedAt ?? this.visitedAt,
      stopLocation: stopLocation ?? this.stopLocation,
      actualLocation: actualLocation ?? this.actualLocation,
      distanceFromStop: distanceFromStop ?? this.distanceFromStop,
      additionalData: additionalData ?? this.additionalData,
    );
  }
  @override
  String toString() {
    return 'RouteHistoryEntry(id: $id, stopId: $stopId, visitedAt: $visitedAt)';
  }
}
class RouteSummary {
  final DateTime date;
  final int totalStops;
  final int visitedStops;
  final double totalDistance;
  final Duration totalTime;
  final List<RouteHistoryEntry> entries;
  RouteSummary({
    required this.date,
    required this.totalStops,
    required this.visitedStops,
    required this.totalDistance,
    required this.totalTime,
    required this.entries,
  });
  factory RouteSummary.fromHistory(
    List<RouteHistoryEntry> history,
    DateTime date,
  ) {
    if (history.isEmpty) {
      return RouteSummary.empty(date);
    }
    double totalDistance = 0.0;
    for (int i = 0; i < history.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        history[i].actualLocation.latitude,
        history[i].actualLocation.longitude,
        history[i + 1].actualLocation.latitude,
        history[i + 1].actualLocation.longitude,
      );
    }
    final firstEntry = history.last;
    final lastEntry = history.first;
    final totalTime = lastEntry.visitedAt.difference(firstEntry.visitedAt);
    return RouteSummary(
      date: date,
      totalStops: history.length,
      visitedStops: history.length,
      totalDistance: totalDistance,
      totalTime: totalTime,
      entries: history,
    );
  }
  factory RouteSummary.empty(DateTime date) {
    return RouteSummary(
      date: date,
      totalStops: 0,
      visitedStops: 0,
      totalDistance: 0.0,
      totalTime: Duration.zero,
      entries: [],
    );
  }
  double get completionRate {
    if (totalStops == 0) return 0.0;
    return visitedStops / totalStops;
  }
  String get formattedDistance {
    if (totalDistance < 1000) {
      return '${totalDistance.round()} m';
    } else {
      return '${(totalDistance / 1000).toStringAsFixed(1)} km';
    }
  }
  String get formattedTime {
    final hours = totalTime.inHours;
    final minutes = totalTime.inMinutes % 60;
    if (hours > 0) {
      return '${hours}s ${minutes}dk';
    } else {
      return '${minutes}dk';
    }
  }
  @override
  String toString() {
    return 'RouteSummary(date: $date, stops: $visitedStops/$totalStops, distance: $formattedDistance)';
  }
}
