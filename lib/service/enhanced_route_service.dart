import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import '../models/stop_log_model.dart';
import 'permission_service.dart';
import '../models/permission_model.dart';
import 'geocoding_service.dart';
import 'unified_route_optimization_service.dart';

class EnhancedRouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<List<StopModel>> getDriverStops(String driverId) async {
    try {
      final stopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .get();
      List<StopModel> stops = [];
      for (var doc in stopsSnapshot.docs) {
        final data = doc.data();
        if (data['temporarilyInactive'] == true) {
          continue;
        }
        try {
          final List<String> passengerIds =
              List<String>.from(data['passengerIds'] ?? []);
          final todayPerms =
              await PermissionService.getTodayActivePermissionsFuture(driverId);
          final now = DateTime.now();
          final bool isMorningNow = now.hour < 12;
          final Set<String> absentNow = todayPerms
              .where((p) {
                switch (p.type) {
                  case PermissionType.allToday:
                    return true;
                  case PermissionType.morningToday:
                    return isMorningNow;
                  case PermissionType.eveningToday:
                    return !isMorningNow;
                  case PermissionType.vacation:
                    return true;
                  case PermissionType.morningTomorrow:
                  case PermissionType.allTomorrow:
                    return false;
                }
              })
              .map((p) => p.userId)
              .toSet();
          final allAbsent = passengerIds.isNotEmpty &&
              passengerIds.every((pid) => absentNow.contains(pid));
          if (allAbsent) {
            continue;
          }
        } catch (_) {}
        final stop = StopModel(
          id: doc.id,
          driverId: driverId,
          passengerId: data['passengerIds']?.isNotEmpty == true
              ? data['passengerIds'][0]
              : null,
          passengerName: data['passengerNames']?.isNotEmpty == true
              ? data['passengerNames'][0]
              : null,
          address: data['address'] ?? '',
          lat: (data['latitude'] ?? 0.0).toDouble(),
          lng: (data['longitude'] ?? 0.0).toDouble(),
          date: DateTime.now(),
          order: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          regionId: data['regionId'],
          phoneNumber: data['phoneNumber'],
          metadata: {
            'passengerCount': data['passengerCount'] ?? 0,
            'passengerIds': data['passengerIds'] ?? [],
            'passengerNames': data['passengerNames'] ?? [],
          },
        );
        stops.add(stop);
      }
      return stops;
    } catch (e) {
      print('❌ Şoför durakları alma hatası: $e');
      return [];
    }
  }

  static Future<List<StopModel>> optimizeRoute(
      List<StopModel> stops, Position currentPosition) async {
    if (stops.isEmpty) return [];
    try {
      if (stops.length == 1) {
        print('📍 Tek durak için rota oluşturuluyor');
        return [stops.first.copyWith(order: 1)];
      }

      final driverLocation = {
        'latitude': currentPosition.latitude,
        'longitude': currentPosition.longitude,
      };

      final stopsAsWaypoints = stops
          .map((stop) => {
                'latitude': stop.lat,
                'longitude': stop.lng,
                'stopId': stop.id,
                'address': stop.address,
                'passengerIds': [],
              })
          .toList();

      print(
          '🚀 Unified Route Optimization Service ile ${stops.length} durak optimize ediliyor...');

      final cacheKey =
          'driver_${stops.first.driverId}_${stops.length}_${currentPosition.latitude.toStringAsFixed(6)}_${currentPosition.longitude.toStringAsFixed(6)}';
      print('🔑 Cache key: $cacheKey');

      final optimizedWaypoints =
          await UnifiedRouteOptimizationService.optimizeRoute(
        driverLocation: driverLocation,
        stops: stopsAsWaypoints,
        useGoogleApi: true,
        cacheKey: cacheKey,
      );

      if (optimizedWaypoints.isEmpty) {
        print('⚠️ Unified optimizasyon başarısız, fallback kullanılıyor');
        return _fallbackOptimizeRoute(stops, currentPosition);
      }

      final optimizedRoute = <StopModel>[];
      for (int i = 0; i < optimizedWaypoints.length; i++) {
        final waypoint = optimizedWaypoints[i];
        final originalStop = stops.firstWhere(
          (stop) =>
              stop.lat == waypoint['latitude'] &&
              stop.lng == waypoint['longitude'],
          orElse: () => stops.first,
        );
        optimizedRoute.add(originalStop.copyWith(order: i + 1));
      }

      final stats = UnifiedRouteOptimizationService.getRouteStatistics(
          optimizedWaypoints);
      print(
          '✅ ${optimizedRoute.length} durak Unified Service ile optimize edildi');
      print(
          '📊 Optimizasyon istatistikleri: ${stats['optimizationMethod']} - ${stats['totalDistance']?.toStringAsFixed(2)} km');

      return optimizedRoute;
    } catch (e) {
      print('❌ Unified optimizasyon hatası: $e');
      print('🔄 Fallback algoritma ile devam ediliyor...');
      return _fallbackOptimizeRoute(stops, currentPosition);
    }
  }

  static Future<List<StopModel>> _fallbackOptimizeRoute(
      List<StopModel> stops, Position currentPosition) async {
    if (stops.isEmpty) return [];
    List<StopModel> optimizedRoute = [];
    List<StopModel> remainingStops = List.from(stops);
    Position currentPos = currentPosition;
    while (remainingStops.isNotEmpty) {
      StopModel nearestStop = remainingStops.first;
      double minDistance = _calculateDistance(
        currentPos.latitude,
        currentPos.longitude,
        nearestStop.lat,
        nearestStop.lng,
      );
      for (var stop in remainingStops) {
        double distance = _calculateDistance(
          currentPos.latitude,
          currentPos.longitude,
          stop.lat,
          stop.lng,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestStop = stop;
        }
      }
      optimizedRoute
          .add(nearestStop.copyWith(order: optimizedRoute.length + 1));
      remainingStops.remove(nearestStop);
      currentPos = Position(
        latitude: nearestStop.lat,
        longitude: nearestStop.lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }
    print(
        '📍 ${optimizedRoute.length} durak yerel algoritma ile optimize edildi');
    return optimizedRoute;
  }

  static Future<Map<String, dynamic>> createOptimizedRouteWithNavigation({
    required String driverId,
    required String regionId,
    required Position currentPosition,
  }) async {
    try {
      final stops = await getDriverStops(driverId);
      if (stops.isEmpty) {
        print('📍 Şoför için aktif durak bulunamadı');
        return {
          'route': <StopModel>[],
          'navigationUrl': null,
          'totalDistance': 0.0,
          'estimatedDuration': 0,
        };
      }
      final optimizedRoute = await optimizeRoute(stops, currentPosition);
      if (optimizedRoute.isEmpty) {
        return {
          'route': <StopModel>[],
          'navigationUrl': null,
          'totalDistance': 0.0,
          'estimatedDuration': 0,
        };
      }
      String? navigationUrl;
      double totalDistance = 0.0;
      int estimatedDuration = 0;
      try {
        final driverLocation = {
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
        };
        final waypoints = optimizedRoute
            .map((stop) => {
                  'latitude': stop.lat,
                  'longitude': stop.lng,
                  'name': stop.address,
                })
            .toList();
        if (optimizedRoute.length == 1) {
          final stop = optimizedRoute.first;
          navigationUrl =
              'https://www.google.com/maps/dir/?api=1&destination=${stop.lat},${stop.lng}&travelmode=driving';
          totalDistance = _calculateDistance(
            currentPosition.latitude,
            currentPosition.longitude,
            stop.lat,
            stop.lng,
          );
          estimatedDuration = (totalDistance / 1000 * 2).round();
        } else {
          navigationUrl = GeocodingService.generateNavigationUrl(
            origin: driverLocation,
            waypoints: waypoints,
          );
          totalDistance = _calculateDistance(
            currentPosition.latitude,
            currentPosition.longitude,
            optimizedRoute.first.lat,
            optimizedRoute.first.lng,
          );
          for (int i = 0; i < optimizedRoute.length - 1; i++) {
            totalDistance += _calculateDistance(
              optimizedRoute[i].lat,
              optimizedRoute[i].lng,
              optimizedRoute[i + 1].lat,
              optimizedRoute[i + 1].lng,
            );
          }
          estimatedDuration = (totalDistance / 1000 * 2).round();
        }
        print(
            '🗺️ Navigasyon URL oluşturuldu: ${navigationUrl.substring(0, 50)}...');
      } catch (e) {
        print('⚠️ Navigasyon URL oluşturma hatası: $e');
      }
      print('🗺️ ${optimizedRoute.length} durak için rota optimize edildi');
      return {
        'route': optimizedRoute,
        'navigationUrl': navigationUrl,
        'totalDistance': totalDistance,
        'estimatedDuration': estimatedDuration,
      };
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
      return {
        'route': <StopModel>[],
        'navigationUrl': null,
        'totalDistance': 0.0,
        'estimatedDuration': 0,
      };
    }
  }

  static Future<List<StopModel>> createOptimizedRoute({
    required String driverId,
    required String regionId,
    required Position currentPosition,
  }) async {
    final result = await createOptimizedRouteWithNavigation(
      driverId: driverId,
      regionId: regionId,
      currentPosition: currentPosition,
    );
    return result['route'] as List<StopModel>;
  }

  static double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  static Future<void> logStopArrival({
    required String stopId,
    required String driverId,
    required String driverName,
    required String vehiclePlate,
    required String regionId,
    required String stopAddress,
    required double latitude,
    required double longitude,
    required List<String> passengerIds,
    required List<String> passengerNames,
    String? notes,
  }) async {
    try {
      final log = StopLogModel(
        id: '',
        stopId: stopId,
        driverId: driverId,
        driverName: driverName,
        vehiclePlate: vehiclePlate,
        regionId: regionId,
        stopAddress: stopAddress,
        latitude: latitude,
        longitude: longitude,
        arrivedAt: DateTime.now(),
        passengerCount: passengerIds.length,
        passengerIds: passengerIds,
        passengerNames: passengerNames,
        status: 'arrived',
        notes: notes,
        createdAt: DateTime.now(),
      );
      await _firestore.collection('stop_logs').add(log.toMap());
      print('📝 Durak varış kaydı oluşturuldu: $stopAddress');
    } catch (e) {
      print('❌ Durak log hatası: $e');
    }
  }

  static Future<void> logStopDeparture({
    required String stopId,
    required String driverId,
    String? notes,
  }) async {
    try {
      final logsSnapshot = await _firestore
          .collection('stop_logs')
          .where('stopId', isEqualTo: stopId)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'arrived')
          .orderBy('arrivedAt', descending: true)
          .limit(1)
          .get();
      if (logsSnapshot.docs.isNotEmpty) {
        final logDoc = logsSnapshot.docs.first;
        final logData = logDoc.data();
        final arrivedAt = (logData['arrivedAt'] as Timestamp).toDate();
        final departedAt = DateTime.now();
        final waitDuration = departedAt.difference(arrivedAt).inSeconds;
        await logDoc.reference.update({
          'departedAt': Timestamp.fromDate(departedAt),
          'status': 'departed',
          'waitDurationSeconds': waitDuration,
          'notes': notes,
        });
        print('🚌 Durak ayrılış kaydı güncellendi: ${logData['stopAddress']}');
      }
    } catch (e) {
      print('❌ Durak ayrılış log hatası: $e');
    }
  }

  static Stream<List<StopLogModel>> getDriverStopLogs(String driverId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _firestore
        .collection('stop_logs')
        .where('driverId', isEqualTo: driverId)
        .where('arrivedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('arrivedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('arrivedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StopLogModel.fromFirestore(doc))
            .toList());
  }

  static Stream<List<StopLogModel>> getRegionStopLogs(String regionId) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _firestore
        .collection('stop_logs')
        .where('regionId', isEqualTo: regionId)
        .where('arrivedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('arrivedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('arrivedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StopLogModel.fromFirestore(doc))
            .toList());
  }

  static Future<StopModel?> getCurrentStop(
      String driverId, String regionId) async {
    try {
      final logsSnapshot = await _firestore
          .collection('stop_logs')
          .where('driverId', isEqualTo: driverId)
          .where('regionId', isEqualTo: regionId)
          .where('status', isEqualTo: 'arrived')
          .orderBy('arrivedAt', descending: true)
          .limit(1)
          .get();
      if (logsSnapshot.docs.isNotEmpty) {
        final logData = logsSnapshot.docs.first.data();
        return StopModel(
          id: logData['stopId'],
          driverId: driverId,
          address: logData['stopAddress'],
          lat: logData['latitude'],
          lng: logData['longitude'],
          date: DateTime.now(),
          order: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          regionId: regionId,
          status: 'in_progress',
        );
      }
      return null;
    } catch (e) {
      print('❌ Mevcut durak alma hatası: $e');
      return null;
    }
  }

  static Future<StopModel?> getNextStop(
      String driverId, String regionId) async {
    try {
      final activeRoute = await _getActiveRoute(driverId);
      if (activeRoute != null) {
        final incompleteStops =
            await _getIncompleteStopsFromRoute(activeRoute['id']);
        if (incompleteStops.isNotEmpty) {
          final currentPosition = await Geolocator.getCurrentPosition();
          return _findNearestIncompleteStop(currentPosition, incompleteStops);
        }
      }
      final currentPosition = await Geolocator.getCurrentPosition();
      final route = await createOptimizedRoute(
        driverId: driverId,
        regionId: regionId,
        currentPosition: currentPosition,
      );
      if (route.isNotEmpty) {
        return route.first;
      }
      return null;
    } catch (e) {
      print('❌ Sonraki durak alma hatası: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _getActiveRoute(String driverId) async {
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
      print('❌ Aktif rota getirme hatası: $e');
      return null;
    }
  }

  static Future<List<StopModel>> _getIncompleteStopsFromRoute(
      String routeId) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) return [];
      final routeData = routeDoc.data()!;
      final stops = List<Map<String, dynamic>>.from(routeData['stops'] ?? []);
      final incompleteStops = stops
          .where((stop) => stop['isCompleted'] != true)
          .map((stop) => StopModel(
                id: stop['id'],
                driverId: routeData['driverId'],
                address: stop['address'] ?? '',
                lat: stop['lat'] ?? 0.0,
                lng: stop['lng'] ?? 0.0,
                date: DateTime.now(),
                order: stop['order'] ?? 0,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                regionId: routeData['regionId'],
                status: 'pending',
              ))
          .toList();
      return incompleteStops;
    } catch (e) {
      print('❌ Tamamlanmamış durakları getirme hatası: $e');
      return [];
    }
  }

  static StopModel? _findNearestIncompleteStop(
      Position currentPosition, List<StopModel> stops) {
    if (stops.isEmpty) return null;
    double minDistance = double.infinity;
    StopModel? nearestStop;
    for (final stop in stops) {
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        stop.lat,
        stop.lng,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestStop = stop;
      }
    }
    return nearestStop;
  }
}



 Again


