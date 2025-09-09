import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
class SimulationService {
  static Timer? _simulationTimer;
  static bool _isSimulationActive = false;
  static List<LatLng> _simulationRoute = [];
  static int _currentRouteIndex = 0;
  static LatLng? _currentSimulatedLocation;
  static double _currentHeading = 0.0;
  static double _simulationSpeedKmh = 40.0;
  static double _intervalSeconds = 1.0;
  static String? _currentDriverId;
  static String? _currentRegionId;
  static String? _currentVehiclePlate;
  static StreamController<SimulationData>? _simulationController;
  static Map<String, SimulationData> _activeSimulations = {};
  static StreamController<Map<String, SimulationData>>?
      _globalSimulationController;
  static Future<void> startDriverSimulation({
    required String driverId,
    required List<LatLng> route,
    Duration interval = const Duration(seconds: 1),
    double speed = 40.0,
    String? regionId,
    String? vehiclePlate,
  }) async {
    if (_isSimulationActive) {
      await stopSimulation();
    }
    if (route.length < 2) {
      throw ArgumentError('Simülasyon için en az iki rota noktası gerekir.');
    }
    _currentDriverId = driverId;
    _currentRegionId = regionId;
    _currentVehiclePlate = vehiclePlate;
    print(
        '🚀 Simülasyon başlatılıyor - Şoför: $driverId, Rota noktası: ${route.length}');
    _simulationRoute = List<LatLng>.from(route);
    _currentRouteIndex = 0;
    _simulationSpeedKmh = speed;
    _intervalSeconds = interval.inMilliseconds / 1000.0;
    _isSimulationActive = true;
    _simulationController = StreamController<SimulationData>.broadcast();
    _currentSimulatedLocation = route.first;
    _currentHeading = _calcBearing(route[0], route[1]);
    await _updateDriverLocationInFirebase(
      driverId,
      _currentSimulatedLocation!,
      _currentHeading,
      _kmhToMps(_simulationSpeedKmh),
    );
    _simulationTimer = Timer.periodic(interval, (_) => _updateSimulationStep());
    _emitToStream();
    print('🚀 Simülasyon başlatıldı: $driverId, nokta sayısı: ${route.length}');
  }
  static Future<void> stopSimulation() async {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (_currentDriverId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('live_locations')
            .doc(_currentDriverId)
            .set({
          'isSimulation': false,
          'isActive': false,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    await _simulationController?.close();
    _simulationController = null;
    _isSimulationActive = false;
    _simulationRoute = [];
    _currentRouteIndex = 0;
    _currentSimulatedLocation = null;
    _currentHeading = 0.0;
    _currentDriverId = null;
    _currentRegionId = null;
    _currentVehiclePlate = null;
    print('⏹️ Simülasyon durduruldu');
  }
  static Future<void> _updateSimulationStep() async {
    if (!_isSimulationActive ||
        _currentDriverId == null ||
        _currentRouteIndex >= _simulationRoute.length - 1) {
      await stopSimulation();
      return;
    }
    final current =
        _currentSimulatedLocation ?? _simulationRoute[_currentRouteIndex];
    final next = _simulationRoute[_currentRouteIndex + 1];
    final distance = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      next.latitude,
      next.longitude,
    );
    final speedMps = _kmhToMps(_simulationSpeedKmh);
    final stepDistance = speedMps * _intervalSeconds;
    final newHeading = _calcBearing(current, next);
    LatLng newLocation;
    if (distance <= stepDistance) {
      newLocation = next;
      _currentRouteIndex++;
    } else {
      final fraction = (stepDistance / distance).clamp(0.0, 1.0);
      newLocation = _interpolate(current, next, fraction);
    }
    _currentSimulatedLocation = newLocation;
    _currentHeading = newHeading;
    await _updateDriverLocationInFirebase(
      _currentDriverId!,
      newLocation,
      newHeading,
      speedMps,
    );
    _emitToStream();
    if (_currentRouteIndex >= _simulationRoute.length - 1) {
      await stopSimulation();
    }
  }
  static void _emitToStream() {
    if (_simulationController == null || _currentSimulatedLocation == null)
      return;
    final progress = _simulationRoute.isEmpty
        ? 0.0
        : _currentRouteIndex / (_simulationRoute.length - 1);
    _simulationController!.add(
      SimulationData(
        location: _currentSimulatedLocation!,
        heading: _currentHeading,
        speed: _simulationSpeedKmh,
        routeProgress: progress,
        isActive: _isSimulationActive,
      ),
    );
  }
  static Future<void> _updateDriverLocationInFirebase(
    String driverId,
    LatLng location,
    double heading,
    double speedMps,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .set({
        'lat': location.latitude,
        'lng': location.longitude,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'heading': heading,
        'speed': speedMps,
        'isActive': true,
        'isSimulation': true,
        'timestamp': FieldValue.serverTimestamp(),
        if (_currentRegionId != null) 'regionId': _currentRegionId,
        if (_currentVehiclePlate != null) 'vehiclePlate': _currentVehiclePlate,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Firebase konum güncelleme hatası: $e');
    }
  }
  static Future<void> simulateStopVisit({
    required String driverId,
    required String stopId,
    required LatLng stopLocation,
    Duration waitTime = const Duration(seconds: 30),
  }) async {
    if (!_isSimulationActive || _currentDriverId != driverId) return;
    await _simulateApproachToStop(stopLocation);
    try {
      await FirebaseFirestore.instance.collection('route_history').add({
        'driverId': driverId,
        'stopId': stopId,
        'visitedAt': FieldValue.serverTimestamp(),
        'location': GeoPoint(stopLocation.latitude, stopLocation.longitude),
        'distanceFromStop': 0.0,
        'isSimulation': true,
      });
    } catch (_) {}
    await Future.delayed(waitTime);
  }
  static Future<void> _simulateApproachToStop(LatLng stopLocation) async {
    if (_currentSimulatedLocation == null || !_isSimulationActive) return;
    final steps = _generateApproachPoints(
      _currentSimulatedLocation!,
      stopLocation,
      5,
    );
    for (final p in steps) {
      if (!_isSimulationActive || _currentDriverId == null) break;
      _currentSimulatedLocation = p;
      _currentHeading = _calcBearing(_currentSimulatedLocation!, stopLocation);
      await _updateDriverLocationInFirebase(
        _currentDriverId!,
        p,
        _currentHeading,
        _kmhToMps(_simulationSpeedKmh * 0.5),
      );
      _emitToStream();
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  static double _kmhToMps(double kmh) => kmh * 1000 / 3600;
  static double _normalizeBearing(double b) => b < 0 ? b + 360 : b;
  static double _calcBearing(LatLng a, LatLng b) =>
      _normalizeBearing(Geolocator.bearingBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      ));
  static LatLng _interpolate(LatLng start, LatLng end, double fraction) {
    final lat1 = start.latitude * pi / 180;
    final lon1 = start.longitude * pi / 180;
    final lat2 = end.latitude * pi / 180;
    final lon2 = end.longitude * pi / 180;
    final d = 2 *
        asin(sqrt(pow(sin((lat2 - lat1) / 2), 2) +
            cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)));
    if (d == 0) return start;
    final A = sin((1 - fraction) * d) / sin(d);
    final B = sin(fraction * d) / sin(d);
    final x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2);
    final y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2);
    final z = A * sin(lat1) + B * sin(lat2);
    final lat = atan2(z, sqrt(x * x + y * y));
    final lon = atan2(y, x);
    return LatLng(lat * 180 / pi, lon * 180 / pi);
  }
  static List<LatLng> _generateApproachPoints(
    LatLng start,
    LatLng end,
    int steps,
  ) {
    final points = <LatLng>[];
    for (int i = 1; i <= steps; i++) {
      points.add(_interpolate(start, end, i / steps));
    }
    return points;
  }
  static List<LatLng> generateRandomRoute({
    required LatLng center,
    required int pointCount,
    double radiusKm = 5.0,
  }) {
    final random = Random();
    final route = <LatLng>[center];
    for (int i = 0; i < pointCount - 1; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = random.nextDouble() * radiusKm * 1000;
      final lat = center.latitude + (distance * cos(angle)) / 111320;
      final lng = center.longitude +
          (distance * sin(angle)) / (111320 * cos(center.latitude * pi / 180));
      route.add(LatLng(lat, lng));
    }
    return route;
  }
  static Stream<SimulationData>? getSimulationStream() =>
      _simulationController?.stream;
  static bool get isSimulationActive => _isSimulationActive;
  static LatLng? get currentLocation => _currentSimulatedLocation;
  static double get currentHeading => _currentHeading;
  static double get routeProgress {
    if (_simulationRoute.isEmpty) return 0.0;
    return _currentRouteIndex / (_simulationRoute.length - 1);
  }
  static void updateSimulationSpeed(double speedKmh) {
    _simulationSpeedKmh = speedKmh;
  }
  static Future<void> clearSimulationData(String driverId) async {
    try {
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .set({'isSimulation': false, 'isActive': false},
              SetOptions(merge: true));
      final historyQuery = await FirebaseFirestore.instance
          .collection('route_history')
          .where('driverId', isEqualTo: driverId)
          .where('isSimulation', isEqualTo: true)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in historyQuery.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Simülasyon verileri temizleme hatası: $e');
    }
  }
}
class SimulationData {
  final LatLng location;
  final double heading;
  final double speed;
  final double routeProgress;
  final bool isActive;
  final DateTime timestamp;
  SimulationData({
    required this.location,
    required this.heading,
    required this.speed,
    required this.routeProgress,
    required this.isActive,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  Map<String, dynamic> toMap() {
    return {
      'lat': location.latitude,
      'lng': location.longitude,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'heading': heading,
      'speed': speed,
      'routeProgress': routeProgress,
      'isActive': isActive,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
  factory SimulationData.fromMap(Map<String, dynamic> map) {
    final lat = (map['lat'] ?? map['latitude'])?.toDouble();
    final lng = (map['lng'] ?? map['longitude'])?.toDouble();
    return SimulationData(
      location: LatLng(lat ?? 0.0, lng ?? 0.0),
      heading: (map['heading'] ?? 0).toDouble(),
      speed: (map['speed'] ?? 0).toDouble(),
      routeProgress: (map['routeProgress'] ?? 0).toDouble(),
      isActive: (map['isActive'] ?? false) as bool,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch) as int,
      ),
    );
  }
  @override
  String toString() =>
      'SimulationData(loc: $location, heading: $heading, speed(km/h): $speed, progress: $routeProgress)';
}

// Updated

