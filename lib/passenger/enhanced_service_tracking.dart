import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import '../service/location_service.dart';
import '../service/user_session.dart';
import '../service/avatar_marker_service.dart';
import '../service/simple_stop_service.dart';
import '../service/enhanced_stop_management_service.dart';
import '../utils/app_colors.dart';

const String kGoogleApiKey = 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ';
const int kDirectionsDebounceMs = 1500;

class EnhancedServiceTracking extends StatefulWidget {
  final String passengerId;
  final String regionId;
  final bool hideAppBar;
  const EnhancedServiceTracking({
    super.key,
    required this.passengerId,
    required this.regionId,
    this.hideAppBar = false,
  });
  @override
  State<EnhancedServiceTracking> createState() =>
      _EnhancedServiceTrackingState();
}

class _EnhancedServiceTrackingState extends State<EnhancedServiceTracking> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _estimatedArrival;
  int? _etaRemainingMinutes;
  bool _isLoading = false;
  List<Map<String, dynamic>> _allStops = [];
  bool _isDriverMoving = false;
  String _driverStatus = 'Bekliyor';
  String? _currentStopAddress;
  int _completedStops = 0;
  int _totalStops = 0;
  double _routeProgress = 0.0;
  Set<String> _completedStopsSet = <String>{};
  Set<String> _completedStopIds = {};
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _serviceStatusStream;
  StreamSubscription? _stopsStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _liveLocationDocStream;
  Timer? _locationUpdateTimer;
  Timer? _etaMinuteTicker;
  Timer? _etaRecomputeTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _stopLogsSubscription;
  Timer? _stopsRedrawDebounce;
  Timer? _directionsDebounce;
  final LocationService _locationService = LocationService();
  LatLng? _driverLatLng;
  LatLng? _myStopLatLng;
  bool _isDrawingRoute = false;
  bool _followDriverCamera = true;
  bool _isTestMode = false;
  Timer? _testTimer;
  Timer? _proximityCheckTimer;
  List<LatLng> _lastRoutePoints = [];
  DateTime? _lastRouteUpdateTime;
  String _vehiclePlate = '';
  String? _activeDriverId;
  double _lastDriverSpeedKmh = 28.0;
  String _resolvedRegionId = '';
  List<LatLng> _recentDriverPositions = [];
  static const int _maxRecentPositions = 5;
  static const Duration _movementAnalysisWindow = Duration(minutes: 2);
  bool get _isApiKeyValid =>
      kGoogleApiKey.isNotEmpty && !kGoogleApiKey.contains('YOUR_');
  @override
  void initState() {
    super.initState();
    _initializeTracking();
    _proximityCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkDriverProximityToStops();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _serviceStatusStream?.cancel();
    _stopsStream?.cancel();
    _liveLocationDocStream?.cancel();
    _locationUpdateTimer?.cancel();
    _etaMinuteTicker?.cancel();
    _etaRecomputeTimer?.cancel();
    _stopLogsSubscription?.cancel();
    _directionsDebounce?.cancel();
    _stopsRedrawDebounce?.cancel();
    _testTimer?.cancel();
    _proximityCheckTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    setState(() => _isLoading = true);
    try {
      await _resolveRegionId();
      Future.microtask(_getCurrentLocation);
      _startServiceStatusTracking();
      _startLocationTracking();
      _startStopsTracking();
      Future.microtask(_loadAllStops);
    } catch (e) {
      debugPrint('Takip başlatma hatası: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveRegionId() async {
    String rid = widget.regionId;
    if (rid.isEmpty) rid = UserSession.regionId ?? '';
    if (rid.isEmpty) {
      try {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.passengerId)
            .get();
        if (u.exists) rid = (u.data()?['regionId'] as String?) ?? '';
      } catch (_) {}
    }
    if (rid.isEmpty) {
      try {
        final p = await FirebaseFirestore.instance
            .collection('passengers')
            .doc(widget.passengerId)
            .get();
        if (p.exists) rid = (p.data()?['regionId'] as String?) ?? '';
      } catch (_) {}
    }
    setState(() => _resolvedRegionId = rid);
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      setState(() => _currentPosition = position);
      _debouncedRouteAndEta();
      if (_mapController != null && position != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            16.0,
          ),
        );
      }
    } catch (e) {
      debugPrint('Konum alma hatası: $e');
    }
  }

  Future<void> _loadAllStops() async {
    try {
      List<Map<String, dynamic>> fetchedStops = [];
      try {
        final String regionForStops =
            _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
        final advStops = await EnhancedStopManagementService.getStopsForRegion(
            regionForStops);
        fetchedStops = advStops;
      } catch (e) {
        debugPrint('Enhanced stops yüklenemedi, simple fallback: $e');
        final String regionForStops =
            _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
        fetchedStops =
            await SimpleStopService.getStopsForRegion(regionForStops);
      }
      var stops = fetchedStops
          .where((s) => (s['temporarilyInactive'] ?? false) != true)
          .toList();
      if (stops.isEmpty) {
        try {
          final mine = await EnhancedStopManagementService.getStopForPassenger(
              widget.passengerId);
          if (mine != null) {
            stops = [mine];
          }
        } catch (_) {}
      }
      stops = _dedupeStops(stops);
      setState(() {
        _allStops = stops;
        _totalStops = stops.length;
        _completedStops =
            stops.where((stop) => stop['isCompleted'] == true).length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });
      await _updateMapWithAllStops();
    } catch (e) {
      debugPrint('Duraklar yükleme hatası: $e');
    }
  }

  void _startLocationTracking() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final position = await _locationService.getCurrentLocation();
        if (position != null && mounted) {
          setState(() => _currentPosition = position);
        }
      } catch (e) {
        debugPrint('Konum takip hatası: $e');
      }
    });
  }

  void _startServiceStatusTracking() {
    final String rid =
        _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
    _serviceStatusStream = FirebaseFirestore.instance
        .collection('service_status')
        .doc(rid)
        .snapshots()
        .listen(
      (snapshot) async {
        final data = snapshot.data();
        if (snapshot.exists && data != null) {
          final newDriverId = data['driverId'] as String?;
          _vehiclePlate = (data['vehiclePlate'] as String?) ?? _vehiclePlate;
          if (newDriverId != null && newDriverId.isNotEmpty) {
            if (_activeDriverId != newDriverId) {
              _activeDriverId = newDriverId;
              _subscribeToLiveLocation(newDriverId);
              await _refreshDriverStops();
              _debouncedRouteAndEta();
              _startEtaAutoRecompute();
              _startStopLogsTracking();
            }
          } else {
            await _fallbackSubscribeToRegionLatestLiveLocation();
            await _refreshDriverStops();
          }
        } else {
          await _fallbackSubscribeToRegionLatestLiveLocation();
          await _refreshDriverStops();
        }
      },
      onError: (error) => debugPrint('Servis durumu takip hatası: $error'),
    );
  }

  Future<void> _fallbackSubscribeToRegionLatestLiveLocation() async {
    try {
      Query<Map<String, dynamic>> base =
          FirebaseFirestore.instance.collection('live_locations');
      final rid =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
      if (rid.isNotEmpty) base = base.where('regionId', isEqualTo: rid);
      final q =
          await base.orderBy('timestamp', descending: true).limit(1).get();
      if (q.docs.isNotEmpty) {
        final doc = q.docs.first;
        final driverId = (doc.data()['driverId'] as String?) ?? doc.id;
        if (driverId.isNotEmpty && _activeDriverId != driverId) {
          _activeDriverId = driverId;
          _subscribeToLiveLocation(driverId);
        }
      }
    } catch (e) {
      debugPrint('Fallback canlı konum abonelik hatası: $e');
    }
  }

  void _startStopsTracking() {
    final rid =
        _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
    _stopsStream = FirebaseFirestore.instance
        .collection('enhanced_stops')
        .where('regionId', isEqualTo: rid)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen(
      (snapshot) async {
        _stopsRedrawDebounce?.cancel();
        _stopsRedrawDebounce = Timer(const Duration(milliseconds: 400), () {
          if (mounted) {
            _refreshDriverStops();
          }
        });
      },
      onError: (error) => debugPrint('Duraklar takip hatası: $error'),
    );
    try {
      FirebaseFirestore.instance
          .collection('permissions')
          .where('userId', isEqualTo: widget.passengerId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen((snap) {
        final now = DateTime.now();
        bool hasActive = false;
        for (final d in snap.docs) {
          final m = d.data();
          final String type = (m['type'] as String?) ?? '';
          final int hour = now.hour;
          final bool isMorning = hour < 12;
          switch (type) {
            case 'allToday':
            case 'vacation':
              hasActive = true;
              break;
            case 'morningToday':
              hasActive = isMorning;
              break;
            case 'eveningToday':
              hasActive = !isMorning;
              break;
          }
          if (hasActive) break;
        }
        if (hasActive) {
          _etaMinuteTicker?.cancel();
          _etaRecomputeTimer?.cancel();
          if (mounted) {
            setState(() {
              _estimatedArrival = null;
              _etaRemainingMinutes = null;
            });
          }
        } else {
          _debouncedRouteAndEta();
          _startEtaAutoRecompute();
        }
      });
    } catch (e) {
      debugPrint('İzin dinleme hatası: $e');
    }
  }

  void _startStopLogsTracking() {
    _stopLogsSubscription?.cancel();
    if (_activeDriverId == null || _activeDriverId!.isEmpty) return;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    _stopLogsSubscription = FirebaseFirestore.instance
        .collection('stop_logs')
        .where('driverId', isEqualTo: _activeDriverId)
        .where('arrivedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('arrivedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots()
        .listen((snapshot) {
      final completed = <String>{};
      for (final d in snapshot.docs) {
        final data = d.data();
        final status = data['status'] as String?;
        final stopId = data['stopId'] as String?;
        if (stopId == null) continue;
        if (status == 'completed' || status == 'arrived') {
          completed.add(stopId);
        }
      }
      if (!mounted) return;
      setState(() {
        _completedStopsSet = completed;
        _completedStops = completed.length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });
    });
  }

  void _checkDriverProximityToStops() {
    if (_driverLatLng == null || _allStops.isEmpty) return;
    double minDistance = double.infinity;
    Map<String, dynamic>? nearestStop;
    for (final stop in _allStops) {
      final stopLatLng = _extractStopLatLng(stop);
      if (stopLatLng != null) {
        final distance = Geolocator.distanceBetween(
          _driverLatLng!.latitude,
          _driverLatLng!.longitude,
          stopLatLng.latitude,
          stopLatLng.longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestStop = stop;
        }
      }
    }
    if (nearestStop != null && minDistance <= 20.0 && !_isDriverMoving) {
      setState(() {
        _driverStatus = 'Durakta';
        _currentStopAddress = (nearestStop!['address'] as String?) ?? 'Durak';
      });
      _updateProgressWhenArrivingAtStop(nearestStop!);
    }
  }

  void _updateProgressWhenArrivingAtStop(Map<String, dynamic> stop) {
    final String stopId = stop['id'] as String? ?? '';
    if (stopId.isNotEmpty && !_completedStopsSet.contains(stopId)) {
      setState(() {
        _completedStopsSet.add(stopId);
        _completedStops = _completedStopsSet.length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });
      _logStopArrival(stopId);
    }
  }

  Future<void> _logStopArrival(String stopId) async {
    try {
      if (_activeDriverId == null || _activeDriverId!.isEmpty) return;
      await FirebaseFirestore.instance.collection('stop_logs').add({
        'driverId': _activeDriverId,
        'stopId': stopId,
        'status': 'arrived',
        'arrivedAt': FieldValue.serverTimestamp(),
        'regionId': UserSession.regionId,
        'passengerId': widget.passengerId,
      });
    } catch (e) {
      print('❌ Durak varış kaydı hatası: $e');
    }
  }

  Future<void> _refreshDriverStops() async {
    try {
      if (_activeDriverId == null || _activeDriverId!.isEmpty) {
        await _loadAllStops();
        return;
      }
      final driverStops =
          await SimpleStopService.getStopsForDriver(_activeDriverId!);
      var filtered = driverStops
          .where((s) => (s['temporarilyInactive'] ?? false) != true)
          .where((s) => (s['latitude'] != null && s['longitude'] != null))
          .toList();
      try {
        final mine = await EnhancedStopManagementService.getStopForPassenger(
            widget.passengerId);
        if (mine != null) filtered.add(mine);
      } catch (_) {}
      filtered = _dedupeStops(filtered);
      if (!mounted) return;
      setState(() {
        _allStops = filtered;
        _totalStops = filtered.length;
        _completedStops = _completedStopIds.length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });
      await _updateMapWithAllStops();
      _debouncedRouteAndEta();
    } catch (e) {
      debugPrint('Aktif şoför duraklarını yenileme hatası: $e');
    }
  }

  List<Map<String, dynamic>> _dedupeStops(List<Map<String, dynamic>> list) {
    final Map<String, Map<String, dynamic>> uniq = {};
    for (final s in list) {
      final String id = (s['id'] as String?)?.trim() ?? '';
      final List<dynamic> pids = (s['passengerIds'] as List<dynamic>?) ?? [];
      final String pid = (s['passengerId'] as String?)?.trim() ??
          (pids.isNotEmpty ? pids.first.toString() : '');
      final double? lat = (s['latitude'] ?? s['lat'])?.toDouble();
      final double? lng = (s['longitude'] ?? s['lng'])?.toDouble();
      final String key = id.isNotEmpty
          ? 'id:$id'
          : (pid.isNotEmpty
              ? 'pid:$pid'
              : (lat != null && lng != null
                  ? 'geo:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
                  : s.hashCode.toString()));
      if (!uniq.containsKey(key)) {
        uniq[key] = s;
      } else {
        final prev = uniq[key]!;
        final prevTs = prev['createdAt'];
        final curTs = s['createdAt'];
        final bool isNewer = (prevTs is Timestamp && curTs is Timestamp)
            ? curTs.compareTo(prevTs) > 0
            : true;
        if (isNewer) uniq[key] = s;
      }
    }
    return uniq.values.toList();
  }

  void _startEtaAutoRecompute() {
    _etaRecomputeTimer?.cancel();
    _etaRecomputeTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      if (_driverLatLng == null || _myStopLatLng == null) return;
      if (_myStopLatLng == null) return;
      await _recomputeETA();
    });
  }

  void _subscribeToLiveLocation(String driverId) {
    _liveLocationDocStream?.cancel();
    _liveLocationDocStream = FirebaseFirestore.instance
        .collection('live_locations')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) async {
      if (_isTestMode) return;
      final data = snapshot.data();
      if (data != null) {
        final pos = _extractLatLng({
          'lat': data['lat'],
          'lng': data['lng'],
        });
        if (pos != null) {
          final num? speedMs = data['speed'] as num?;
          final num? accuracy = data['accuracy'] as num?;
          final Timestamp? timestamp = data['timestamp'] as Timestamp?;
          bool isMovingBySpeed = false;
          if (speedMs != null) {
            final double speedKmh = speedMs.toDouble() * 3.6;
            isMovingBySpeed = speedKmh > 5.0;
          }
          bool isMovingByLocation = false;
          if (_driverLatLng != null && timestamp != null) {
            final double distance = Geolocator.distanceBetween(
              _driverLatLng!.latitude,
              _driverLatLng!.longitude,
              pos.latitude,
              pos.longitude,
            );
            final double minDistance = (accuracy ?? 5.0) * 2.0;
            isMovingByLocation = distance > minDistance;
          }
          final bool isMoving = isMovingBySpeed || isMovingByLocation;
          _recentDriverPositions.add(pos);
          if (_recentDriverPositions.length > _maxRecentPositions) {
            _recentDriverPositions.removeAt(0);
          }
          final bool isMovingByTime = _analyzeMovementByTime();
          final bool finalIsMoving = isMoving || isMovingByTime;
          setState(() {
            _driverLatLng = pos;
            _isDriverMoving = finalIsMoving;
            _driverStatus = finalIsMoving ? 'Hareket Halinde' : 'Durakta';
            _currentStopAddress = data['currentStopAddress'];
            if (speedMs != null) {
              _lastDriverSpeedKmh = (speedMs.toDouble() * 3.6).clamp(5.0, 70.0);
            }
          });
          await _updateDriverMarker(pos);
          _updateRouteAndETA();
          _debouncedRouteAndEta();
        }
      }
    }, onError: (e) => debugPrint('live_locations hata: $e'));
  }

  void _updateRouteAndETA() {
    if (_driverLatLng == null || _currentPosition == null) return;
    if (_lastRoutePoints.isEmpty || _shouldRefreshRoute()) {
      _createRouteFromCurrentToDriver();
    }
  }

  bool _shouldRefreshRoute() {
    if (_lastRoutePoints.isEmpty) return true;
    final now = DateTime.now();
    final lastUpdate = _lastRouteUpdateTime ??
        DateTime.now().subtract(const Duration(minutes: 10));
    return now.difference(lastUpdate).inMinutes > 5;
  }

  Future<void> _createRouteFromCurrentToDriver() async {
    if (_driverLatLng == null || _currentPosition == null) return;
    try {
      final origin =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final destination = _driverLatLng!;
      final route = await _getRouteFromDirections(origin, destination);
      if (route.isNotEmpty) {
        setState(() {
          _lastRoutePoints = route;
          _lastRouteUpdateTime = DateTime.now();
        });
        _drawRouteOnMap(route);
      }
    } catch (e) {
      print('❌ Rota oluşturma hatası: $e');
    }
  }

  Future<List<LatLng>> _getRouteFromDirections(
      LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=${kGoogleApiKey}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first;
          final legs = route['legs'] as List?;
          if (legs != null && legs.isNotEmpty) {
            final leg = legs.first;
            final steps = leg['steps'] as List?;
            if (steps != null) {
              final List<LatLng> points = [];
              for (final step in steps) {
                final startLocation = step['start_location'];
                points.add(LatLng(
                  startLocation['lat'].toDouble(),
                  startLocation['lng'].toDouble(),
                ));
              }
              final endLocation = legs.first['end_location'];
              points.add(LatLng(
                endLocation['lat'].toDouble(),
                endLocation['lng'].toDouble(),
              ));
              return points;
            }
          }
        }
      }
    } catch (e) {
      print('❌ Directions API hatası: $e');
    }
    return [];
  }

  Future<void> _updateMapWithAllStops() async {
    final newMarkers = <Marker>{};
    if (_currentPosition != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Konumunuz'),
        ),
      );
    }
    _myStopLatLng = null;
    for (int i = 0; i < _allStops.length; i++) {
      final stop = _allStops[i];
      final stopLatLng = _extractStopLatLng(stop);
      if (stopLatLng == null) continue;
      final bool isMyStop = (stop['passengerId'] == widget.passengerId) ||
          (List<String>.from(stop['passengerIds'] ?? [])
              .contains(widget.passengerId));
      if (isMyStop) {
        _myStopLatLng = stopLatLng;
      }
      final defaultIcon = BitmapDescriptor.defaultMarkerWithHue(
          isMyStop ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueViolet);
      newMarkers.add(
        Marker(
          markerId: MarkerId('stop_$i'),
          position: stopLatLng,
          icon: defaultIcon,
          infoWindow: InfoWindow(
            title: isMyStop ? 'Sizin Durağınız' : _formatStopTitle(stop, i + 1),
            snippet: _formatStopSnippet(stop),
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _markers = newMarkers);
    const int maxAvatarized = 30;
    final int limit = math.min(_allStops.length, maxAvatarized);
    Future.microtask(() async {
      for (int i = 0; i < limit; i++) {
        if (!mounted) return;
        final stop = _allStops[i];
        final stopLatLng = _extractStopLatLng(stop);
        if (stopLatLng == null) continue;
        final bool isMyStop = (stop['passengerId'] == widget.passengerId) ||
            (List<String>.from(stop['passengerIds'] ?? [])
                .contains(widget.passengerId));
        try {
          final avatarIcon = await AvatarMarkerService.createAvatarMarker(
            profileImageUrl: (stop['profileImageUrl'] ?? '') as String?,
            stopNumber: i + 1,
            size: 60,
          );
          if (!mounted) return;
          setState(() {
            _markers.removeWhere((m) => m.markerId.value == 'stop_$i');
            _markers.add(
              Marker(
                markerId: MarkerId('stop_$i'),
                position: stopLatLng,
                icon: avatarIcon,
                infoWindow: InfoWindow(
                  title: isMyStop
                      ? 'Sizin Durağınız'
                      : _formatStopTitle(stop, i + 1),
                  snippet: _formatStopSnippet(stop),
                ),
              ),
            );
          });
        } catch (_) {}
      }
    });
    if (_myStopLatLng == null &&
        (_estimatedArrival != null || _etaMinuteTicker != null)) {
      _etaMinuteTicker?.cancel();
      if (mounted) {
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
      }
    }
    _debouncedRouteAndEta();
  }

  Future<void> _updateDriverMarker(LatLng driverPosition) async {
    try {
      final carIcon = await AvatarMarkerService.createEmojiMarker(
        emoji: '🚌',
        size: 88,
        backgroundColor: _isDriverMoving ? Colors.green : Colors.orange,
      );
      final driverMarker = Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition,
        icon: carIcon,
        infoWindow: InfoWindow(
          title: 'Şoför${_vehiclePlate.isNotEmpty ? ' ($_vehiclePlate)' : ''}',
          snippet: _driverStatus,
        ),
      );
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'driver');
        _markers.add(driverMarker);
      });
    } catch (e) {
      debugPrint('Şoför marker güncelleme hatası: $e');
    }
  }

  void _debouncedRouteAndEta() {
    _directionsDebounce?.cancel();
    _directionsDebounce =
        Timer(const Duration(milliseconds: kDirectionsDebounceMs), () async {
      await _updateRoutePolylineViaDirections();
      await _recomputeETA();
      if (_followDriverCamera &&
          _driverLatLng != null &&
          _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _driverLatLng!, zoom: 16.0),
          ),
        );
      }
    });
  }

  Future<void> _updateRoutePolylineViaDirections() async {
    if (_isDrawingRoute) return;
    if (_driverLatLng == null) {
      if (mounted) setState(() => _polylines.clear());
      return;
    }
    _isDrawingRoute = true;
    try {
      if (_allStops.isEmpty) {
        await _ensureMyStopLatLng();
        if (_myStopLatLng != null) {
          await _drawDriverToMyStopRoute();
        } else {
          if (mounted) setState(() => _polylines.clear());
        }
        return;
      }
      final ordered = [..._allStops]..sort((a, b) {
          final int ai = (a['order'] ?? 0) as int;
          final int bi = (b['order'] ?? 0) as int;
          return ai.compareTo(bi);
        });
      final activeOrdered = ordered
          .where((s) => (s['temporarilyInactive'] ?? false) != true)
          .where((s) =>
              (s['latitude'] ?? s['lat']) != null &&
              (s['longitude'] ?? s['lng']) != null)
          .toList();
      if (activeOrdered.isEmpty) {
        await _ensureMyStopLatLng();
        if (_myStopLatLng != null) {
          await _drawDriverToMyStopRoute();
        } else {
          if (mounted) setState(() => _polylines.clear());
        }
        return;
      }
      final origin =
          PointLatLng(_driverLatLng!.latitude, _driverLatLng!.longitude);
      const int maxWaypoints = 20;
      final List<Map<String, dynamic>> limitedStops =
          activeOrdered.length > (maxWaypoints + 1)
              ? activeOrdered.take(maxWaypoints + 1).toList()
              : activeOrdered;
      final double? destLatNum =
          (limitedStops.last['latitude'] ?? limitedStops.last['lat'])
              ?.toDouble();
      final double? destLngNum =
          (limitedStops.last['longitude'] ?? limitedStops.last['lng'])
              ?.toDouble();
      if (destLatNum == null || destLngNum == null) {
        if (mounted) setState(() => _polylines.clear());
        return;
      }
      final destination = PointLatLng(destLatNum, destLngNum);
      final waypoints = <PolylineWayPoint>[];
      if (limitedStops.length > 1) {
        for (int i = 0; i < limitedStops.length - 1; i++) {
          final lat = (limitedStops[i]['latitude'] ?? limitedStops[i]['lat'])
              ?.toDouble();
          final lng = (limitedStops[i]['longitude'] ?? limitedStops[i]['lng'])
              ?.toDouble();
          if (lat == null || lng == null) continue;
          waypoints.add(PolylineWayPoint(location: '$lat,$lng'));
        }
      }
      if (_isApiKeyValid) {
        final polylinePoints = PolylinePoints(apiKey: kGoogleApiKey);
        final result = await polylinePoints.getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin: origin,
            destination: destination,
            mode: TravelMode.driving,
            wayPoints: waypoints,
          ),
        );
        if (result.points.isNotEmpty) {
          final pts = result.points
              .map((e) => LatLng(e.latitude, e.longitude))
              .toList();
          final set = <Polyline>{
            Polyline(
              polylineId: const PolylineId('route_shadow'),
              points: pts,
              color: Colors.black.withOpacity(0.15),
              width: 8,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
            Polyline(
              polylineId: const PolylineId('route_main'),
              points: pts,
              color: Colors.blue,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          };
          if (mounted)
            setState(() {
              _polylines = set;
              _lastRoutePoints = pts;
            });
          if (_mapController != null) {
            final bounds = _computeBounds(includePolyline: pts);
            if (bounds != null) {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 80),
              );
            }
          }
          return;
        }
      }
      await _ensureMyStopLatLng();
      if (_myStopLatLng != null) {
        await _drawDriverToMyStopRoute();
        return;
      }
      final fallbackPts = <LatLng>[_driverLatLng!];
      for (final s in limitedStops) {
        final p = _extractStopLatLng(s);
        if (p != null) fallbackPts.add(p);
      }
      if (fallbackPts.length >= 2) {
        if (mounted) {
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('simple_route_shadow'),
                points: fallbackPts,
                color: Colors.black.withOpacity(0.15),
                width: 6,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
              Polyline(
                polylineId: const PolylineId('simple_route'),
                points: fallbackPts,
                color: Colors.blue,
                width: 4,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            };
            _lastRoutePoints = fallbackPts;
          });
        }
      } else {
        if (mounted) setState(() => _polylines.clear());
      }
    } catch (e) {
      debugPrint('Polyline (Directions) hatası: $e');
    } finally {
      _isDrawingRoute = false;
    }
  }

  Future<void> _drawDriverToMyStopRoute() async {
    if (_driverLatLng == null || _myStopLatLng == null) return;
    try {
      if (_isApiKeyValid) {
        final polylinePoints = PolylinePoints(apiKey: kGoogleApiKey);
        final result = await polylinePoints.getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin:
                PointLatLng(_driverLatLng!.latitude, _driverLatLng!.longitude),
            destination:
                PointLatLng(_myStopLatLng!.latitude, _myStopLatLng!.longitude),
            mode: TravelMode.driving,
          ),
        );
        if (result.points.isNotEmpty) {
          final pts = result.points
              .map((e) => LatLng(e.latitude, e.longitude))
              .toList();
          if (mounted) {
            setState(() {
              _polylines = {
                Polyline(
                  polylineId: const PolylineId('route_shadow'),
                  points: pts,
                  color: Colors.black.withOpacity(0.15),
                  width: 8,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                ),
                Polyline(
                  polylineId: const PolylineId('route_main'),
                  points: pts,
                  color: Colors.blue,
                  width: 6,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                ),
              };
              _lastRoutePoints = pts;
            });
          }
          if (_mapController != null) {
            final bounds = _computeBounds(includePolyline: pts);
            if (bounds != null) {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 80),
              );
            }
          }
          return;
        }
      }
    } catch (_) {}
    final pts = <LatLng>[_driverLatLng!, _myStopLatLng!];
    if (mounted) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('simple_route_shadow'),
            points: pts,
            color: Colors.black.withOpacity(0.15),
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
          Polyline(
            polylineId: const PolylineId('simple_route'),
            points: pts,
            color: Colors.blue,
            width: 4,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
        _lastRoutePoints = pts;
      });
    }
    if (_mapController != null) {
      final bounds = _computeBounds(includePolyline: pts);
      if (bounds != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );
      }
    }
  }

  Future<void> _ensureMyStopLatLng() async {
    if (_myStopLatLng != null) return;
    try {
      final mine = await EnhancedStopManagementService.getStopForPassenger(
          widget.passengerId);
      if (mine != null) {
        final p = _extractStopLatLng(mine);
        if (p != null) {
          _myStopLatLng = p;
          return;
        }
      }
    } catch (_) {}
    try {
      final rid =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
      if (rid.isEmpty) return;
      final snap = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: rid)
          .where('isActive', isEqualTo: true)
          .where('passengerIds', arrayContains: widget.passengerId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final p = _extractStopLatLng(data);
        if (p != null) {
          _myStopLatLng = p;
        }
      }
    } catch (_) {}
  }

  Future<void> _recomputeETA() async {
    if (_driverLatLng == null || _myStopLatLng == null) {
      if (mounted)
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
      return;
    }
    if (!_isApiKeyValid) {
      _fallbackEta();
      return;
    }
    try {
      final eta = await _fetchETAWithDirections(
        origin: _driverLatLng!,
        destination: _myStopLatLng!,
      );
      if (mounted)
        setState(() {
          _estimatedArrival = eta;
          _etaRemainingMinutes = _parseMinutes(eta);
        });
      _startEtaMinuteTicker();
    } catch (e) {
      _fallbackEta();
    }
  }

  void _fallbackEta() {
    try {
      final dMeters = Geolocator.distanceBetween(
        _driverLatLng!.latitude,
        _driverLatLng!.longitude,
        _myStopLatLng!.latitude,
        _myStopLatLng!.longitude,
      );
      final distanceKm = dMeters / 1000.0;
      final speedKmh = _lastDriverSpeedKmh.clamp(10.0, 60.0);
      final traffic = distanceKm > 8
          ? 1.25
          : distanceKm > 3
              ? 1.15
              : 1.07;
      final minutes = (distanceKm / speedKmh * 60) * traffic;
      if (mounted) {
        final m = minutes.clamp(1, 90).round();
        setState(() {
          _estimatedArrival = '$m dk';
          _etaRemainingMinutes = m;
        });
        _startEtaMinuteTicker();
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
    }
  }

  Future<String> _fetchETAWithDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'departure_time': 'now',
        'traffic_model': 'best_guess',
        'key': kGoogleApiKey,
      },
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('Directions HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final status = body['status'];
    if (status != 'OK') {
      throw Exception('Directions status: $status');
    }
    final routes = body['routes'] as List<dynamic>;
    if (routes.isEmpty) throw Exception('No routes');
    final legs = routes.first['legs'] as List<dynamic>;
    if (legs.isEmpty) throw Exception('No legs');
    final leg0 = legs.first as Map<String, dynamic>;
    final durTraffic = leg0['duration_in_traffic'] as Map<String, dynamic>?;
    final dur = leg0['duration'] as Map<String, dynamic>?;
    int seconds;
    if (durTraffic != null && durTraffic['value'] is num) {
      seconds = (durTraffic['value'] as num).toInt();
    } else if (dur != null && dur['value'] is num) {
      seconds = (dur['value'] as num).toInt();
    } else {
      throw Exception('No duration');
    }
    return _formatDuration(seconds);
  }

  String _formatDuration(int seconds) {
    if (seconds <= 60) return '1 dk';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours sa';
    return '$hours sa $mins dk';
  }

  void _startEtaMinuteTicker() {
    _etaMinuteTicker?.cancel();
    if (_etaRemainingMinutes == null) return;
    _etaMinuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_etaRemainingMinutes == null) return;
      if (_myStopLatLng == null) {
        _etaMinuteTicker?.cancel();
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
        return;
      }
      if (_etaRemainingMinutes! <= 1) {
        setState(() {
          _etaRemainingMinutes = 0;
          _estimatedArrival = '1 dk';
        });
        _etaMinuteTicker?.cancel();
      } else {
        setState(() {
          _etaRemainingMinutes = (_etaRemainingMinutes! - 1).clamp(0, 9999);
          _estimatedArrival = '${_etaRemainingMinutes!} dk';
        });
      }
    });
  }

  int? _parseMinutes(String? label) {
    if (label == null) return null;
    try {
      if (label.endsWith(' dk')) {
        return int.parse(label.replaceAll(' dk', '').trim());
      }
      if (label.contains('sa')) {
        final parts = label.split(' ');
        int hours = 0;
        int mins = 0;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == 'sa') {
            hours = int.tryParse(parts[i - 1]) ?? 0;
          } else if (parts[i] == 'dk') {
            mins = int.tryParse(parts[i - 1]) ?? 0;
          }
        }
        return hours * 60 + mins;
      }
    } catch (_) {}
    return null;
  }

  LatLng? _extractLatLng(Map<String, dynamic> data) {
    try {
      final num? latN = (data['lat'] ?? data['latitude']) as num?;
      final num? lngN = (data['lng'] ?? data['longitude']) as num?;
      if (latN == null || lngN == null) return null;
      final lat = latN.toDouble();
      final lng = lngN.toDouble();
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  LatLng? _extractStopLatLng(Map<String, dynamic> data) {
    try {
      final num? latN = (data['latitude'] ?? data['lat']) as num?;
      final num? lngN = (data['longitude'] ?? data['lng']) as num?;
      if (latN == null || lngN == null) return null;
      final lat = latN.toDouble();
      final lng = lngN.toDouble();
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  LatLngBounds? _computeBounds({List<LatLng>? includePolyline}) {
    final pts = <LatLng>[];
    if (_driverLatLng != null) pts.add(_driverLatLng!);
    for (final s in _allStops) {
      final p = _extractStopLatLng(s);
      if (p != null) pts.add(p);
    }
    if (includePolyline != null && includePolyline.isNotEmpty) {
      pts.addAll(includePolyline);
    }
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    const pad = 0.002;
    return LatLngBounds(
      southwest: LatLng(minLat - pad, minLng - pad),
      northeast: LatLng(maxLat + pad, maxLng + pad),
    );
  }

  String _formatStopTitle(Map<String, dynamic> stop, int index) {
    final passengerNames = List<String>.from(stop['passengerNames'] ?? []);
    if (passengerNames.isNotEmpty) {
      final joined = passengerNames.length > 2
          ? '${passengerNames.take(2).join(', ')} +${passengerNames.length - 2}'
          : passengerNames.join(', ');
      return 'Durak $index · $joined';
    }
    return 'Durak $index';
  }

  String _formatStopSnippet(Map<String, dynamic> stop) {
    final address = (stop['address'] ?? 'Adres belirtilmemiş') as String;
    return address;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Servis Takip'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      final b = _computeBounds();
                      if (b != null) {
                        await _mapController?.animateCamera(
                          CameraUpdate.newLatLngBounds(b, 80),
                        );
                      } else if (_currentPosition != null) {
                        await _mapController?.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(_currentPosition!.latitude,
                                _currentPosition!.longitude),
                            16.0,
                          ),
                        );
                      }
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition != null
                        ? LatLng(_currentPosition!.latitude,
                            _currentPosition!.longitude)
                        : const LatLng(39.9334, 32.8597),
                    zoom: 16.0,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'follow_cam_btn',
                    onPressed: () => setState(
                        () => _followDriverCamera = !_followDriverCamera),
                    backgroundColor:
                        _followDriverCamera ? Colors.green : Colors.grey,
                    child: const Icon(Icons.center_focus_strong,
                        color: Colors.white),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 72,
                  child: FloatingActionButton.small(
                    heroTag: 'test_mode_btn',
                    onPressed: _toggleTestMode,
                    backgroundColor:
                        _isTestMode ? Colors.deepPurple : Colors.grey,
                    child:
                        const Icon(Icons.science_rounded, color: Colors.white),
                  ),
                ),
                if (_estimatedArrival != null)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: Colors.green),
                          const SizedBox(width: 6),
                          Text(
                            _estimatedArrival!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLiveTrackingInfo(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLiveTrackingInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Anlık Takip Bilgileri',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_estimatedArrival != null) ...[
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Tahmini Varış: $_estimatedArrival',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.directions_bus,
                  color: Colors.orange.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'Şoför Durumu: $_driverStatus',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_currentStopAddress != null) ...[
            Row(
              children: [
                Icon(Icons.place, color: Color(0xFF6366F1), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mevcut Durak: $_currentStopAddress',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4338CA),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(Icons.timeline, color: Colors.indigo.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'İlerleme: $_completedStops/$_totalStops durak',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _routeProgress,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
        ],
      ),
    );
  }

  void _toggleTestMode() {
    setState(() {
      _isTestMode = !_isTestMode;
    });
    _testTimer?.cancel();
    if (_isTestMode) {
      List<LatLng> route = List<LatLng>.from(_lastRoutePoints);
      if (route.length < 2) {
        route = _createTestRouteFromStops();
      }
      if (route.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Simülasyon için rota bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isTestMode = false);
        return;
      }
      _lastRoutePoints = route;
      _updateRoutePolyline(route);
      int idx = 0;
      _testTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_isTestMode || !mounted) return;
        final p = route[idx];
        setState(() {
          _driverLatLng = p;
          _isDriverMoving = true;
          _driverStatus = 'Test Modu';
        });
        await _updateDriverMarker(p);
        _debouncedRouteAndEta();
        idx = (idx + 1) % route.length;
      });
    } else {
      setState(() {
        _driverStatus = _isDriverMoving ? 'Hareket Halinde' : 'Bekliyor';
      });
    }
  }

  List<LatLng> _createTestRouteFromStops() {
    final List<LatLng> route = [];
    if (_currentPosition != null) {
      route
          .add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }
    for (final stop in _allStops) {
      final stopLatLng = _extractStopLatLng(stop);
      if (stopLatLng != null) {
        route.add(stopLatLng);
      }
    }
    if (route.length < 2) {
      final LatLng center = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : const LatLng(39.9334, 32.8597);
      route.addAll([
        LatLng(center.latitude + 0.001, center.longitude + 0.001),
        LatLng(center.latitude + 0.002, center.longitude + 0.002),
        LatLng(center.latitude + 0.003, center.longitude + 0.003),
      ]);
    }
    return route;
  }

  void _updateRoutePolyline(List<LatLng> routePoints) {
    if (routePoints.length < 2) return;
    setState(() {
      _lastRoutePoints = routePoints;
    });
    if (_mapController != null) {
      _drawRouteOnMap(routePoints);
    }
  }

  void _drawRouteOnMap(List<LatLng> routePoints) {
    if (routePoints.length < 2) return;
    _polylines.clear();
    _polylines.add(Polyline(
      polylineId: const PolylineId('test_route'),
      points: routePoints,
      color: Colors.blue,
      width: 4,
      geodesic: true,
    ));
    setState(() {});
  }

  bool _analyzeMovementByTime() {
    if (_recentDriverPositions.length < 3) return false;
    final now = DateTime.now();
    final cutoffTime = now.subtract(_movementAnalysisWindow);
    double totalDistance = 0.0;
    for (int i = 1; i < _recentDriverPositions.length; i++) {
      totalDistance += Geolocator.distanceBetween(
        _recentDriverPositions[i - 1].latitude,
        _recentDriverPositions[i - 1].longitude,
        _recentDriverPositions[i].latitude,
        _recentDriverPositions[i].longitude,
      );
    }
    return totalDistance > 30.0;
  }
}
