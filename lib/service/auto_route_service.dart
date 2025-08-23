import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../models/permission_model.dart';
import 'permission_service.dart';
import 'auto_stop_service.dart';
import 'geocoding_service.dart';
class AutoRouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<void> createAutoRouteForDriver({
    required String driverId,
    required String vehiclePlate,
    required String region,
  }) async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      String routeType;
      if (currentHour >= 6 && currentHour < 12) {
        routeType = 'morning';
      } else if (currentHour >= 12 && currentHour < 20) {
        routeType = 'evening';
      } else {
        routeType = 'morning';
      }
      print('[AutoRouteService] Şoför $driverId için $routeType rotası oluşturuluyor...');
      await deleteExistingAutoRoutes(driverId, now, routeType);
      final result = await generateAutoRouteFromDriverLocation(
        driverId: driverId,
        regionId: region,
        routeDate: now,
        routeType: routeType,
      );
      if (result == null) {
        print('[AutoRouteService] Şoför için otomatik rota başarıyla oluşturuldu');
        _startListeningForPermissionChanges(driverId, region);
      } else {
        print('[AutoRouteService] Rota oluşturma hatası: $result');
      }
    } catch (e) {
      print('[AutoRouteService] createAutoRouteForDriver hatası: $e');
      rethrow;
    }
  }
  static Future<String?> generateAutoRouteFromDriverLocation({
    required String driverId,
    required String regionId,
    DateTime? routeDate,
    String? routeType,
  }) async {
    try {
      final targetDate = routeDate ?? DateTime.now();
      final targetRouteType = routeType ?? 'morning';
      print('[AutoRouteService] Şoför konumuna göre otomatik rota oluşturuluyor...');
      print('[AutoRouteService] Şoför: $driverId, Bölge: $regionId, Tarih: $targetDate, Tip: $targetRouteType');
      final passengers = await _getDriverPassengers(driverId, regionId);
      if (passengers.isEmpty) {
        return 'Bu şoföre atanmış yolcu bulunamadı.';
      }
      print('[AutoRouteService] Toplam yolcu sayısı: ${passengers.length}');
      final activePassengers = await _filterActivePassengers(
        passengers, 
        targetDate, 
        targetRouteType
      );
      print('[AutoRouteService] Aktif yolcu sayısı: ${activePassengers.length}');
      if (activePassengers.isEmpty) {
        return 'Bu tarih ve saat için aktif yolcu bulunamadı.';
      }
      final allStops = await _getMainRoadStopsForPassengers(activePassengers, regionId);
      if (allStops.isEmpty) {
        return 'Aktif yolcular için ana yol durağı bulunamadı.';
      }
      print('[AutoRouteService] Toplam ana yol durağı sayısı: ${allStops.length}');
      final driverLocation = await _getDriverCurrentLocation(driverId);
      if (driverLocation == null) {
        print('[AutoRouteService] Şoför konumu alınamadı, varsayılan sıralama kullanılıyor');
        return await _generateStandardAutoRoute(
          driverId: driverId,
          regionId: regionId,
          routeDate: targetDate,
          routeType: targetRouteType,
          passengers: activePassengers,
          stops: allStops,
        );
      }
      print('[AutoRouteService] Şoför konumu: ${driverLocation['latitude']}, ${driverLocation['longitude']}');
      final optimizedStops = await _createMultiStopRoute(allStops, driverLocation, activePassengers);
      print('[AutoRouteService] Ana yol durakları şoför konumuna göre optimize edildi');
      for (int i = 0; i < optimizedStops.length; i++) {
        final stop = optimizedStops[i];
        final distance = _calculateDistance(
          driverLocation['latitude']!, 
          driverLocation['longitude']!,
          stop['latitude']?.toDouble() ?? 0.0, 
          stop['longitude']?.toDouble() ?? 0.0
        );
        print('[AutoRouteService] ${i + 1}. ${stop['name']} - ${distance.toStringAsFixed(2)} km');
      }
      final navigationUrl = GeocodingService.generateNavigationUrl(
        origin: driverLocation,
        waypoints: optimizedStops,
      );
      final routeName = _generateRouteName(targetRouteType, targetDate, activePassengers.length);
      final routeId = await _createRoute(
        driverId: driverId,
        regionId: regionId,
        routeName: routeName,
        stops: optimizedStops,
        routeDate: targetDate,
        routeType: targetRouteType,
        navigationUrl: navigationUrl,
      );
      print('[AutoRouteService] Şoför konumuna göre ana yol rotası oluşturuldu: $routeId, Durak sayısı: ${optimizedStops.length}');
      return null;
    } catch (e) {
      print('[AutoRouteService] Hata: $e');
      return 'Şoför konumuna göre rota oluşturulurken hata: $e';
    }
  }
  static Future<List<Map<String, dynamic>>> _getMainRoadStopsForPassengers(
    List<Map<String, dynamic>> passengers,
    String regionId,
  ) async {
    final List<Map<String, dynamic>> stops = [];
    final Set<String> addedStops = {};
    for (final passenger in passengers) {
      try {
        final mainRoadStop = await _findMainRoadStopForPassenger(passenger, regionId);
        if (mainRoadStop != null) {
          final stopKey = '${mainRoadStop['latitude']}_${mainRoadStop['longitude']}';
          if (!addedStops.contains(stopKey)) {
            stops.add(mainRoadStop);
            addedStops.add(stopKey);
            print('[AutoRouteService] Ana yol durağı eklendi: ${mainRoadStop['name']} (${passenger['name']} için)');
          }
        } else {
          await _createMainRoadStopForPassenger(passenger, regionId);
          final newMainRoadStop = await _findMainRoadStopForPassenger(passenger, regionId);
          if (newMainRoadStop != null) {
            final stopKey = '${newMainRoadStop['latitude']}_${newMainRoadStop['longitude']}';
            if (!addedStops.contains(stopKey)) {
              stops.add(newMainRoadStop);
              addedStops.add(stopKey);
              print('[AutoRouteService] Yeni ana yol durağı oluşturuldu ve eklendi: ${newMainRoadStop['name']} (${passenger['name']} için)');
            }
          } else {
            final fallbackStop = await _createFallbackStopForPassenger(passenger, regionId);
            if (fallbackStop != null) {
              final stopKey = '${fallbackStop['latitude']}_${fallbackStop['longitude']}';
              if (!addedStops.contains(stopKey)) {
                stops.add(fallbackStop);
                addedStops.add(stopKey);
                print('[AutoRouteService] Yedek durak oluşturuldu: ${fallbackStop['name']} (${passenger['name']} için)');
              }
            }
          }
        }
      } catch (e) {
        print('[AutoRouteService] ${passenger['name']} için ana yol durağı işlemi hatası: $e');
        try {
          final fallbackStop = await _createFallbackStopForPassenger(passenger, regionId);
          if (fallbackStop != null) {
            final stopKey = '${fallbackStop['latitude']}_${fallbackStop['longitude']}';
            if (!addedStops.contains(stopKey)) {
              stops.add(fallbackStop);
              addedStops.add(stopKey);
              print('[AutoRouteService] Hata sonrası yedek durak oluşturuldu: ${fallbackStop['name']} (${passenger['name']} için)');
            }
          }
        } catch (fallbackError) {
          print('[AutoRouteService] ${passenger['name']} için yedek durak oluşturulamadı: $fallbackError');
        }
      }
    }
    print('[AutoRouteService] Toplam ${stops.length} durak bulundu');
    return stops;
  }
  static Future<Map<String, dynamic>?> _findMainRoadStopForPassenger(
    Map<String, dynamic> passenger,
    String regionId,
  ) async {
    try {
      final enhancedStopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passenger['id'])
          .where('isActive', isEqualTo: true)
          .where('regionId', isEqualTo: regionId)
          .limit(1)
          .get();
      if (enhancedStopsSnapshot.docs.isNotEmpty) {
        final stopDoc = enhancedStopsSnapshot.docs.first;
        final stopData = stopDoc.data();
        return {
          'id': stopDoc.id,
          'name': stopData['name'] ?? '${passenger['name']} Ana Yol Durağı',
          'address': stopData['address'] ?? passenger['address'],
          'latitude': stopData['latitude'],
          'longitude': stopData['longitude'],
          'passengerIds': stopData['passengerIds'] ?? [passenger['id']],
          'estimatedTime': 2,
          'isMainRoad': true,
        };
      }
      return null;
    } catch (e) {
      print('[AutoRouteService] Ana yol durağı bulunamadı: ${passenger['name']} - $e');
      return null;
    }
  }
  static Future<void> _createMainRoadStopForPassenger(
    Map<String, dynamic> passenger,
    String regionId,
  ) async {
    try {
      final address = passenger['address'];
      if (address == null || address.toString().trim().isEmpty) {
        print('[AutoRouteService] ${passenger['name']} için adres bilgisi yok');
        return;
      }
      final validatedCoordinates = await GeocodingService.validateAndFixCoordinates(
        address: address.toString(),
        latitude: 0.0,
        longitude: 0.0,
      );
      if (validatedCoordinates == null) {
        print('[AutoRouteService] ${passenger['name']} için koordinat alınamadı: $address');
        return;
      }
      await _firestore.collection('enhanced_stops').add({
        'name': '${passenger['name']} Ana Yol Durağı',
        'address': address.toString(),
        'latitude': validatedCoordinates['latitude']!,
        'longitude': validatedCoordinates['longitude']!,
        'passengerIds': [passenger['id']],
        'regionId': regionId,
        'isActive': true,
        'isMainRoad': true,
        'coordinatesValidated': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('[AutoRouteService] ${passenger['name']} için ana yol durağı oluşturuldu (koordinatlar doğrulandı)');
    } catch (e) {
      print('[AutoRouteService] ${passenger['name']} için ana yol durağı oluşturma hatası: $e');
    }
  }
  static Future<Map<String, dynamic>?> _createFallbackStopForPassenger(
    Map<String, dynamic> passenger,
    String regionId,
  ) async {
    try {
      final address = passenger['address'];
      if (address == null || address.toString().trim().isEmpty) {
        print('[AutoRouteService] ${passenger['name']} için adres bilgisi yok');
        return null;
      }
      final validatedCoordinates = await GeocodingService.validateAndFixCoordinates(
        address: address.toString(),
        latitude: 0.0,
        longitude: 0.0,
      );
      if (validatedCoordinates == null) {
        print('[AutoRouteService] ${passenger['name']} için yedek durak koordinatı alınamadı');
        final fallbackStop = {
          'id': 'fallback_${passenger['id']}_${DateTime.now().millisecondsSinceEpoch}',
          'name': '${passenger['name']} Durağı (Koordinat Gerekli)',
          'address': address.toString(),
          'latitude': 0.0,
          'longitude': 0.0,
          'passengerIds': [passenger['id']],
          'estimatedTime': 2,
          'isMainRoad': false,
          'isFallback': true,
          'coordinatesValidated': false,
        };
        return fallbackStop;
      }
      final fallbackStop = {
        'id': 'fallback_${passenger['id']}_${DateTime.now().millisecondsSinceEpoch}',
        'name': '${passenger['name']} Durağı',
        'address': address.toString(),
        'latitude': validatedCoordinates['latitude']!,
        'longitude': validatedCoordinates['longitude']!,
        'passengerIds': [passenger['id']],
        'estimatedTime': 2,
        'isMainRoad': false,
        'isFallback': true,
        'coordinatesValidated': true,
      };
      print('[AutoRouteService] ${passenger['name']} için yedek durak oluşturuldu (koordinatlar doğrulandı)');
      return fallbackStop;
    } catch (e) {
      print('[AutoRouteService] ${passenger['name']} için yedek durak oluşturma hatası: $e');
      return null;
    }
  }
  static Future<String?> _generateStandardAutoRoute({
    required String driverId,
    required String regionId,
    required DateTime routeDate,
    required String routeType,
    required List<Map<String, dynamic>> passengers,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      final routeName = _generateRouteName(routeType, routeDate, passengers.length);
      final routeId = await _createRoute(
        driverId: driverId,
        regionId: regionId,
        routeName: routeName,
        stops: stops,
        routeDate: routeDate,
        routeType: routeType,
      );
      print('[AutoRouteService] Standart ana yol rotası oluşturuldu: $routeId');
      return null;
    } catch (e) {
      print('[AutoRouteService] Standart rota oluşturma hatası: $e');
      return 'Standart rota oluşturulurken hata: $e';
    }
  }
  static Future<Map<String, double>?> _getDriverCurrentLocation(String driverId) async {
    try {
      final locationDoc = await _firestore
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (locationDoc.exists) {
        final locationData = locationDoc.data()!;
        return {
          'latitude': locationData['lat']?.toDouble() ?? 0.0,
          'longitude': locationData['lng']?.toDouble() ?? 0.0,
        };
      }
      print('[AutoRouteService] Aktif konum paylaşımı bulunamadı');
      return null;
    } catch (e) {
      print('[AutoRouteService] Şoför konumu alınırken hata: $e');
      return null;
    }
  }
  static Future<List<Map<String, dynamic>>> _createMultiStopRoute(
    List<Map<String, dynamic>> stops,
    Map<String, double> driverLocation,
    List<Map<String, dynamic>> activePassengers,
  ) async {
    if (stops.isEmpty) return stops;
    final List<Map<String, dynamic>> expandedStops = [];
    for (final passenger in activePassengers) {
      final mainRoadStop = stops.firstWhere(
        (stop) => (stop['passengerIds'] as List?)?.contains(passenger['id']) ?? false,
        orElse: () => {},
      );
      if (mainRoadStop.isNotEmpty) {
        expandedStops.add({
          ...mainRoadStop,
          'stopType': 'mainRoad',
          'primaryPassengerId': passenger['id'],
          'estimatedTime': 1,
        });
        expandedStops.add({
          'id': 'passenger_${passenger['id']}_${DateTime.now().millisecondsSinceEpoch}',
          'name': '${passenger['name']} Evi',
          'address': passenger['address'] ?? '',
          'latitude': passenger['latitude']?.toDouble() ?? mainRoadStop['latitude']?.toDouble() ?? 0.0,
          'longitude': passenger['longitude']?.toDouble() ?? mainRoadStop['longitude']?.toDouble() ?? 0.0,
          'passengerIds': [passenger['id']],
          'stopType': 'passenger',
          'primaryPassengerId': passenger['id'],
          'estimatedTime': 3,
        });
      }
    }
    if (expandedStops.isEmpty) return stops;
    try {
      final optimizedStops = await GeocodingService.optimizeStopsAsWaypoints(
        driverLocation: driverLocation,
        stops: expandedStops,
      );
      print('[AutoRouteService] Waypoints ile ${optimizedStops.length} durak optimize edildi');
      return optimizedStops;
    } catch (e) {
      print('[AutoRouteService] Waypoints optimizasyon hatası: $e, fallback kullanılıyor');
      return _sortStopsByDistanceFromDriver(expandedStops, driverLocation);
    }
  }
  static List<Map<String, dynamic>> _sortStopsByDistanceFromDriver(
    List<Map<String, dynamic>> stops,
    Map<String, double> driverLocation,
  ) {
    if (stops.isEmpty) return stops;
    if (stops.length == 1) return stops;
    final List<Map<String, dynamic>> stopsWithDistance = [];
    for (final stop in stops) {
      final distance = _calculateDistance(
        driverLocation['latitude']!,
        driverLocation['longitude']!,
        stop['latitude']?.toDouble() ?? 0.0,
        stop['longitude']?.toDouble() ?? 0.0,
      );
      final stopWithDistance = Map<String, dynamic>.from(stop);
      stopWithDistance['distanceFromDriver'] = distance;
      stopsWithDistance.add(stopWithDistance);
    }
    final List<Map<String, dynamic>> optimizedRoute = [];
    final List<Map<String, dynamic>> remainingStops = List.from(stopsWithDistance);
    remainingStops.sort((a, b) {
      final distanceA = a['distanceFromDriver'] as double;
      final distanceB = b['distanceFromDriver'] as double;
      return distanceA.compareTo(distanceB);
    });
    Map<String, dynamic> currentStop = remainingStops.removeAt(0);
    optimizedRoute.add(currentStop);
    while (remainingStops.isNotEmpty) {
      double minDistance = double.infinity;
      int nearestIndex = 0;
      for (int i = 0; i < remainingStops.length; i++) {
        final distance = _calculateDistance(
          currentStop['latitude']?.toDouble() ?? 0.0,
          currentStop['longitude']?.toDouble() ?? 0.0,
          remainingStops[i]['latitude']?.toDouble() ?? 0.0,
          remainingStops[i]['longitude']?.toDouble() ?? 0.0,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
      currentStop = remainingStops.removeAt(nearestIndex);
      optimizedRoute.add(currentStop);
    }
    final result = optimizedRoute.map((stop) {
      stop.remove('distanceFromDriver');
      return stop;
    }).toList();
    print('[AutoRouteService] Rota optimizasyonu tamamlandı: ${result.length} durak sıralandı');
    return result;
  }
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
  static void _startListeningForPermissionChanges(String driverId, String region) {
    print('[AutoRouteService] İzin değişiklikleri dinleniyor...');
    _firestore
        .collection('permissions')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docChanges.isNotEmpty) {
        print('[AutoRouteService] İzin değişikliği tespit edildi, rota güncelleniyor...');
        Future.delayed(const Duration(seconds: 2), () {
          updateRouteForPermissionChange(driverId, region);
        });
      }
    });
  }
  static Future<void> updateRouteForPermissionChange(String driverId, String region) async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      String routeType;
      if (currentHour >= 6 && currentHour < 12) {
        routeType = 'morning';
      } else if (currentHour >= 12 && currentHour < 20) {
        routeType = 'evening';
      } else {
        return;
      }
      print('[AutoRouteService] İzin değişikliği nedeniyle $routeType rotası güncelleniyor...');
      await deleteExistingAutoRoutes(driverId, now, routeType);
      final result = await generateAutoRoute(
        driverId: driverId,
        regionId: region,
        routeDate: now,
        routeType: routeType,
      );
      if (result == null) {
        print('[AutoRouteService] Rota izin değişikliği nedeniyle güncellendi');
      } else {
        print('[AutoRouteService] Rota güncelleme hatası: $result');
      }
    } catch (e) {
      print('[AutoRouteService] Rota güncelleme hatası: $e');
    }
  }
  static Future<String?> generateAutoRoute({
    required String driverId,
    required String regionId,
    DateTime? routeDate,
    String? routeType,
  }) async {
    return await generateAutoRouteFromDriverLocation(
      driverId: driverId,
      regionId: regionId,
      routeDate: routeDate,
      routeType: routeType,
    );
  }
  static Future<List<Map<String, dynamic>>> _getDriverPassengers(
    String driverId, 
    String regionId
  ) async {
    final snapshot = await _firestore
        .collection('passengers')
        .where('driverId', isEqualTo: driverId)
        .where('regionId', isEqualTo: regionId)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }
  static Future<List<Map<String, dynamic>>> _filterActivePassengers(
    List<Map<String, dynamic>> passengers,
    DateTime routeDate,
    String routeType,
  ) async {
    final List<Map<String, dynamic>> activePassengers = [];
    for (final passenger in passengers) {
      final userId = passenger['id'];
      final hasPermission = await _checkUserPermissionForDate(
        userId,
        routeDate,
        routeType,
      );
      if (!hasPermission) {
        activePassengers.add(passenger);
        print('[AutoRouteService] Aktif yolcu: ${passenger['name']}');
      } else {
        print('[AutoRouteService] İzinli yolcu (rotadan çıkarıldı): ${passenger['name']}');
      }
    }
    return activePassengers;
  }
  static Future<bool> _checkUserPermissionForDate(
    String userId,
    DateTime targetDate,
    String routeType,
  ) async {
    try {
      final permissions = await PermissionService.checkUserPermissionsForDate(
        userId,
        targetDate,
      );
      return _checkPassengerPermission(permissions, routeType, targetDate);
    } catch (e) {
      print('[AutoRouteService] İzin kontrolü hatası: $e');
      return false;
    }
  }
  static bool _checkPassengerPermission(
    List<PermissionModel> permissions, 
    String routeType,
    DateTime targetDate,
  ) {
    final today = DateTime.now();
    final isToday = targetDate.year == today.year && 
                   targetDate.month == today.month && 
                   targetDate.day == today.day;
    final isTomorrow = targetDate.difference(today).inDays == 1;
    for (final permission in permissions) {
      switch (permission.type) {
        case PermissionType.allToday:
          if (isToday) return true;
          break;
        case PermissionType.allTomorrow:
          if (isTomorrow) return true;
          break;
        case PermissionType.vacation:
          return true;
        case PermissionType.morningToday:
          if (isToday && routeType == 'morning') return true;
          break;
        case PermissionType.morningTomorrow:
          if (isTomorrow && routeType == 'morning') return true;
          break;
        case PermissionType.eveningToday:
          if (isToday && routeType == 'evening') return true;
          break;
      }
    }
    return false;
  }
  static Future<List<Map<String, dynamic>>> _getPassengerStops(
    List<Map<String, dynamic>> passengers
  ) async {
    final List<Map<String, dynamic>> stops = [];
    final Set<String> addedStops = {};
    for (final passenger in passengers) {
      final stopData = await _findStopForPassenger(passenger);
      if (stopData != null) {
        final stopKey = '${stopData['latitude']}_${stopData['longitude']}';
        if (!addedStops.contains(stopKey)) {
          stops.add(stopData);
          addedStops.add(stopKey);
        }
      }
    }
    return stops;
  }
  static Future<Map<String, dynamic>?> _findStopForPassenger(
    Map<String, dynamic> passenger
  ) async {
    try {
      final enhancedStopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passenger['id'])
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (enhancedStopsSnapshot.docs.isNotEmpty) {
        final stopDoc = enhancedStopsSnapshot.docs.first;
        final stopData = stopDoc.data();
        return {
          'id': stopDoc.id,
          'name': stopData['name'] ?? '${passenger['name']} Durağı',
          'address': stopData['address'] ?? passenger['address'],
          'latitude': stopData['latitude'],
          'longitude': stopData['longitude'],
          'passengerIds': [passenger['id']],
          'estimatedTime': 2,
        };
      }
      if (passenger['address'] != null) {
        return {
          'id': 'temp_${passenger['id']}',
          'name': '${passenger['name']} Durağı',
          'address': passenger['address'],
          'latitude': 0.0,
          'longitude': 0.0,
          'passengerIds': [passenger['id']],
          'estimatedTime': 2,
        };
      }
      return null;
    } catch (e) {
      print('[AutoRouteService] Durak bulunamadı: ${passenger['name']} - $e');
      return null;
    }
  }
  static String _generateRouteName(
    String routeType, 
    DateTime routeDate, 
    int passengerCount
  ) {
    final dateStr = '${routeDate.day}/${routeDate.month}/${routeDate.year}';
    final timeStr = routeType == 'morning' ? 'Sabah' : 'Akşam';
    return 'Otomatik $timeStr Rotası - $dateStr ($passengerCount yolcu)';
  }
  static Future<String> _createRoute({
    required String driverId,
    required String regionId,
    required String routeName,
    required List<Map<String, dynamic>> stops,
    required DateTime routeDate,
    required String routeType,
    String? navigationUrl,
  }) async {
    DateTime startTime, endTime;
    if (routeType == 'morning') {
      startTime = DateTime(routeDate.year, routeDate.month, routeDate.day, 7, 0);
      endTime = DateTime(routeDate.year, routeDate.month, routeDate.day, 9, 0);
    } else {
      startTime = DateTime(routeDate.year, routeDate.month, routeDate.day, 16, 0);
      endTime = DateTime(routeDate.year, routeDate.month, routeDate.day, 18, 0);
    }
    final routeDoc = await _firestore.collection('routes').add({
      'driverId': driverId,
      'regionId': regionId,
      'routeName': routeName,
      'stops': stops,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'status': 'active',
      'isAutoGenerated': true,
      'routeType': routeType,
      'routeDate': Timestamp.fromDate(routeDate),
      'navigationUrl': navigationUrl,
      'hasWaypoints': stops.length > 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return routeDoc.id;
  }
  static Future<String?> generateTodayRoutes(String driverId, String regionId) async {
    final today = DateTime.now();
    final morningResult = await generateAutoRoute(
      driverId: driverId,
      regionId: regionId,
      routeDate: today,
      routeType: 'morning',
    );
    final eveningResult = await generateAutoRoute(
      driverId: driverId,
      regionId: regionId,
      routeDate: today,
      routeType: 'evening',
    );
    if (morningResult != null && eveningResult != null) {
      return 'Sabah: $morningResult, Akşam: $eveningResult';
    } else if (morningResult != null) {
      return 'Sabah rotası hatası: $morningResult';
    } else if (eveningResult != null) {
      return 'Akşam rotası hatası: $eveningResult';
    }
    return null;
  }
  static Future<String?> generateTomorrowRoutes(String driverId, String regionId) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final morningResult = await generateAutoRoute(
      driverId: driverId,
      regionId: regionId,
      routeDate: tomorrow,
      routeType: 'morning',
    );
    final eveningResult = await generateAutoRoute(
      driverId: driverId,
      regionId: regionId,
      routeDate: tomorrow,
      routeType: 'evening',
    );
    if (morningResult != null && eveningResult != null) {
      return 'Sabah: $morningResult, Akşam: $eveningResult';
    } else if (morningResult != null) {
      return 'Sabah rotası hatası: $morningResult';
    } else if (eveningResult != null) {
      return 'Akşam rotası hatası: $eveningResult';
    }
    return null;
  }
  static Future<void> deleteExistingAutoRoutes(
    String driverId, 
    DateTime routeDate,
    String routeType,
  ) async {
    try {
      final startOfDay = DateTime(routeDate.year, routeDate.month, routeDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final snapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .where('isAutoGenerated', isEqualTo: true)
          .where('routeType', isEqualTo: routeType)
          .where('routeDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('routeDate', isLessThan: Timestamp.fromDate(endOfDay))
          .get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
      print('[AutoRouteService] Eski otomatik rotalar silindi: ${snapshot.docs.length} adet');
    } catch (e) {
      print('[AutoRouteService] Eski rotalar silinirken hata: $e');
    }
  }
  static Future<void> generateDailyRoutes(DateTime date) async {
    try {
      final driversSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('isActive', isEqualTo: true)
          .get();
      for (final driverDoc in driversSnapshot.docs) {
        final driverId = driverDoc.id;
        final driverData = driverDoc.data();
        final regionId = driverData['regionId'] as String?;
        if (regionId == null) continue;
        final activePassengers = await _getActivePassengersForDriver(
          driverId, 
          date,
        );
        if (activePassengers.isEmpty) continue;
        await _createMorningRoute(driverId, regionId, activePassengers, date);
        await _createEveningRoute(driverId, regionId, activePassengers, date);
      }
    } catch (e) {
      print('Günlük rota oluşturma hatası: $e');
      rethrow;
    }
  }
  static Future<List<Map<String, dynamic>>> _getActivePassengersForDriver(
    String driverId,
    DateTime date,
  ) async {
    final passengers = await _getDriverPassengers(driverId, '');
    final morningActive = await _filterActivePassengers(passengers, date, 'morning');
    final eveningActive = await _filterActivePassengers(passengers, date, 'evening');
    final allActive = <String, Map<String, dynamic>>{};
    for (final passenger in morningActive) {
      allActive[passenger['id']] = passenger;
    }
    for (final passenger in eveningActive) {
      allActive[passenger['id']] = passenger;
    }
    return allActive.values.toList();
  }
  static Future<void> _createMorningRoute(
    String driverId,
    String regionId,
    List<Map<String, dynamic>> passengers,
    DateTime date,
  ) async {
    final morningPassengers = await _filterActivePassengers(passengers, date, 'morning');
    if (morningPassengers.isNotEmpty) {
      await generateAutoRoute(
        driverId: driverId,
        regionId: regionId,
        routeDate: date,
        routeType: 'morning',
      );
    }
  }
  static Future<void> _createEveningRoute(
    String driverId,
    String regionId,
    List<Map<String, dynamic>> passengers,
    DateTime date,
  ) async {
    final eveningPassengers = await _filterActivePassengers(passengers, date, 'evening');
    if (eveningPassengers.isNotEmpty) {
      await generateAutoRoute(
        driverId: driverId,
        regionId: regionId,
        routeDate: date,
        routeType: 'evening',
      );
    }
  }
}
