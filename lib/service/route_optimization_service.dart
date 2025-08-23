import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/stop_model.dart';

class RouteOptimizationService {
  static const String _firebaseFunctionsUrl =
      'https://us-central1-servis-takip-uygulama.cloudfunctions.net';
  static const String _googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ',
  );
  static const double _earthRadius = 6371000;
  Future<Map<String, dynamic>?> optimizeRouteWithFirebase(
    Position currentPosition,
    List<StopModel> stops,
  ) async {
    if (stops.isEmpty) return null;
    try {
      final origin = {
        'lat': currentPosition.latitude,
        'lng': currentPosition.longitude,
      };
      final waypoints = stops
          .map((stop) => {
                'lat': stop.lat,
                'lng': stop.lng,
                'stopId': stop.id,
              })
          .toList();
      final response = await http.post(
        Uri.parse('$_firebaseFunctionsUrl/createRoute'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'origin': origin,
          'waypoints': waypoints,
          'optimize': true,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Firebase Functions hatası: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Rota optimizasyon hatası: $e');
      return null;
    }
  }

  Future<List<StopModel>> optimizeRouteFromCurrentLocation(
    Position currentPosition,
    List<StopModel> stops,
  ) async {
    if (stops.isEmpty) return [];
    try {
      final routeData = await optimizeRouteWithFirebase(currentPosition, stops);
      if (routeData != null && routeData['waypoint_order'] != null) {
        final waypointOrder = List<int>.from(routeData['waypoint_order']);
        final optimizedStops = <StopModel>[];
        for (final index in waypointOrder) {
          if (index < stops.length) {
            optimizedStops.add(stops[index]);
          }
        }
        return optimizedStops;
      }
      final nearestStop = _findNearestStop(currentPosition, stops);
      final remainingStops =
          stops.where((stop) => stop.id != nearestStop.id).toList();
      final optimizedRoute = await _solveTSP([nearestStop, ...remainingStops]);
      return optimizedRoute;
    } catch (e) {
      print('Rota optimizasyon hatası: $e');
      return stops;
    }
  }

  StopModel _findNearestStop(Position currentPosition, List<StopModel> stops) {
    double minDistance = double.infinity;
    StopModel nearestStop = stops.first;
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

  Future<List<StopModel>> _solveTSP(List<StopModel> stops) async {
    if (stops.length <= 2) return stops;
    final distanceMatrix = await _createDistanceMatrix(stops);
    List<int> route = _nearestNeighborTSP(distanceMatrix);
    route = _twoOptOptimization(route, distanceMatrix);
    return route.map((index) => stops[index]).toList();
  }

  Future<List<List<double>>> _createDistanceMatrix(
      List<StopModel> stops) async {
    final matrix = List.generate(
      stops.length,
      (i) => List.generate(stops.length, (j) => 0.0),
    );
    for (int i = 0; i < stops.length; i++) {
      for (int j = 0; j < stops.length; j++) {
        if (i != j) {
          matrix[i][j] = _calculateDistance(
            stops[i].lat,
            stops[i].lng,
            stops[j].lat,
            stops[j].lng,
          );
        }
      }
    }
    return matrix;
  }

  List<int> _nearestNeighborTSP(List<List<double>> distanceMatrix) {
    final n = distanceMatrix.length;
    final visited = List.filled(n, false);
    final route = <int>[];
    int current = 0;
    visited[current] = true;
    route.add(current);
    for (int i = 1; i < n; i++) {
      double minDistance = double.infinity;
      int nextCity = -1;
      for (int j = 0; j < n; j++) {
        if (!visited[j] && distanceMatrix[current][j] < minDistance) {
          minDistance = distanceMatrix[current][j];
          nextCity = j;
        }
      }
      if (nextCity != -1) {
        visited[nextCity] = true;
        route.add(nextCity);
        current = nextCity;
      }
    }
    return route;
  }

  List<int> _twoOptOptimization(
      List<int> route, List<List<double>> distanceMatrix) {
    bool improved = true;
    List<int> bestRoute = List.from(route);
    while (improved) {
      improved = false;
      for (int i = 1; i < route.length - 2; i++) {
        for (int j = i + 1; j < route.length; j++) {
          if (j - i == 1) continue;
          final newRoute = _twoOptSwap(bestRoute, i, j);
          if (_calculateTotalDistance(newRoute, distanceMatrix) <
              _calculateTotalDistance(bestRoute, distanceMatrix)) {
            bestRoute = newRoute;
            improved = true;
          }
        }
      }
    }
    return bestRoute;
  }

  List<int> _twoOptSwap(List<int> route, int i, int j) {
    final newRoute = <int>[];
    for (int k = 0; k <= i - 1; k++) {
      newRoute.add(route[k]);
    }
    for (int k = j; k >= i; k--) {
      newRoute.add(route[k]);
    }
    for (int k = j + 1; k < route.length; k++) {
      newRoute.add(route[k]);
    }
    return newRoute;
  }

  double _calculateTotalDistance(
      List<int> route, List<List<double>> distanceMatrix) {
    double totalDistance = 0.0;
    for (int i = 0; i < route.length - 1; i++) {
      totalDistance += distanceMatrix[route[i]][route[i + 1]];
    }
    return totalDistance;
  }

  Future<void> _enrichRouteWithDirections(List<StopModel> route) async {
    if (route.length < 2) return;
    try {
      for (int i = 0; i < route.length - 1; i++) {
        final origin = route[i];
        final destination = route[i + 1];
        final directions = await _getDirections(
          origin.lat,
          origin.lng,
          destination.lat,
          destination.lng,
        );
        if (directions != null) {}
      }
    } catch (e) {}
  }

  Future<Map<String, dynamic>?> _getDirections(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=$originLat,$originLng&destination=$destLat,$destLng&key=$_googleMapsApiKey&mode=driving&language=tr';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          return {
            'polyline': route['overview_polyline']['points'],
            'distance': leg['distance']['value'],
            'duration': leg['duration']['value'],
          };
        }
      }
    } catch (e) {}
    return null;
  }

  Future<int> calculateEstimatedTime(
      Position currentPosition, List<StopModel> stops) async {
    if (stops.isEmpty) return 0;
    try {
      final optimizedRoute =
          await optimizeRouteFromCurrentLocation(currentPosition, stops);
      int totalDuration = 0;
      if (optimizedRoute.isNotEmpty) {
        final firstStopDirections = await _getDirections(
          currentPosition.latitude,
          currentPosition.longitude,
          optimizedRoute.first.lat,
          optimizedRoute.first.lng,
        );
        if (firstStopDirections != null) {
          totalDuration += firstStopDirections['duration'] as int;
        }
      }
      for (final stop in optimizedRoute) {
        totalDuration += 120;
      }
      return (totalDuration / 60).round();
    } catch (e) {
      return stops.length * 5;
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  List<Map<String, double>> decodePolyline(String polyline) {
    final points = <Map<String, double>>[];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < polyline.length) {
      int shift = 0;
      int result = 0;
      int byte;
      do {
        byte = polyline.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += deltaLat;
      shift = 0;
      result = 0;
      do {
        byte = polyline.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += deltaLng;
      points.add({
        'latitude': lat / 1E5,
        'longitude': lng / 1E5,
      });
    }
    return points;
  }

  Future<Map<String, dynamic>> getRouteStatistics(List<StopModel> route) async {
    if (route.isEmpty) {
      return {
        'totalDistance': 0.0,
        'totalDuration': 0,
        'averageStopDistance': 0.0,
        'stopCount': 0,
      };
    }
    double totalDistance = 0.0;
    int totalDuration = 0;
    for (final stop in route) {}
    final averageStopDistance =
        route.length > 1 ? totalDistance / (route.length - 1) : 0.0;
    return {
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
      'averageStopDistance': averageStopDistance,
      'stopCount': route.length,
    };
  }
}
