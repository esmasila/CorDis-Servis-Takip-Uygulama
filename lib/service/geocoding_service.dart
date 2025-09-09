import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'unified_route_optimization_service.dart';
import '../services/config_service.dart';

class GeocodingService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const String _directionsUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  static Future<Map<String, double>?> getCoordinatesFromAddress(
      String address) async {
    try {
      if (address.trim().isEmpty) {
        print('[GeocodingService] Boş adres girişi');
        return null;
      }
      final url =
          '$_baseUrl?address=${Uri.encodeComponent(address)}&region=tr&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      print('[GeocodingService] API isteği: $url');
      print('[GeocodingService] Yanıt kodu: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[GeocodingService] API yanıtı: ${data['status']}');
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          final coordinates = <String, double>{
            'latitude': location['lat'].toDouble(),
            'longitude': location['lng'].toDouble(),
          };
          print('[GeocodingService] ✅ Koordinat bulundu: $coordinates');
          return coordinates;
        } else {
          print('[GeocodingService] ❌ Koordinat bulunamadı: ${data['status']}');
        }
      } else {
        print('[GeocodingService] ❌ API hatası: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      print('[GeocodingService] ❌ Koordinat alma hatası: $e');
      return null;
    }
  }

  static Future<String?> getAddressFromCoordinates(
      double latitude, double longitude) async {
    try {
      if (latitude == 0.0 || longitude == 0.0) {
        print(
            '[GeocodingService] Geçersiz koordinatlar: $latitude, $longitude');
        return null;
      }
      final url =
          '$_baseUrl?latlng=$latitude,$longitude&language=tr&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      print(
          '[GeocodingService] Reverse geocoding isteği: $latitude, $longitude');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final address = data['results'][0]['formatted_address'];
          print('[GeocodingService] ✅ Adres bulundu: $address');
          return address;
        } else {
          print('[GeocodingService] ❌ Adres bulunamadı: ${data['status']}');
        }
      } else {
        print(
            '[GeocodingService] ❌ Reverse geocoding API hatası: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      print('[GeocodingService] ❌ Adres alma hatası: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getOptimizedRouteWithWaypoints({
    required Map<String, double> origin,
    required Map<String, double> destination,
    required List<Map<String, double>> waypoints,
    bool optimizeWaypoints = true,
  }) async {
    try {
      final originStr = '${origin['latitude']},${origin['longitude']}';
      final destinationStr =
          '${destination['latitude']},${destination['longitude']}';
      String waypointsStr = '';
      if (waypoints.isNotEmpty) {
        final waypointsList = waypoints
            .map((wp) => '${wp['latitude']},${wp['longitude']}')
            .toList();
        waypointsStr =
            '&waypoints=${optimizeWaypoints ? 'optimize:true|' : ''}${waypointsList.join('|')}';
      }
      final url =
          '$_directionsUrl?origin=$originStr&destination=$destinationStr$waypointsStr&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final legs = route['legs'] as List;
          int totalDistance = 0;
          int totalDuration = 0;
          for (final leg in legs) {
            totalDistance += (leg['distance']['value'] as int);
            totalDuration += (leg['duration']['value'] as int);
          }
          List<int>? waypointOrder;
          if (optimizeWaypoints && route['waypoint_order'] != null) {
            waypointOrder = List<int>.from(route['waypoint_order']);
          }
          return {
            'distance': totalDistance,
            'duration': totalDuration,
            'waypoint_order': waypointOrder,
            'polyline': route['overview_polyline']['points'],
            'legs': legs,
          };
        }
      }
      return null;
    } catch (e) {
      print('[GeocodingService] Rota alma hatası: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> optimizeStopsAsWaypoints({
    required Map<String, double> driverLocation,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      if (stops.isEmpty) return stops;

      print(
          '[GeocodingService] Unified Route Optimization Service ile ${stops.length} durak optimize ediliyor...');

      final optimizedStops =
          await UnifiedRouteOptimizationService.optimizeRoute(
        driverLocation: driverLocation,
        stops: stops,
        useGoogleApi: true,
      );

      if (optimizedStops.isNotEmpty) {
        final stats =
            UnifiedRouteOptimizationService.getRouteStatistics(optimizedStops);
        print(
            '[GeocodingService] ✅ ${optimizedStops.length} durak Unified Service ile optimize edildi');
        print(
            '[GeocodingService] 📊 Optimizasyon: ${stats['optimizationMethod']} - ${stats['totalDistance']?.toStringAsFixed(2)} km');
        return optimizedStops;
      }

      print(
          '[GeocodingService] ⚠️ Unified service başarısız, orijinal algoritma kullanılıyor');
      final sortedStops = List<Map<String, dynamic>>.from(stops);
      sortedStops.sort((a, b) {
        final da = _calculateDistance(
          driverLocation['latitude']!,
          driverLocation['longitude']!,
          (a['latitude'] as num).toDouble(),
          (a['longitude'] as num).toDouble(),
        );
        final db = _calculateDistance(
          driverLocation['latitude']!,
          driverLocation['longitude']!,
          (b['latitude'] as num).toDouble(),
          (b['longitude'] as num).toDouble(),
        );
        return da.compareTo(db);
      });
      final waypoints = sortedStops
          .map((stop) => {
                'latitude': stop['latitude'] as double,
                'longitude': stop['longitude'] as double,
              })
          .toList();
      final lastStop = waypoints.last;
      final waypointsForApi = waypoints.length > 1
          ? waypoints.sublist(0, waypoints.length - 1)
          : <Map<String, double>>[];
      final routeData = await getOptimizedRouteWithWaypoints(
        origin: driverLocation,
        destination: lastStop,
        waypoints: waypointsForApi,
        optimizeWaypoints: true,
      );
      if (routeData != null && routeData['waypoint_order'] != null) {
        final waypointOrder = routeData['waypoint_order'] as List<int>;
        final optimizedStops = <Map<String, dynamic>>[];
        for (final idx in waypointOrder) {
          if (idx >= 0 && idx < waypointsForApi.length) {
            final wp = waypointsForApi[idx];
            final original = sortedStops.firstWhere(
              (s) =>
                  (s['latitude'] as num).toDouble() == wp['latitude'] &&
                  (s['longitude'] as num).toDouble() == wp['longitude'],
              orElse: () => sortedStops.first,
            );
            optimizedStops.add(original);
          }
        }
        if (sortedStops.length > 1) {
          optimizedStops.add(sortedStops.last);
        }
        for (int i = 0; i < optimizedStops.length; i++) {
          optimizedStops[i]['order'] = i + 1;
          optimizedStops[i]['estimated_distance'] = routeData['distance'];
          optimizedStops[i]['estimated_duration'] = routeData['duration'];
        }
        print(
            '[GeocodingService] ${sortedStops.length} durak waypoints ile optimize edildi');
        return optimizedStops;
      }
      return _sortStopsByDistance(driverLocation, sortedStops);
    } catch (e) {
      print('[GeocodingService] Waypoints optimizasyon hatası: $e');
      return _sortStopsByDistance(driverLocation, stops);
    }
  }

  static List<Map<String, dynamic>> _sortStopsByDistance(
    Map<String, double> driverLocation,
    List<Map<String, dynamic>> stops,
  ) {
    final sortedStops = List<Map<String, dynamic>>.from(stops);
    sortedStops.sort((a, b) {
      final distanceA = _calculateDistance(
        driverLocation['latitude']!,
        driverLocation['longitude']!,
        a['latitude'] as double,
        a['longitude'] as double,
      );
      final distanceB = _calculateDistance(
        driverLocation['latitude']!,
        driverLocation['longitude']!,
        b['latitude'] as double,
        b['longitude'] as double,
      );
      return distanceA.compareTo(distanceB);
    });
    for (int i = 0; i < sortedStops.length; i++) {
      sortedStops[i]['order'] = i + 1;
    }
    return sortedStops;
  }

  static double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  static String generateNavigationUrl({
    required Map<String, double> origin,
    required List<Map<String, dynamic>> waypoints,
    Map<String, double>? destination,
  }) {
    final originStr = '${origin['latitude']},${origin['longitude']}';
    String waypointsStr = '';
    if (waypoints.isNotEmpty) {
      final waypointsList = waypoints
          .map((wp) => '${wp['latitude']},${wp['longitude']}')
          .toList();
      waypointsStr = waypointsList.join('|');
    }
    String destinationStr = '';
    if (destination != null) {
      destinationStr = '${destination['latitude']},${destination['longitude']}';
    } else if (waypoints.isNotEmpty) {
      final lastWaypoint = waypoints.last;
      destinationStr =
          '${lastWaypoint['latitude']},${lastWaypoint['longitude']}';
    }
    if (waypointsStr.isNotEmpty && destinationStr.isNotEmpty) {
      return 'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destinationStr&waypoints=$waypointsStr&key=${ConfigService.googleMapsApiKey}';
    } else if (destinationStr.isNotEmpty) {
      return 'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destinationStr&key=${ConfigService.googleMapsApiKey}';
    }
    return 'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&key=${ConfigService.googleMapsApiKey}';
  }

  static List<Map<String, double>> decodePolyline(String polyline) {
    List<Map<String, double>> points = [];
    int index = 0;
    int len = polyline.length;
    int lat = 0;
    int lng = 0;
    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add({
        'latitude': lat / 1E5,
        'longitude': lng / 1E5,
      });
    }
    return points;
  }

  static Future<Map<String, double>?> validateAndFixCoordinates({
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      if (latitude != null &&
          longitude != null &&
          latitude != 0.0 &&
          longitude != 0.0 &&
          latitude.abs() <= 90 &&
          longitude.abs() <= 180) {
        print(
            '[GeocodingService] ✅ Koordinatlar geçerli: $latitude, $longitude');
        return {
          'latitude': latitude,
          'longitude': longitude,
        };
      }
      if (address.trim().isNotEmpty) {
        print(
            '[GeocodingService] 🔄 Koordinatlar geçersiz, adresten alınıyor: $address');
        final coordinates = await getCoordinatesFromAddress(address);
        if (coordinates != null) {
          print(
              '[GeocodingService] ✅ Adres koordinatlara çevrildi: $coordinates');
          return coordinates;
        }
      }
      print('[GeocodingService] ❌ Koordinat düzeltme başarısız');
      return null;
    } catch (e) {
      print('[GeocodingService] ❌ Koordinat doğrulama hatası: $e');
      return null;
    }
  }

  static Future<void> fixStopCoordinates(String regionId) async {
    try {
      print('[GeocodingService] 🔧 Durak koordinatları düzeltiliyor...');
      final firestore = FirebaseFirestore.instance;
      final stopsSnapshot = await firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      int fixedCount = 0;
      int totalCount = stopsSnapshot.docs.length;
      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();
        final latitude = data['latitude'] as double?;
        final longitude = data['longitude'] as double?;
        final address = data['address'] as String?;
        if (latitude == null ||
            longitude == null ||
            latitude == 0.0 ||
            longitude == 0.0) {
          if (address != null && address.trim().isNotEmpty) {
            print(
                '[GeocodingService] 🔄 Durak düzeltiliyor: ${doc.id} - $address');
            final coordinates = await getCoordinatesFromAddress(address);
            if (coordinates != null) {
              await doc.reference.update({
                'latitude': coordinates['latitude'],
                'longitude': coordinates['longitude'],
                'lastUpdated': FieldValue.serverTimestamp(),
                'coordinatesFixed': true,
              });
              fixedCount++;
              print(
                  '[GeocodingService] ✅ Durak koordinatları düzeltildi: ${doc.id}');
            } else {
              print(
                  '[GeocodingService] ❌ Durak koordinatları düzeltilemedi: ${doc.id}');
            }
          }
        }
      }
      print(
          '[GeocodingService] 🎉 Koordinat düzeltme tamamlandı: $fixedCount/$totalCount durak düzeltildi');
    } catch (e) {
      print('[GeocodingService] ❌ Toplu koordinat düzeltme hatası: $e');
    }
  }

  static Future<bool> fixSingleStopCoordinates(String stopId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final stopDoc =
          await firestore.collection('enhanced_stops').doc(stopId).get();
      if (!stopDoc.exists) {
        print('[GeocodingService] ❌ Durak bulunamadı: $stopId');
        return false;
      }
      final data = stopDoc.data()!;
      final address = data['address'] as String?;
      if (address == null || address.trim().isEmpty) {
        print('[GeocodingService] ❌ Durak adresi boş: $stopId');
        return false;
      }
      final coordinates = await getCoordinatesFromAddress(address);
      if (coordinates != null) {
        await stopDoc.reference.update({
          'latitude': coordinates['latitude'],
          'longitude': coordinates['longitude'],
          'lastUpdated': FieldValue.serverTimestamp(),
          'coordinatesFixed': true,
        });
        print('[GeocodingService] ✅ Durak koordinatları düzeltildi: $stopId');
        return true;
      }
      print('[GeocodingService] ❌ Durak koordinatları düzeltilemedi: $stopId');
      return false;
    } catch (e) {
      print('[GeocodingService] ❌ Durak koordinat düzeltme hatası: $e');
      return false;
    }
  }
}





