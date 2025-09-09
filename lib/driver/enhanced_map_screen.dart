import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/painting.dart' show paintImage;
import '../service/voice_navigation_service.dart';
import 'dart:math' as math;
import '../models/stop_model.dart';
import '../models/directions_model.dart';
import '../service/enhanced_route_service.dart';
import '../service/enhanced_tracking_service.dart';
import '../service/location_service.dart';
import '../service/user_session.dart';
import '../service/directions_service.dart';
import '../service/roads_service.dart';
import '../service/geocoding_service.dart';
import '../service/background_location_service.dart';
import '../service/distance_notification_service.dart';
import '../service/avatar_marker_service.dart';
import '../service/stop_completion_tracker.dart';
import '../service/automatic_permission_service.dart';
import '../service/simulation_service.dart';
import '../service/eta_calculation_service.dart';
import '../service/route_history_service.dart';
import '../utils/app_colors.dart';
import '../widget/top_notification.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/unified_route_optimization_service.dart';

class EnhancedMapScreen extends StatefulWidget {
  final String driverId;
  final String regionId;
  final String vehiclePlate;
  const EnhancedMapScreen({
    super.key,
    required this.driverId,
    required this.regionId,
    required this.vehiclePlate,
  });
  @override
  State<EnhancedMapScreen> createState() => _EnhancedMapScreenState();
}

class _EnhancedMapScreenState extends State<EnhancedMapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  List<StopModel> _stops = [];
  List<StopModel> _optimizedRoute = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  bool _isRouteActive = false;
  bool _isAnimating = false;
  double _animationProgress = 0.0;
  List<LatLng> _fullRoutePoints = [];
  List<LatLng> _animatedRoutePoints = [];
  Timer? _animationTimer;
  StreamSubscription<QuerySnapshot>? _permissionsSubscription;
  Set<String> _absentPassengerIds = {};
  void _resetRouteVisualization() {
    _animationTimer?.cancel();
    _isAnimating = false;
    _animationProgress = 0.0;
    _fullRoutePoints.clear();
    _animatedRoutePoints.clear();
    if (mounted) {
      setState(() => _polylines.clear());
    }
  }

  bool _isTestSimulating = false;
  Timer? _simulationTimer;
  int _simulationIndex = 0;
  bool _isLiveTracking = false;
  Timer? _liveTrackingTimer;
  LatLng? _lastKnownPosition;
  List<LatLng> _trackingHistory = [];
  final Map<String, BitmapDescriptor> _bitmapCache = {};
  bool _shouldFollowUser = true;
  double _currentZoom = 16.0;
  Map<String, LatLng> _otherDrivers = {};
  Timer? _driversUpdateTimer;
  MapType _currentMapType = MapType.normal;
  DirectionsService? _directionsService;
  DirectionsModel? _currentDirections;
  VoiceNavigationService? _voiceNavigationService;
  String? _effectiveRegionId;
  bool _isAnimatingCamera = false;
  int _lastCameraAnimateMs = 0;
  ETACalculationService? _etaCalculationService;
  bool _isVoiceNavigationActive = false;
  bool _isSimulationMode = false;
  String _currentInstruction = '';
  bool _didAttemptAutoStart = false;
  StreamSubscription? _stopsSubscription;
  Timer? _routeUpdateTimer;
  Timer? _proximityCheckTimer;
  @override
  void initState() {
    super.initState();
    _directionsService = DirectionsService.instance;
    _voiceNavigationService = VoiceNavigationService();
    _etaCalculationService = ETACalculationService();
    _initializeMap();
    _resolveDriverRegionAndStartStreams();
    _initializeNewServices();

    StopCompletionTracker().startTracking(
      driverId: widget.driverId,
      onStopsUpdated: () {
        if (kDebugMode) {
          print('🔄 StopCompletionTracker onStopsUpdated callback çağrıldı');
        }
        if (mounted) {
          _updateMarkers();
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMapOnCurrentPosition();
      _syncLocationSharingStatus();
      _startPeriodicStatusCheck();
    });
  }

  Future<void> _resolveDriverRegionAndStartStreams() async {
    try {
      _effectiveRegionId = widget.regionId;
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.driverId)
          .get();
      if (driverDoc.exists) {
        final data = driverDoc.data() as Map<String, dynamic>;
        final resolvedRegion = (data['regionId'] as String?)?.trim();
        if (resolvedRegion != null && resolvedRegion.isNotEmpty) {
          _effectiveRegionId = resolvedRegion;
          debugPrint(
              '✅ Şoför bölgesi bulundu: $_effectiveRegionId (Şoför: ${widget.driverId})');
        } else {
          debugPrint(
              '⚠️ Şoför dokümanında regionId bulunamadı, widget regionId kullanılıyor: ${widget.regionId}');
        }
      } else {
        debugPrint(
            '❌ Şoför dokümanı bulunamadı: ${widget.driverId}, widget regionId kullanılıyor: ${widget.regionId}');
      }
      _startRealTimeUpdates();
      if (_effectiveRegionId != null && _effectiveRegionId!.isNotEmpty) {
        UserSession.regionId = _effectiveRegionId!;
        debugPrint('✅ UserSession.regionId güncellendi: $_effectiveRegionId');
      }
    } catch (e) {
      debugPrint('❌ Şoför bölgesi resolve hatası: $e');
      _startRealTimeUpdates();
    }
  }

  Future<void> _autoStartLocationSharingOnEnter() async {}
  @override
  void dispose() {
    if (_isSimulationMode) {
      SimulationService.stopSimulation();
      _isSimulationMode = false;
      _isTestSimulating = false;
      print('🛑 Harita kapatılırken simülasyon durduruldu');
    }

    StopCompletionTracker().stopTracking();

    _stopsSubscription?.cancel();
    _routeUpdateTimer?.cancel();
    _proximityCheckTimer?.cancel();
    _animationTimer?.cancel();
    _liveTrackingTimer?.cancel();
    _driversUpdateTimer?.cancel();
    RouteHistoryService.stopRouteTracking(widget.driverId);
    super.dispose();
  }

  Future<void> _centerMapOnCurrentPosition() async {
    try {
      if (_isSimulationMode) {
        print(
            '⏸️ Test modunda harita ortalanması atlandı - simülasyon konumu korunuyor');
        return;
      }
      int attempts = 0;
      while (_mapController == null && attempts < 10) {
        await Future.delayed(Duration(milliseconds: 100));
        attempts++;
      }
      if (_mapController != null) {
        final position = await LocationService.instance.getCurrentPosition();
        _currentPosition = position;
        if (position != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(position.latitude, position.longitude),
                zoom: 17.0,
                tilt: 0.0,
                bearing: 0.0,
              ),
            ),
          );
          _shouldFollowUser = true;
          print(
              '📍 Harita mevcut konuma ortalandı ve takip aktif edildi - Zoom: 17.0');
          await _updateMarkers();
        }
      } else {
        print('⚠️ MapController hazır değil, harita ortalanması atlandı');
      }
    } catch (e) {
      print('❌ Harita ortalama hatası: $e');
    }
  }

  void _syncLocationSharingStatus() {
    final isSharing = UserSession.isLocationSharing;
    print(
        '🔍 Durum kontrolü - UserSession: $isSharing, _isLiveTracking: $_isLiveTracking');
    if (_isLiveTracking != isSharing) {
      setState(() {
        _isLiveTracking = isSharing;
      });
      if (isSharing && (_liveTrackingTimer?.isActive != true)) {
        _startLiveTracking();
      }
      print('🔄 Konum paylaşım durumu senkronize edildi: $_isLiveTracking');
    }
  }

  void _startPeriodicStatusCheck() {
    Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isSharing = UserSession.isLocationSharing;
      if (_isLiveTracking != isSharing) {
        print(
            '🚨 Durum uyumsuzluğu tespit edildi! UserSession: $isSharing, UI: $_isLiveTracking');
        setState(() {
          _isLiveTracking = isSharing;
        });
      }
    });
  }

  Future<void> _initializeNewServices() async {
    try {
      await VoiceNavigationService.initializeTTS();
      RouteHistoryService.startRouteTracking(widget.driverId);
      await AutomaticPermissionService.initialize();
      print('✅ Yeni servisler başarıyla başlatıldı');
    } catch (e) {
      print('❌ Yeni servisler başlatma hatası: $e');
    }
  }

  Future<void> _initializeMap() async {
    try {
      _currentPosition = await LocationService.instance.getCurrentPosition();
      await _loadStops();
      await _optimizeRoute();
      await _updateMapElements();
      if (_mapController != null && _optimizedRoute.isNotEmpty) {
        await _drawRoute();
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Harita başlatma hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStops() async {
    try {
      final region = _effectiveRegionId ?? widget.regionId;
      final col = FirebaseFirestore.instance.collection('enhanced_stops');
      final snap1 = await col
          .where('regionId', isEqualTo: region)
          .where('isActive', isEqualTo: true)
          .where('createdFromMap', isEqualTo: true)
          .get();
      final snap2 = await col
          .where('regionId', isEqualTo: region)
          .where('isActive', isEqualTo: true)
          .where('source', isEqualTo: 'map_selection')
          .get();
      final merged = [...snap1.docs, ...snap2.docs];
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
          latestByPassenger = {};
      for (final doc in merged) {
        final data = doc.data();
        final List<dynamic> pids =
            (data['passengerIds'] as List<dynamic>?) ?? [];
        if (pids.isEmpty) continue;
        final String pid = pids.first.toString();
        final createdAt = (data['createdAt']);
        if (!latestByPassenger.containsKey(pid)) {
          latestByPassenger[pid] = doc;
        } else {
          final prev = latestByPassenger[pid]!.data();
          final prevCreatedAt = prev['createdAt'];
          final bool isNewer =
              (createdAt is Timestamp && prevCreatedAt is Timestamp)
                  ? createdAt.compareTo(prevCreatedAt) > 0
                  : true;
          if (isNewer) latestByPassenger[pid] = doc;
        }
      }
      final List<StopModel> regionStops = [];
      for (final doc in latestByPassenger.values) {
        final data = doc.data();
        if ((data['temporarilyInactive'] ?? false) == true) continue;
        final List<dynamic> pids =
            (data['passengerIds'] as List<dynamic>?) ?? [];
        if (pids.isEmpty) continue;
        regionStops.add(
          StopModel(
            id: doc.id,
            driverId: data['driverId'] ?? '',
            address: data['address'] ?? '',
            lat: (data['latitude'] ?? 0.0).toDouble(),
            lng: (data['longitude'] ?? 0.0).toDouble(),
            date: DateTime.now(),
            order: data['order'] ?? 0,
            createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
            updatedAt: data['updatedAt']?.toDate() ?? DateTime.now(),
            regionId: data['regionId'] ?? '',
            status: data['status'] ?? 'pending',
            passengerId: pids.first.toString(),
            passengerName: data['passengerName'],
            phoneNumber: data['phoneNumber'],
            note: data['note'],
          ),
        );
      }
      setState(() {
        _stops = regionStops;
      });
    } catch (e) {
      print('❌ Duraklar yükleme hatası: $e');
    }
  }

  void _startRealTimeUpdates() {
    final region = _effectiveRegionId ?? widget.regionId;
    print('🎯 Real-time updates başlatılıyor - Bölge: $region');
    _stopsSubscription?.cancel();
    final baseQuery = FirebaseFirestore.instance
        .collection('enhanced_stops')
        .where('regionId', isEqualTo: region)
        .where('isActive', isEqualTo: true);
    _stopsSubscription = baseQuery.snapshots().listen((snapshot) {
      final docs = snapshot.docs.where((d) {
        final m = d.data() as Map<String, dynamic>;
        return m['createdFromMap'] == true || m['source'] == 'map_selection';
      }).toList();
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
          latestByPassenger = {};
      for (final d in docs) {
        final m = d.data() as Map<String, dynamic>;
        final List<dynamic> pids = (m['passengerIds'] as List<dynamic>?) ?? [];
        if (pids.isEmpty) continue;
        final pid = pids.first.toString();
        final createdAt = m['createdAt'];
        if (!latestByPassenger.containsKey(pid)) {
          latestByPassenger[pid] = d;
        } else {
          final prev = latestByPassenger[pid]!.data();
          final prevCreatedAt = prev['createdAt'];
          final bool isNewer =
              (createdAt is Timestamp && prevCreatedAt is Timestamp)
                  ? createdAt.compareTo(prevCreatedAt) > 0
                  : true;
          if (isNewer) latestByPassenger[pid] = d;
        }
      }
      final filteredDocs = latestByPassenger.values.toList();
      print(
          '📡 Firestore değişikliği: ${filteredDocs.length} HARİTA durağı (Bölge: $region)');
      print('🔍 === İLDEM BÖLGE DURAK ANALİZİ ===');
      for (int i = 0; i < snapshot.docs.length; i++) {
        final doc = snapshot.docs[i];
        final data = doc.data() as Map<String, dynamic>;
        final lat = data['lat'] ?? data['latitude'] ?? 0.0;
        final lng = data['lng'] ?? data['longitude'] ?? 0.0;
        final isActive = data['isActive'] ?? false;
        final address = data['address'] ?? 'Adres yok';
        final passengerId = data['passengerId'] ?? 'Yolcu yok';
        print('📍 Durak ${i + 1}: ${doc.id}');
        print('   📍 Adres: $address');
        print('   🌍 Konum: ($lat, $lng)');
        print('   🔄 Aktif: $isActive');
        print('   👤 Yolcu: $passengerId');
        print('   🏷️ BölgeID: ${data['regionId']}');
        print('   ─────────────────────────');
      }
      print('🔍 === TOPLAM: ${snapshot.docs.length} DURAK ===');
      _handleStopsUpdate(snapshot);
    });
    try {
      _permissionsSubscription?.cancel();
      _permissionsSubscription = FirebaseFirestore.instance
          .collection('permissions')
          .where('driverId', isEqualTo: widget.driverId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen((snap) async {
        final now = DateTime.now();
        final Set<String> ids = {};
        for (final d in snap.docs) {
          final m = d.data() as Map<String, dynamic>;
          final String? uid = m['userId'] as String?;
          if (uid == null || uid.isEmpty) continue;
          final String type = (m['type'] as String?) ?? '';
          final int hour = now.hour;
          final bool isMorning = hour < 12;
          bool active = false;
          switch (type) {
            case 'allToday':
              active = true;
              break;
            case 'vacation':
              active = true;
              break;
            case 'morningToday':
              active = isMorning;
              break;
            case 'eveningToday':
              active = !isMorning;
              break;
            case 'allTomorrow':
            case 'morningTomorrow':
              active = false;
              break;
            default:
              active = true;
          }
          if (active) ids.add(uid);
        }
        _absentPassengerIds = ids;
        await _optimizeRoute();
        await _updateMapElements();
        if (_mapController != null && _optimizedRoute.isNotEmpty) {
          await _drawRoute();
        }
      });
    } catch (e) {
      print('⚠️ permissions dinleme hatası: $e');
    }
    try {
      FirebaseFirestore.instance
          .collection('route_refresh_triggers')
          .where('driverId', isEqualTo: widget.driverId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.docs.isEmpty) return;
        print(
            '🔔 Rota yenileme tetikleyicisi alındı (${snapshot.docs.length})');
        _resetRouteVisualization();
        await _optimizeRoute();
        await _updateMapElements();
        if (_mapController != null && _optimizedRoute.isNotEmpty) {
          await _drawRoute();
        }
        for (final d in snapshot.docs) {
          await d.reference
              .update({'status': 'processed', 'processedAt': Timestamp.now()});
        }
      });
    } catch (e) {
      print('⚠️ route_refresh_triggers dinleme hatası: $e');
    }
    _routeUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateRouteIfNeeded();
    });
    _proximityCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkStopProximity();
    });
    _startDriversTracking();
    print(
        '🔄 Real-time güncellemeler başlatıldı - tüm aktif duraklar dinleniyor');
  }

  void _handleStopsUpdate(QuerySnapshot snapshot) async {
    try {
      print('🔄 Durak güncellemesi başlıyor - ${snapshot.docs.length} durak');
      final Map<String, QueryDocumentSnapshot> latestByPassenger = {};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final bool isMapStop = (data['createdFromMap'] == true) ||
            (data['source'] == 'map_selection');
        if (!isMapStop) continue;
        final bool isActive = (data['isActive'] ?? true) == true;
        final bool tempInactive =
            (data['temporarilyInactive'] ?? false) == true;
        if (!isActive || tempInactive) {
          continue;
        }
        final List<dynamic> pids =
            (data['passengerIds'] as List<dynamic>?) ?? [];
        if (pids.isEmpty) continue;
        final pid = pids.first.toString();
        if (!latestByPassenger.containsKey(pid)) {
          latestByPassenger[pid] = doc;
        } else {
          final prev = latestByPassenger[pid]!.data() as Map<String, dynamic>;
          final createdAt = data['createdAt'];
          final prevCreated = prev['createdAt'];
          final bool isNewer =
              (createdAt is Timestamp && prevCreated is Timestamp)
                  ? createdAt.compareTo(prevCreated) > 0
                  : true;
          if (isNewer) latestByPassenger[pid] = doc;
        }
      }
      final List<StopModel> allStops = [];
      for (final doc in latestByPassenger.values) {
        final data = doc.data() as Map<String, dynamic>;
        allStops.add(
          StopModel(
            id: doc.id,
            driverId: data['driverId'] ?? '',
            address: data['address'] ?? '',
            lat: (data['latitude'] ?? 0.0).toDouble(),
            lng: (data['longitude'] ?? 0.0).toDouble(),
            date: DateTime.now(),
            order: data['order'] ?? 0,
            createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
            updatedAt: data['updatedAt']?.toDate() ?? DateTime.now(),
            regionId: data['regionId'] ?? '',
            status: data['status'] ?? 'pending',
            passengerId: (data['passengerIds'] as List?)?.isNotEmpty == true
                ? (data['passengerIds'] as List).first
                : null,
            passengerName: data['passengerName'],
            phoneNumber: data['phoneNumber'],
            note: data['note'],
          ),
        );
      }
      setState(() {
        _stops = allStops;
      });
      print('🔄 ${allStops.length} durak güncellendi (bölgedeki tüm duraklar)');
      if (allStops.isNotEmpty) {
        _resetRouteVisualization();
        await _optimizeRoute();
        await _updateMapElements();
        print('🎨 Rota çizimi kontrol ediliyor:');
        print('   - MapController: ${_mapController != null ? "✅" : "❌"}');
        print(
            '   - OptimizedRoute: ${_optimizedRoute.isNotEmpty ? "✅ (${_optimizedRoute.length})" : "❌"}');
        if (_mapController != null && _optimizedRoute.isNotEmpty) {
          print('🚀 _drawRoute() çağrılıyor...');
          await _drawRoute();
        } else {
          print('⚠️ Rota çizimi atlandı - koşullar sağlanmadı');
        }
      } else {
        print('📍 Bu bölgede aktif durak bulunamadı');
      }
      if (mounted && allStops.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota güncellendi (${allStops.length} durak)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Durak güncelleme hatası: $e');
    }
  }

  bool _stopsChanged(List<StopModel> newStops) {
    if (_stops.length != newStops.length) return true;
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i].id != newStops[i].id ||
          _stops[i].lat != newStops[i].lat ||
          _stops[i].lng != newStops[i].lng ||
          _stops[i].status != newStops[i].status) {
        return true;
      }
    }
    return false;
  }

  void _updateRouteIfNeeded() async {
    if (_isSimulationMode) {
      print('⏸️ Rota güncellemesi atlandı - simülasyon modunda');
      return;
    }
    if (_currentPosition == null) return;
    try {
      final newPosition = await LocationService.instance.getCurrentPosition();
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        newPosition?.latitude ?? 0.0,
        newPosition?.longitude ?? 0.0,
      );
      if (distance > 150) {
        _currentPosition = newPosition;
        print(
            '🔄 Konum önemli ölçüde değişti, rota yeniden optimize ediliyor...');
        _resetRouteVisualization();
        await _optimizeRoute();
        await _updateMapElements();
        if (_mapController != null && _optimizedRoute.isNotEmpty) {
          await _drawRoute();
        }
      }
    } catch (e) {
      print('❌ Konum güncelleme hatası: $e');
    }
  }

  Future<void> _optimizeRoute() async {
    if (_currentPosition == null || _stops.isEmpty) return;
    try {
      final validStops = _stops
          .where((stop) => stop.lat != 0.0 && stop.lng != 0.0)
          .where((stop) {
        final List<String> pids = stop.passengerIds?.isNotEmpty == true
            ? stop.passengerIds!
            : (stop.passengerId != null
                ? <String>[stop.passengerId!]
                : <String>[]);
        return !pids.any((id) => _absentPassengerIds.contains(id));
      }).toList();
      if (validStops.isEmpty) {
        print('⚠️ Geçerli koordinatlı durak bulunamadı');
        setState(() {
          _optimizedRoute = [];
        });
        return;
      }
      if (validStops.length != _stops.length) {
        print(
            '⚠️ ${_stops.length - validStops.length} durak geçersiz koordinatlara sahip');
      }
      final optimizedStops = await EnhancedRouteService.optimizeRoute(
        validStops,
        _currentPosition!,
      );
      setState(() {
        _optimizedRoute = optimizedStops;
      });
      print(
          '✅ ${optimizedStops.length} durak optimize edildi - Şoför: ${widget.driverId}');
      print('🎮 Test modu butonu aktif olacak: ${_optimizedRoute.isNotEmpty}');
      print('🔍 === OPTİMİZE EDİLEN DURAKLAR ===');
      for (int i = 0; i < optimizedStops.length; i++) {
        final stop = optimizedStops[i];
        print('🎯 Durak ${i + 1}: ${stop.address}');
        print('   🌍 Konum: (${stop.lat}, ${stop.lng})');
        print('   👤 Yolcu: ${stop.passengerId}');
        print('   🏷️ ID: ${stop.id}');
        print('   ─────────────────────────');
      }
      print('🔍 === TOPLAM OPTİMİZE: ${optimizedStops.length} ===');

      if (_currentPosition != null) {
        final cacheKey =
            'driver_${widget.driverId}_${validStops.length}_${_currentPosition!.latitude.toStringAsFixed(6)}_${_currentPosition!.longitude.toStringAsFixed(6)}';
        print('🔑 Cache key oluşturuldu: $cacheKey');
        print('📱 Passenger panel bu key ile aynı rotayı alacak');
        print(
            '📍 Driver konumu: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        print('🚌 Durak sayısı: ${validStops.length}');
        print('👤 Driver ID: ${widget.driverId}');

        _writeRouteToCache(
            cacheKey,
            validStops
                .map((stop) => {
                      'latitude': stop.lat,
                      'longitude': stop.lng,
                      'stopId': stop.id,
                      'address': stop.address,
                      'order': stop.order ?? 0,
                    })
                .toList());
      }
    } catch (e) {
      print('❌ Rota optimizasyonu hatası: $e');
      setState(() {
        _optimizedRoute = [];
      });
    }
  }

  Future<void> _updateMapElements() async {
    await _updateMarkers();
    await _updatePolylines();
  }

  Future<void> _addCurrentUserMarker(Set<Marker> markers) async {
    try {
      final userPhotoUrl = UserSession.photoUrl;
      final userProfileIcon = await AvatarMarkerService.createAvatarMarker(
        profileImageUrl: userPhotoUrl,
        stopNumber: 0,
        size: 80,
      );
      if (_currentPosition != null) {
        final userMarkerPosition = LatLng(
          _currentPosition!.latitude + 0.0001,
          _currentPosition!.longitude + 0.0001,
        );
        markers.add(
          Marker(
            markerId: const MarkerId('current_user_profile'),
            position: userMarkerPosition,
            icon: userProfileIcon,
            infoWindow: InfoWindow(
              title: '👤 Sizin Profiliniz',
              snippet: userPhotoUrl != null && userPhotoUrl.isNotEmpty
                  ? 'Profil fotoğrafı ile'
                  : 'Varsayılan avatar',
            ),
          ),
        );
      }
    } catch (e) {
      print('Kullanıcı profil marker\'ı eklenirken hata: $e');
    }
  }

  Future<void> _updateMarkers() async {
    if (kDebugMode) {
      print(
          '🎨 _updateMarkers çağrıldı - isSimulationMode: $_isSimulationMode');
    }
    Set<Marker> markers = {};
    if (_currentPosition != null) {
      final carIcon = await AvatarMarkerService.createEmojiMarker(
        emoji: '🚌',
        size: 88,
      );
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: carIcon,
          infoWindow: const InfoWindow(
            title: 'Servis Aracı',
            snippet: 'Mevcut konum',
          ),
        ),
      );
    }
    await _addCurrentUserMarker(markers);
    for (int i = 0; i < _optimizedRoute.length; i++) {
      final stop = _optimizedRoute[i];
      final List<String> pids = stop.passengerIds?.isNotEmpty == true
          ? stop.passengerIds!
          : (stop.passengerId != null ? [stop.passengerId!] : <String>[]);
      final bool isAbsent = pids.any((id) => _absentPassengerIds.contains(id));
      if (isAbsent) {
        continue;
      }
      final passengerId = stop.passengerIds?.isNotEmpty == true
          ? stop.passengerIds!.first
          : stop.passengerId;
      String? profilePhotoUrl;
      if (passengerId != null) {
        try {
          profilePhotoUrl =
              await EnhancedTrackingService.getPassengerProfilePhoto(
                  passengerId);
        } catch (e) {
          print('Profil fotoğrafı alınamadı: $e');
        }
      }
      final bool isCompleted = StopCompletionTracker().isStopCompleted(stop.id);
      if (kDebugMode) {
        print(
            '🎨 Marker oluşturuluyor: ${stop.address} - isCompleted: $isCompleted');
      }
      final BitmapDescriptor markerIcon =
          await AvatarMarkerService.createAvatarMarker(
        profileImageUrl: profilePhotoUrl,
        stopNumber: i + 1,
        size: 110,
        isCompleted: isCompleted,
      );
      final passengerNames = await _getPassengerNamesForStop(stop);
      markers.add(
        Marker(
          markerId: MarkerId(stop.id),
          position: LatLng(stop.lat, stop.lng),
          icon: markerIcon,
          infoWindow: InfoWindow(
            title: '🚏 Durak ${i + 1}',
            snippet: '${stop.address}\n👥 $passengerNames',
          ),
          onTap: () => _showStopDetails(stop),
        ),
      );
    }
    setState(() {
      _markers = markers;
    });
  }

  Future<void> _drawRoute() async {
    if (_currentPosition == null ||
        _optimizedRoute.isEmpty ||
        _isSimulationMode) {
      print('⚠️ Rota çizimi için gerekli veriler eksik');
      return;
    }
    try {
      _isRouteActive = true;
      final startPoint =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final waypoints =
          _optimizedRoute.map((stop) => LatLng(stop.lat, stop.lng)).toList();
      final directions = await _directionsService!.getOptimizedRoute(
        baslangic: startPoint,
        duraklar: waypoints,
      );
      if (directions != null && directions.isValid) {
        _currentDirections = directions;
        final snapped =
            await RoadsService.snapToRoads(directions.latLngNoktalari);
        _fullRoutePoints = snapped;
        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route_shadow'),
              points: snapped,
              color: Colors.black.withOpacity(0.15),
              width: 8,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          );
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('main_route'),
              points: snapped,
              color: AppColors.primary,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          );
        });
        if (!_isSimulationMode) {
          await _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(
              directions.sinirlar,
              80.0,
            ),
          );
        }
        print('✅ Modern rota başarıyla çizildi');
      } else {
        try {
          final origin = {
            'latitude': startPoint.latitude,
            'longitude': startPoint.longitude,
          };
          final destination = {
            'latitude': waypoints.last.latitude,
            'longitude': waypoints.last.longitude,
          };
          final waypointMaps = waypoints
              .take(waypoints.length - 1)
              .map((p) => {
                    'latitude': p.latitude,
                    'longitude': p.longitude,
                  })
              .toList();
          final routeData =
              await GeocodingService.getOptimizedRouteWithWaypoints(
            origin: origin,
            destination: destination,
            waypoints: waypointMaps,
            optimizeWaypoints: false,
          );
          if (routeData != null && routeData['polyline'] != null) {
            final decoded =
                GeocodingService.decodePolyline(routeData['polyline']);
            final rawPoints = decoded
                .map((e) => LatLng(e['latitude']!, e['longitude']!))
                .toList();
            final points = await RoadsService.snapToRoads(rawPoints);
            if (points.length > 1) {
              _fullRoutePoints = points;
              setState(() {
                _polylines.clear();
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('route_shadow'),
                    points: points,
                    color: Colors.black.withOpacity(0.15),
                    width: 8,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
                );
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('main_route'),
                    points: points,
                    color: AppColors.primary,
                    width: 6,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
                );
              });
              if (!_isSimulationMode) {
                final bounds = _calculateBounds(points);
                await _mapController?.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, 80.0),
                );
              }
              print('✅ Fallback ile rota başarıyla çizildi (GeocodingService)');
            } else {
              setState(() => _polylines.clear());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Rota çizimi için internet bağlantısı gerekli'),
                  backgroundColor: Colors.red,
                ));
              }
            }
          } else {
            setState(() => _polylines.clear());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Rota çizimi için internet bağlantısı gerekli'),
                backgroundColor: Colors.red,
              ));
            }
          }
        } catch (e) {
          print('⚠️ Fallback rota çizimi hatası: $e');
          setState(() => _polylines.clear());
        }
      }
    } catch (e) {
      print('❌ Rota çizimi hatası: $e');
      _drawCleanSimpleRoute();
    } finally {
      _isRouteActive = false;
    }
  }

  Future<void> _drawCleanSimpleRoute() async {
    if (_currentPosition == null ||
        _optimizedRoute.isEmpty ||
        _isSimulationMode) return;
    List<LatLng> points = [];
    points.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    for (var stop in _optimizedRoute) {
      points.add(LatLng(stop.lat, stop.lng));
    }
    _fullRoutePoints = points;
    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('simple_route_shadow'),
          points: points,
          color: Colors.black.withOpacity(0.15),
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('simple_route'),
          points: points,
          color: AppColors.primary,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    });
    if (points.length > 1) {
      final bounds = _calculateBounds(points);
      if (!_isSimulationMode) {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80.0),
        );
      }
    }
    print('📍 Temiz basit rota çizildi (${points.length} nokta)');
  }

  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (var point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100.0),
    );
  }

  Future<void> _updatePolylines() async {
    await _drawRoute();
  }

  Future<List<String>> _getPassengerPhotos(String passengerId) async {
    if (passengerId.isEmpty) return [];
    try {
      final photoUrl =
          await EnhancedTrackingService.getPassengerProfilePhoto(passengerId);
      return photoUrl != null ? [photoUrl] : [];
    } catch (e) {
      print('❌ Profil fotoğrafı alma hatası: $e');
      return [];
    }
  }

  void _navigateToStop(StopModel stop) async {
    try {
      if (_currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mevcut konum alınamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (stop.lat == 0.0 || stop.lng == 0.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Durak koordinatları geçersiz'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final stopLatLng = LatLng(stop.lat, stop.lng);
      final currentLatLng =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(currentLatLng.latitude, stopLatLng.latitude) - 0.01,
          math.min(currentLatLng.longitude, stopLatLng.longitude) - 0.01,
        ),
        northeast: LatLng(
          math.max(currentLatLng.latitude, stopLatLng.latitude) + 0.01,
          math.max(currentLatLng.longitude, stopLatLng.longitude) + 0.01,
        ),
      );
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );
      await _drawSingleStopRoute(stop);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 ${stop.address} durağına yönlendiriliyorsunuz'),
          backgroundColor: Colors.blue,
          action: SnackBarAction(
            label: 'Tamam',
            onPressed: () {},
          ),
        ),
      );
      print(
          '🗺️ ${stop.address} durağına kendi harita üzerinde navigasyon başlatıldı');
    } catch (e) {
      print('❌ Navigasyon hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigasyon başlatılamadı'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToAllStops() async {
    try {
      if (_currentPosition == null || _optimizedRoute.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_optimizedRoute.length == 1) {
        _navigateToStop(_optimizedRoute.first);
        return;
      }
      final invalidStops = _optimizedRoute
          .where((stop) => stop.lat == 0.0 || stop.lng == 0.0)
          .toList();
      if (invalidStops.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${invalidStops.length} durağın koordinatları geçersiz'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      final validStops = _optimizedRoute
          .where((stop) => stop.lat != 0.0 && stop.lng != 0.0)
          .toList();
      if (validStops.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geçerli koordinatlı durak bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _fitMapToAllStops(validStops);
      await _drawRoute();
      if (_fullRoutePoints.isNotEmpty) {
        _startAnimatedRoute();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚗 ${validStops.length} durak rotası gösteriliyor'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Rota oluşturulamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print(
          '🗺️ ${validStops.length} durak için kendi harita üzerinde rota hazırlandı');
    } catch (e) {
      print('❌ Çoklu navigasyon hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigasyon başlatılamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fitMapToAllStops(List<StopModel> stops) async {
    if (_mapController == null || stops.isEmpty || _currentPosition == null)
      return;
    try {
      final allPoints = <LatLng>[
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ...stops.map((stop) => LatLng(stop.lat, stop.lng)),
      ];
      if (allPoints.length == 1) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(allPoints.first, 16.0),
        );
        return;
      }
      double minLat = allPoints.first.latitude;
      double maxLat = allPoints.first.latitude;
      double minLng = allPoints.first.longitude;
      double maxLng = allPoints.first.longitude;
      for (final point in allPoints) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
      const padding = 0.005;
      final bounds = LatLngBounds(
        southwest: LatLng(minLat - padding, minLng - padding),
        northeast: LatLng(maxLat + padding, maxLng + padding),
      );
      if (!_isSimulationMode) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80.0),
        );
      }
      print('📍 Harita ${stops.length} durağa sığdırıldı');
    } catch (e) {
      print('❌ Harita sığdırma hatası: $e');
    }
  }

  void _startAnimatedRoute() {
    if (_fullRoutePoints.isEmpty) return;
    print(
        '🎬 Animasyonlu rota başlatılıyor - ${_fullRoutePoints.length} nokta');
    _isAnimating = true;
    _animationProgress = 0.0;
    _animatedRoutePoints.clear();
    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _updateRouteAnimation();
    });
    _createAnimatedMarkers();
  }

  void _updateRouteAnimation() {
    if (!_isAnimating || _fullRoutePoints.isEmpty) {
      _animationTimer?.cancel();
      return;
    }
    _animationProgress += 0.025;
    if (_animationProgress >= 1.0) {
      _animationProgress = 1.0;
      _isAnimating = false;
      _animationTimer?.cancel();
      print('🎬 Rota animasyonu tamamlandı');
    }
    final targetIndex =
        (_animationProgress * (_fullRoutePoints.length - 1)).floor();
    _animatedRoutePoints = _fullRoutePoints.sublist(0, targetIndex + 1);
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('animated_route'),
          points: _animatedRoutePoints,
          color: Colors.blue,
          width: 6,
          patterns: [],
        ),
        if (_animationProgress < 1.0)
          Polyline(
            polylineId: const PolylineId('future_route'),
            points: _fullRoutePoints.sublist(_animatedRoutePoints.length - 1),
            color: Colors.grey.withOpacity(0.5),
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        if (_animatedRoutePoints.length > 1)
          Polyline(
            polylineId: const PolylineId('active_segment'),
            points: _animatedRoutePoints.length > 1
                ? _animatedRoutePoints.sublist(_animatedRoutePoints.length - 2)
                : _animatedRoutePoints,
            color: Colors.green,
            width: 8,
            patterns: [],
          ),
        if (_trackingHistory.length > 1)
          Polyline(
            polylineId: const PolylineId('tracking_history'),
            points: _trackingHistory,
            color: Colors.orange.withOpacity(0.7),
            width: 3,
            patterns: [PatternItem.dot],
          ),
      };
    });
    _createAnimatedMarkers();
  }

  Future<void> _createAnimatedMarkers() async {
    final Set<Marker> animatedMarkers = {};
    if (_currentPosition != null) {
      final driverIcon = _bitmapCache['car_icon_v1'];
      if (driverIcon != null) {
        animatedMarkers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position:
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            icon: driverIcon,
            infoWindow: const InfoWindow(
              title: '🚐 Şoför Konumu',
              snippet: 'Mevcut konum',
            ),
          ),
        );
      }
    }
    for (int i = 0; i < _optimizedRoute.length; i++) {
      final stop = _optimizedRoute[i];
      final String? passengerId = stop.passengerIds?.isNotEmpty == true
          ? stop.passengerIds!.first
          : null;
      final BitmapDescriptor icon = await _getStopMarkerIcon(
        passengerId: passengerId,
        stopNumber: i + 1,
      );
      animatedMarkers.add(Marker(
        markerId: MarkerId('stop_${stop.id}'),
        position: LatLng(stop.lat, stop.lng),
        icon: icon,
        infoWindow: InfoWindow(
          title: '🚏 Durak ${i + 1}',
          snippet: stop.address,
        ),
        onTap: () => _showStopDetails(stop),
      ));
    }
    setState(() {
      _markers = animatedMarkers;
    });
  }

  void _startLiveTracking() {
    print('🎯 Canlı takip sistemi başlatılıyor...');
    _isLiveTracking = true;
    _liveTrackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateLiveLocation();
    });
  }

  void _updateLiveLocation() async {
    try {
      if (_isSimulationMode) return;
      final newPosition = await LocationService.instance.getCurrentPosition();
      if (newPosition == null) return;
      final newLatLng = LatLng(newPosition.latitude, newPosition.longitude);
      if (_lastKnownPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastKnownPosition!.latitude,
          _lastKnownPosition!.longitude,
          newLatLng.latitude,
          newLatLng.longitude,
        );
        if (distance > 10) {
          _animateToNewPosition(newLatLng);
          _trackingHistory.add(newLatLng);
          if (_trackingHistory.length > 100) {
            _trackingHistory.removeAt(0);
          }
        }
      } else {
        _lastKnownPosition = newLatLng;
        _trackingHistory.add(newLatLng);
      }
      _currentPosition = newPosition;
      try {
        await DistanceNotificationService.checkDistanceAlerts(
          driverId: widget.driverId,
          regionId: widget.regionId,
          driverLat: newPosition.latitude,
          driverLng: newPosition.longitude,
        );
      } catch (e) {}
    } catch (e) {
      print('❌ Canlı konum güncelleme hatası: $e');
    }
  }

  void _toggleTestSimulation() async {
    if (_isSimulationMode) {
      SimulationService.stopSimulation();
      _isSimulationMode = false;
      _isTestSimulating = false;
      if (_isLiveTracking) {
        await BackgroundLocationService.startLocationTracking();
        _startLiveTracking();
      }
      _startRealTimeUpdates();
      _shouldFollowUser = false;
      print('✅ Test modu durduruldu - gerçek konum takibi restore edildi');
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Test simülasyonu durduruldu - Gerçek konum takibi başlatıldı'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    List<LatLng> routePoints = [];
    if (_fullRoutePoints.isNotEmpty) {
      routePoints = _fullRoutePoints;
    } else if (_currentDirections != null) {
      routePoints = _currentDirections!.latLngNoktalari;
    } else if (_polylines.isNotEmpty) {
      try {
        Polyline? p = _polylines.firstWhere(
            (pl) => pl.polylineId.value == 'main_route',
            orElse: () => _polylines.firstWhere(
                (pl) => pl.polylineId.value == 'simple_route',
                orElse: () => _polylines.first));
        if (p.points.length > 1) {
          routePoints = p.points;
          _fullRoutePoints = List<LatLng>.from(routePoints);
        }
      } catch (_) {}
    }
    if (routePoints.length < 2 && _optimizedRoute.isNotEmpty) {
      if (_currentPosition != null) {
        routePoints = [
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          ..._optimizedRoute.map((s) => LatLng(s.lat, s.lng))
        ];
      }
    }
    if (routePoints.length < 2) {
      try {
        await _drawRoute();
        if (_fullRoutePoints.length >= 2) {
          routePoints = _fullRoutePoints;
        }
      } catch (_) {}
      if (routePoints.length < 2) {
        await _drawCleanSimpleRoute();
        if (_fullRoutePoints.length >= 2) {
          routePoints = _fullRoutePoints;
        }
      }
      if (routePoints.length < 2 && _currentPosition != null) {
        final center =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        final randomRoute = SimulationService.generateRandomRoute(
          center: center,
          pointCount: 20,
          radiusKm: 1.5,
        );
        if (randomRoute.length >= 2) {
          routePoints = [...randomRoute, randomRoute.first];
          _fullRoutePoints = routePoints;
          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('simple_route_shadow'),
                points: routePoints,
                color: Colors.black.withOpacity(0.15),
                width: 6,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            );
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('simple_route'),
                points: routePoints,
                color: AppColors.primary,
                width: 4,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            );
          });
        }
      }
      if (routePoints.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rota bulunamadı'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }
    routePoints = _densifyRoute(routePoints, 25.0);
    _stopLiveTracking();
    await BackgroundLocationService.forceStopLocationSharing();
    _liveTrackingTimer?.cancel();
    _routeUpdateTimer?.cancel();
    _proximityCheckTimer?.cancel();
    _driversUpdateTimer?.cancel();
    _isSimulationMode = true;
    _isTestSimulating = true;
    _shouldFollowUser = true;
    _isLiveTracking = false;
    print('🚫 TÜM gerçek konum takibi DURDURULDU - test modu aktif');
    SimulationService.startDriverSimulation(
      driverId: widget.driverId,
      route: routePoints,
      speed: 40,
      regionId: widget.regionId,
      vehiclePlate: widget.vehiclePlate,
    );
    SimulationService.getSimulationStream()?.listen((simulationData) async {
      if (simulationData != null && mounted) {
        final newPosition = simulationData.location;
        if (kDebugMode) {
          print(
              '🎮 Simülasyon pozisyon güncellendi: ${newPosition.latitude}, ${newPosition.longitude}');
        }
        _lastKnownPosition = newPosition;
        _currentPosition = Position(
          latitude: newPosition.latitude,
          longitude: newPosition.longitude,
          timestamp: simulationData.timestamp,
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 1,
          heading: simulationData.heading,
          headingAccuracy: 1,
          speed: simulationData.speed,
          speedAccuracy: 1,
        );
        _animateToNewPosition(newPosition);

        _checkSimulationStopCompletion(newPosition);

        await _updateMarkers();
        _updateDriverPosition(newPosition);
        if (_isVoiceNavigationActive) {
          VoiceNavigationService.checkSimulationProgress(newPosition);
        }
        DistanceNotificationService.checkDistanceAlerts(
          driverId: widget.driverId,
          regionId: widget.regionId,
          driverLat: newPosition.latitude,
          driverLng: newPosition.longitude,
        );
      }
    });
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Test simülasyonu başlatıldı - Yolcular takip edebilir'),
      backgroundColor: Colors.green,
    ));
  }

  void _animateToNewPosition(LatLng newPosition) {
    if (_mapController != null) {
      bool shouldAnimate = _shouldFollowUser;
      if (!_isSimulationMode) {
        shouldAnimate = true;
        _shouldFollowUser = true;
      }
      if (!shouldAnimate) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_isAnimatingCamera && now - _lastCameraAnimateMs < 300) {
        return;
      }
      _isAnimatingCamera = true;
      _lastCameraAnimateMs = now;
      _mapController!
          .animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newPosition,
            zoom: _currentZoom,
            tilt: 0.0,
            bearing: 0.0,
          ),
        ),
      )
          .whenComplete(() {
        _isAnimatingCamera = false;
      });
    }
    _lastKnownPosition = newPosition;
    _updateDriverPosition(newPosition);
  }

  List<LatLng> _densifyRoute(List<LatLng> points, double targetSpacingMeters) {
    if (points.length < 2) return points;
    final result = <LatLng>[]..add(points.first);
    LatLng prev = points.first;
    for (int i = 1; i < points.length; i++) {
      final curr = points[i];
      final segLen = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );
      if (segLen <= targetSpacingMeters) {
        result.add(curr);
        prev = curr;
        continue;
      }
      final steps = (segLen / targetSpacingMeters).floor();
      for (int s = 1; s <= steps; s++) {
        final frac = (s * targetSpacingMeters) / segLen;
        if (frac >= 1.0) break;
        final interp = _lerpLatLng(prev, curr, frac);
        result.add(interp);
      }
      result.add(curr);
      prev = curr;
    }
    return result;
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    final lat = a.latitude + (b.latitude - a.latitude) * t;
    final lng = a.longitude + (b.longitude - a.longitude) * t;
    return LatLng(lat, lng);
  }

  double _calculateBearing() {
    if (_trackingHistory.length < 2) return 0.0;
    final last = _trackingHistory.last;
    final previous = _trackingHistory[_trackingHistory.length - 2];
    final dLng = last.longitude - previous.longitude;
    final dLat = last.latitude - previous.latitude;
    final bearing = math.atan2(dLng, dLat) * (180 / math.pi);
    return bearing < 0 ? bearing + 360 : bearing;
  }

  void _updateDriverPosition(LatLng position) async {
    try {
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(widget.driverId)
          .set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'bearing': _calculateBearing(),
        'speed': _isSimulationMode ? 30.0 : 0.0,
        'regionId': _effectiveRegionId ?? widget.regionId,
        'vehiclePlate': widget.vehiclePlate,
        'isSimulation': _isSimulationMode,
        'isActive': true,
      }, SetOptions(merge: true));
      final region = _effectiveRegionId ?? widget.regionId;
      await EnhancedTrackingService.updateServiceStatus(
        regionId: region,
        driverId: widget.driverId,
        driverName: UserSession.driverName ?? 'Bilinmeyen',
        vehiclePlate: widget.vehiclePlate,
        currentLat: position.latitude,
        currentLng: position.longitude,
      );
    } catch (e) {
      print('❌ Şoför konumu kaydetme hatası: $e');
    }
  }

  void _startDriversTracking() {
    print('👥 Diğer şoförler takibi başlatılıyor...');
    _driversUpdateTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      _updateOtherDrivers();
    });
  }

  void _updateOtherDrivers() {
    final currentRegionId = _effectiveRegionId ?? widget.regionId;
    FirebaseFirestore.instance
        .collection('live_locations')
        .where('regionId', isEqualTo: currentRegionId)
        .snapshots()
        .listen((snapshot) async {
      final Map<String, LatLng> nextDrivers = {};
      for (var doc in snapshot.docs) {
        if (doc.id == widget.driverId) continue;
        final data = doc.data();
        final lat = data['lat'] ?? data['latitude'];
        final lng = data['lng'] ?? data['longitude'];
        final docRegionId = data['regionId'];
        if (lat != null && lng != null && docRegionId == currentRegionId) {
          nextDrivers[doc.id] = LatLng(lat.toDouble(), lng.toDouble());
        }
      }
      print(
          '👥 Aynı bölgeden ${nextDrivers.length} şoför bulundu (Bölge: $currentRegionId)');
      _otherDrivers = nextDrivers;
      await _updateOtherDriverMarkers();
    });
  }

  Future<void> _updateOtherDriverMarkers() async {
    if (!mounted) return;
    await _createAllMarkers();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _createAllMarkers() async {
    final Set<Marker> allMarkers = {};
    if (_currentPosition != null) {
      final carIcon = await AvatarMarkerService.createEmojiMarker(
        emoji: '🚌',
        size: 88,
      );
      allMarkers.add(
        Marker(
          markerId: const MarkerId('current_driver'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: carIcon,
          infoWindow: InfoWindow(
            title: '🚐 ${widget.vehiclePlate}',
            snippet: 'Mevcut konum',
          ),
          rotation: _calculateBearing(),
        ),
      );
    }
    await _addCurrentUserMarker(allMarkers);
    for (final entry in _otherDrivers.entries) {
      final driverId = entry.key;
      final position = entry.value;
      final otherCarIcon = await AvatarMarkerService.createEmojiMarker(
        emoji: '🚐',
        size: 72,
      );
      allMarkers.add(
        Marker(
          markerId: MarkerId('driver_$driverId'),
          position: position,
          icon: otherCarIcon,
          infoWindow: InfoWindow(
            title: '🚚 Şoför',
            snippet: 'ID: ${driverId.substring(0, 8)}...',
          ),
        ),
      );
    }
    for (int i = 0; i < _optimizedRoute.length; i++) {
      final stop = _optimizedRoute[i];
      final passengerId = stop.passengerIds?.isNotEmpty == true
          ? stop.passengerIds!.first
          : stop.passengerId;
      String? profilePhotoUrl;
      if (passengerId != null) {
        try {
          profilePhotoUrl =
              await EnhancedTrackingService.getPassengerProfilePhoto(
                  passengerId);
        } catch (e) {
          print('Profil fotoğrafı alınamadı: $e');
        }
      }
      final BitmapDescriptor markerIcon =
          await AvatarMarkerService.createAvatarMarker(
        profileImageUrl: profilePhotoUrl,
        stopNumber: i + 1,
        size: 110,
      );
      final passengerNames = await _getPassengerNamesForStop(stop);
      allMarkers.add(
        Marker(
          markerId: MarkerId('stop_${stop.id}'),
          position: LatLng(stop.lat, stop.lng),
          icon: markerIcon,
          infoWindow: InfoWindow(
            title: '🚏 Durak ${i + 1}',
            snippet: '${stop.address}\n👥 $passengerNames',
          ),
          onTap: () => _showStopDetails(stop),
        ),
      );
    }
    _markers = allMarkers;
  }

  Future<void> _drawSingleStopRoute(StopModel stop) async {
    try {
      if (_currentPosition == null || _directionsService == null) return;
      final origin =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final destination = LatLng(stop.lat, stop.lng);
      print('🗺️ Tek durak rotası çiziliyor: ${stop.address}');
      final directions = await _directionsService!.getDirections(
        baslangic: origin,
        hedef: destination,
      );
      if (directions != null && directions.polylineNoktalari.isNotEmpty) {
        final points = directions.polylineNoktalari
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('single_stop_route'),
              points: points,
              color: AppColors.primary,
              width: 6,
              patterns: [],
            ),
          };
          _markers = {
            Marker(
              markerId: const MarkerId('current_location'),
              position: origin,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(
                title: '🚐 Mevcut Konum',
                snippet: 'Başlangıç noktası',
              ),
            ),
            Marker(
              markerId: MarkerId('target_stop_${stop.id}'),
              position: destination,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(
                title: '🎯 Hedef Durak',
                snippet: stop.address,
              ),
            ),
          };
          _currentDirections = directions;
        });
        print(
            '✅ Tek durak rotası başarıyla çizildi: ${directions.toplamMesafe}');
      } else {
        print('❌ Tek durak rotası çizilemedi');
      }
    } catch (e) {
      print('❌ Tek durak rota çizme hatası: $e');
    }
  }

  Future<String> _getPassengerNamesForStop(StopModel stop) async {
    try {
      final passengerNames = stop.metadata?['passengerNames'] as List<dynamic>?;
      if (passengerNames != null && passengerNames.isNotEmpty) {
        return passengerNames.join(', ');
      }
      final passengerIds = stop.metadata?['passengerIds'] as List<dynamic>?;
      if (passengerIds != null && passengerIds.isNotEmpty) {
        final names = <String>[];
        for (final id in passengerIds) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(id.toString())
                .get();
            if (userDoc.exists) {
              final name = userDoc.data()?['name'] as String?;
              if (name != null) names.add(name);
            }
          } catch (e) {
            print('❌ Yolcu ismi alma hatası: $e');
          }
        }
        return names.join(', ');
      }
      return 'Yolcu bilgisi yok';
    } catch (e) {
      print('❌ Yolcu isimleri alma hatası: $e');
      return 'Hata';
    }
  }

  void _checkStopProximity() async {
    if (_isSimulationMode) {
      print('⏸️ Durak yakınlık kontrolü atlandı - simülasyon modunda');
      return;
    }
    if (_currentPosition == null || _optimizedRoute.isEmpty) return;
    try {
      _currentPosition = await LocationService.instance.getCurrentPosition();
    } catch (e) {
      print('❌ Konum güncellenirken hata: $e');
      return;
    }
    for (var stop in _optimizedRoute) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        stop.lat,
        stop.lng,
      );
      print(
          '📍 Durak mesafesi: ${distance.toStringAsFixed(0)}m - ${stop.address}');
      if (distance <= 50) {
        print('🎯 Durağa yaklaşıldı: ${stop.address}');
        _recordStopArrivalAuto(stop);

        StopCompletionTracker().markStopAsCompleted(stop.id);

        break;
      }
    }
  }

  Set<String> _recordedStops = {};
  Future<void> _recordStopArrivalAuto(StopModel stop) async {
    if (_recordedStops.contains(stop.id)) {
      print('⚠️ Bu durak zaten kaydedildi: ${stop.address}');
      return;
    }
    try {
      print('📝 Otomatik durak kaydı yapılıyor: ${stop.address}');
      await EnhancedRouteService.logStopArrival(
        stopId: stop.id,
        driverId: widget.driverId,
        driverName: UserSession.driverName ?? 'Bilinmeyen',
        vehiclePlate: widget.vehiclePlate,
        regionId: widget.regionId,
        stopAddress: stop.address,
        latitude: stop.lat,
        longitude: stop.lng,
        passengerIds: stop.metadata?['passengerIds']?.cast<String>() ?? [],
        passengerNames: stop.metadata?['passengerIds']?.cast<String>() ?? [],
      );

      StopCompletionTracker().markStopAsCompleted(stop.id);

      _recordedStops.add(stop.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('✅ Durak kaydı: ${stop.address}'),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Otomatik durak kaydı hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('❌ Durak kaydı hatası: ${stop.address}'),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _checkSimulationStopCompletion(LatLng currentPosition) {
    if (!_isSimulationMode || _optimizedRoute.isEmpty) {
      if (kDebugMode) {
        print(
            '🔍 Simülasyon durak kontrolü: isSimulationMode=$_isSimulationMode, routeLength=${_optimizedRoute.length}');
        if (_optimizedRoute.isEmpty) {
          print('⚠️ _optimizedRoute boş! _stops uzunluğu: ${_stops.length}');
        }
      }
      return;
    }

    if (kDebugMode) {
      print(
          '🔍 Simülasyon durak kontrolü başladı - ${_optimizedRoute.length} durak, konum: ${currentPosition.latitude}, ${currentPosition.longitude}');
      print('🔍 Durak detayları:');
      for (int i = 0; i < _optimizedRoute.length; i++) {
        final stop = _optimizedRoute[i];
        print(
            '   🎯 Durak ${i + 1}: ${stop.address} (${stop.lat}, ${stop.lng}) - ID: ${stop.id}');
      }
    }

    for (var stop in _optimizedRoute) {
      final distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        stop.lat,
        stop.lng,
      );

      if (kDebugMode) {
        print(
            '📍 Simülasyon durak mesafesi: ${stop.address} - ${distance.toStringAsFixed(0)}m');
      }

      if (distance <= 50) {
        print(
            '🎯 Simülasyon: Durağa yaklaşıldı: ${stop.address} (${distance.toStringAsFixed(0)}m)');

        StopCompletionTracker().markStopAsCompleted(stop.id);

        if (kDebugMode) {
          print('✅ Durak tamamlandı olarak işaretlendi: ${stop.id}');
          print(
              '🔍 StopCompletionTracker durumu: ${StopCompletionTracker().completedStops}');
        }

        _recordStopArrivalAuto(stop);

        break;
      }
    }
  }

  Future<void> _recordStopArrival(StopModel stop) async {
    try {
      StopCompletionTracker().markStopAsCompleted(stop.id);

      await EnhancedRouteService.logStopArrival(
        stopId: stop.id,
        driverId: widget.driverId,
        driverName: UserSession.driverName ?? 'Bilinmeyen',
        vehiclePlate: widget.vehiclePlate,
        regionId: widget.regionId,
        stopAddress: stop.address,
        latitude: stop.lat,
        longitude: stop.lng,
        passengerIds: stop.metadata?['passengerIds']?.cast<String>() ?? [],
        passengerNames: stop.metadata?['passengerNames']?.cast<String>() ?? [],
      );
      await EnhancedTrackingService.updateServiceStatus(
        regionId: widget.regionId,
        driverId: widget.driverId,
        driverName: UserSession.driverName ?? 'Bilinmeyen',
        vehiclePlate: widget.vehiclePlate,
        currentLat: _currentPosition!.latitude,
        currentLng: _currentPosition!.longitude,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${stop.address} durağına varış kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Varış kaydı hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Varış kaydı hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDepartureDialog(StopModel stop) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duraktan Ayrılıyor'),
        content: Text('${stop.address} durağından ayrılıyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _recordStopDeparture(stop);
            },
            child: const Text('Evet'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordStopDeparture(StopModel stop) async {
    try {
      await EnhancedRouteService.logStopDeparture(
        stopId: stop.id,
        driverId: widget.driverId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${stop.address} durağından ayrılış kaydedildi'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadStops();
      await _optimizeRoute();
      await _updateMapElements();
      if (_mapController != null && _optimizedRoute.isNotEmpty) {
        await _drawRoute();
      }
    } catch (e) {
      print('❌ Ayrılış kaydı hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayrılış kaydı hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showStopDetails(StopModel stop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Durak Detayları',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('Adres', stop.address),
                    _buildDetailRow(
                        'Yolcu', stop.passengerName ?? 'Bilinmeyen'),
                    if (stop.phoneNumber?.isNotEmpty == true)
                      _buildDetailRow('Telefon', stop.phoneNumber!),
                    if (stop.note?.isNotEmpty == true)
                      _buildDetailRow('Not', stop.note!),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _recordStopArrival(stop);
                            },
                            icon: const Icon(Icons.location_on),
                            label: const Text('Vardım'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showDepartureDialog(stop);
                            },
                            icon: const Icon(Icons.directions_run),
                            label: const Text('Ayrıldım'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                'Harita Yükleniyor',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rota ve duraklar hazırlanıyor...',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          toolbarHeight: 0, elevation: 0, backgroundColor: Colors.transparent),
      body: Stack(
        children: [
          GoogleMap(
            mapType: _currentMapType,
            onCameraMoveStarted: () {
              _shouldFollowUser = true;
              _isAnimating = false;
            },
            onCameraIdle: () {},
            onMapCreated: (controller) {
              _mapController = controller;
              print('🗺️ GoogleMap oluşturuldu, controller hazır');
              Future.delayed(Duration(milliseconds: 500), () {
                _centerMapOnCurrentPosition();
                _syncLocationSharingStatus();
                if (_optimizedRoute.isNotEmpty && !_isRouteActive) {
                  _drawRoute();
                }
              });
            },
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude)
                  : const LatLng(39.7348, 32.8597),
              zoom: 15,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: false,
            zoomGesturesEnabled: true,
          ),
          const SizedBox.shrink(),
          _buildSideControls(),
          _buildBottomInfoPanel(),
        ],
      ),
    );
  }

  Widget _buildCleanHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Harita',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideControls() {
    return Positioned(
      top: 140,
      right: 16,
      child: Column(
        children: [
          _buildControlButton(
            Icons.my_location_rounded,
            'Konumum',
            () {
              if (_mapController != null && _currentPosition != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    16,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          if (_optimizedRoute.isNotEmpty)
            _buildControlButton(
              _isTestSimulating ? Icons.stop_circle : Icons.play_circle_fill,
              _isTestSimulating ? 'Test Durdur' : 'Test Başlat',
              () {
                print(
                    '🎮 Test modu: ${widget.driverId} için ${_isTestSimulating ? "durduruluyor" : "başlatılıyor"}');
                _toggleTestSimulation();
              },
            ),
          if (_optimizedRoute.isNotEmpty) const SizedBox(height: 12),
          if (_optimizedRoute.isNotEmpty)
            _buildControlButton(
              Icons.check_circle,
              'Test: Durak Tamamla',
              () {
                if (_optimizedRoute.isNotEmpty) {
                  final firstStop = _optimizedRoute.first;
                  StopCompletionTracker().markStopAsCompleted(firstStop.id);
                  if (kDebugMode) {
                    print(
                        '🧪 Test: İlk durak manuel olarak tamamlandı: ${firstStop.address}');
                  }
                  _updateMarkers();
                }
              },
            ),
          if (_optimizedRoute.isNotEmpty) const SizedBox(height: 12),
          if (_optimizedRoute.isNotEmpty)
            _buildControlButton(
              Icons.refresh,
              'Test: Sıfırla',
              () {
                StopCompletionTracker().resetAllStops();
                if (kDebugMode) {
                  print('🧪 Test: Tüm duraklar sıfırlandı');
                }
                _updateMarkers();
              },
            ),
          if (_optimizedRoute.isNotEmpty) const SizedBox(height: 12),
          if (_optimizedRoute.isNotEmpty)
            _buildControlButton(
              Icons.center_focus_strong_rounded,
              'Rota',
              () {
                if (_mapController != null && _currentDirections != null) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngBounds(
                      _currentDirections!.sinirlar,
                      100.0,
                    ),
                  );
                }
              },
            ),
          if (_optimizedRoute.isNotEmpty) const SizedBox(height: 12),
          _buildControlButton(
            Icons.layers_rounded,
            'Harita',
            () => _showMapTypeSelector(),
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            Icons.refresh_rounded,
            'Yenile',
            () async {
              await _loadStops();
              await _optimizeRoute();
              await _updateMapElements();
              if (_mapController != null && _optimizedRoute.isNotEmpty) {
                await _drawRoute();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
      IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.9)),
        ),
        child: Icon(
          icon,
          size: 22,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildBottomInfoPanel() {
    if (_optimizedRoute.isEmpty) return const SizedBox.shrink();
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color:
                        _isRouteActive ? AppColors.success : AppColors.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_optimizedRoute.length} durak optimize edildi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    _isLiveTracking
                        ? Icons.stop_circle
                        : Icons.play_circle_fill,
                    _isLiveTracking ? 'Konumu Durdur' : 'Konumu Başlat',
                    _isLiveTracking ? AppColors.error : AppColors.success,
                    () async {
                      if (_isLiveTracking) {
                        _stopLiveSharing();
                      } else {
                        await _startLiveSharing();
                        await Future.delayed(Duration(milliseconds: 300));
                        setState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.85),
              color.withOpacity(0.75),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernControlPanel() {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isRouteActive
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.textLight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isRouteActive ? Icons.route : Icons.route_outlined,
                    color: _isRouteActive
                        ? AppColors.success
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRouteActive ? 'Rota Aktif' : 'Rota Hazırlanıyor',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_optimizedRoute.length} durak',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_optimizedRoute.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: Colors.grey.shade200,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildModernControlButton(
                      Icons.center_focus_strong,
                      'Merkez',
                      () {
                        if (_mapController != null &&
                            _currentDirections != null) {
                          _mapController!.animateCamera(
                            CameraUpdate.newLatLngBounds(
                              _currentDirections!.sinirlar,
                              100.0,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModernControlButton(
                      Icons.my_location,
                      'Konumum',
                      () {
                        if (_mapController != null &&
                            _currentPosition != null) {
                          _mapController!.animateCamera(
                            CameraUpdate.newLatLngZoom(
                              LatLng(_currentPosition!.latitude,
                                  _currentPosition!.longitude),
                              16,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModernControlButton(
                      _isLiveTracking
                          ? Icons.stop_circle_outlined
                          : Icons.share_location,
                      _isLiveTracking ? 'Konumu Durdur' : 'Konumu Paylaş',
                      () {
                        if (_isLiveTracking) {
                          _stopLiveSharing();
                        } else {
                          _startLiveSharing();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _launchGoogleMapsNavigation() async {
    if (_optimizedRoute.isEmpty) return;
    try {
      final firstStop = _optimizedRoute.first;
      final url =
          'https://www.google.com/maps/dir/?api=1&destination=${firstStop.lat},${firstStop.lng}&travelmode=driving';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        print(
            '🗺️ Google Maps navigasyon başlatıldı: ${firstStop.lat}, ${firstStop.lng}');
      } else {
        throw 'Google Maps açılamadı';
      }
    } catch (e) {
      print('❌ Navigasyon hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigasyon uygulaması açılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopLiveTracking() {
    _liveTrackingTimer?.cancel();
    _liveTrackingTimer = null;
    print('Live tracking stopped');
  }

  Future<void> _startLiveSharing() async {
    try {
      final hasPerm =
          await BackgroundLocationService.checkLocationPermissions();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konum izni gerekli'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      await BackgroundLocationService.startLocationTracking();
      setState(() {
        _isLiveTracking = true;
      });
      _startLiveTracking();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum paylaşımı başladı'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Konum paylaşımı başlatılamadı: $e');
    }
  }

  Future<void> _stopLiveSharing() async {
    try {
      print(
          '🛑 Enhanced map\'tan manuel konum paylaşımı durdurma başlatıldı...');
      await BackgroundLocationService.forceStopLocationSharing();
      _stopLiveTracking();
      if (mounted) {
        setState(() {
          _isLiveTracking = false;
        });
        print(
            '✅ Enhanced map manuel konum paylaşımı durduruldu - Durum: ${UserSession.isLocationSharing}');
        TopNotificationService.showLocationStopped(context);
      }
    } catch (e) {
      print('❌ Konum paylaşımı durdurulamadı: $e');
    }
  }

  Widget _buildModernControlButton(
      IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernRouteInfo() {
    return Positioned(
      top: 120,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.directions_bus_rounded,
                color: AppColors.info,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optimizasyon: ${_optimizedRoute.length} Durak',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'En verimli rota hesaplandı',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleControls() {
    return Positioned(
      right: 16,
      top: 120,
      child: Column(
        children: [
          _buildCleanButton(
            icon: Icons.my_location,
            onTap: () async {
              if (_mapController != null && _currentPosition != null) {
                await _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    16,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          if (_optimizedRoute.isNotEmpty)
            _buildCleanButton(
              icon: Icons.center_focus_strong,
              onTap: () {
                if (_mapController != null && _currentDirections != null) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngBounds(
                      _currentDirections!.sinirlar,
                      100.0,
                    ),
                  );
                }
              },
            ),
          if (_optimizedRoute.isNotEmpty) const SizedBox(height: 8),
          _buildCleanButton(
            icon: Icons.layers,
            onTap: _showMapTypeSelector,
          ),
        ],
      ),
    );
  }

  Widget _buildCleanButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color? backgroundColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color:
                backgroundColor != null ? Colors.white : Colors.grey.shade700,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildCleanStatusInfo() {
    if (_optimizedRoute.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      bottom: 20 + MediaQuery.of(context).padding.bottom,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.route,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_optimizedRoute.length} durak optimize edildi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    _isLiveTracking ? Icons.stop_circle : Icons.play_circle,
                    _isLiveTracking ? 'Konumu Durdur' : 'Konumu Paylaş',
                    !_isLiveTracking ? AppColors.primary : Colors.grey,
                    _isLiveTracking ? _stopLiveSharing : _startLiveSharing,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : AppColors.textPrimary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMapControls() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.layers),
                title: const Text('Harita Tipi'),
                onTap: () {
                  Navigator.pop(context);
                  _showMapTypeSelector();
                },
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(_isSimulationMode
                    ? 'Test Simülasyonunu Durdur'
                    : 'Test: Rotayı Simüle Et'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleTestSimulation();
                },
              ),
              ListTile(
                leading: Icon(_isVoiceNavigationActive
                    ? Icons.volume_up
                    : Icons.volume_off),
                title: Text(_isVoiceNavigationActive
                    ? 'Sesli Navigasyonu Kapat'
                    : 'Sesli Navigasyonu Aç'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleVoiceNavigation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('ETA Bilgilerini Göster'),
                onTap: () {
                  Navigator.pop(context);
                  _showETAInfo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.center_focus_strong),
                title: const Text('Rotaya Odaklan'),
                onTap: () {
                  Navigator.pop(context);
                  if (_mapController != null && _currentDirections != null) {
                    _mapController!.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        _currentDirections!.sinirlar,
                        100.0,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Konumuma Git'),
                onTap: () {
                  Navigator.pop(context);
                  _goToCurrentLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: isPrimary ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : AppColors.textPrimary,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isPrimary ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMapTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Harita Görünümü',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildMapTypeOption(
                      title: 'Normal Harita',
                      subtitle: 'Standart sokak haritası',
                      icon: Icons.map_rounded,
                      mapType: MapType.normal,
                    ),
                    const SizedBox(height: 12),
                    _buildMapTypeOption(
                      title: 'Uydu Görünümü',
                      subtitle: 'Gerçek uydu fotoğrafları',
                      icon: Icons.satellite_alt_rounded,
                      mapType: MapType.satellite,
                    ),
                    const SizedBox(height: 12),
                    _buildMapTypeOption(
                      title: 'Hibrit Görünüm',
                      subtitle: 'Uydu + sokak isimleri',
                      icon: Icons.layers_rounded,
                      mapType: MapType.hybrid,
                    ),
                    const SizedBox(height: 12),
                    _buildMapTypeOption(
                      title: 'Arazi Haritası',
                      subtitle: 'Topografik detaylar',
                      icon: Icons.terrain_rounded,
                      mapType: MapType.terrain,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapTypeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required MapType mapType,
  }) {
    final isSelected = _currentMapType == mapType;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMapType = mapType;
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<BitmapDescriptor> _createCarIcon() async {
    const int size = 80;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(const Offset(41, 41), 20, shadowPaint);
    final Paint carPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(40, 40), 18, carPaint);
    final Paint innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(40, 40), 14, innerPaint);
    final Paint iconPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    final RRect carShape = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(40, 40),
        width: 16,
        height: 10,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(carShape, iconPaint);
    final ui.Image image =
        await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _getCarIcon() async {
    const cacheKey = 'car_icon_v1';
    final cached = _bitmapCache[cacheKey];
    if (cached != null) return cached;
    final icon = await _createCarIcon();
    _bitmapCache[cacheKey] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _getStopMarkerIcon({
    required String? passengerId,
    required int stopNumber,
  }) async {
    final String cacheKey = 'stop_${passengerId ?? 'default'}_$stopNumber';
    final cached = _bitmapCache[cacheKey];
    if (cached != null) return cached;
    BitmapDescriptor icon;
    if (passengerId != null) {
      icon = await _createPassengerMarker(passengerId, stopNumber);
    } else {
      icon = await _createDefaultStopMarker(stopNumber);
    }
    _bitmapCache[cacheKey] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _createPassengerMarker(
      String passengerId, int stopNumber) async {
    const int size = 110;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint ringPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(55, 55), 52, ringPaint);
    final Paint innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(55, 55), 42, innerPaint);
    bool drewPhoto = false;
    try {
      final photoUrl =
          await EnhancedTrackingService.getPassengerProfilePhoto(passengerId);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        final uri = Uri.parse(photoUrl);
        final ByteData data =
            await NetworkAssetBundle(uri).load(uri.toString());
        final Uint8List bytes = data.buffer.asUint8List();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes,
            targetWidth: 76, targetHeight: 76);
        final ui.FrameInfo frame = await codec.getNextFrame();
        final ui.Image photoImg = frame.image;
        final Rect dst =
            Rect.fromCircle(center: const Offset(55, 55), radius: 38);
        final Path clipPath = Path()
          ..addOval(Rect.fromCircle(center: const Offset(55, 55), radius: 38));
        canvas.save();
        canvas.clipPath(clipPath);
        paintImage(
            canvas: canvas, image: photoImg, rect: dst, fit: BoxFit.cover);
        canvas.restore();
        drewPhoto = true;
      }
    } catch (_) {
      drewPhoto = false;
    }
    if (!drewPhoto) {
      final Paint iconPaint = Paint()
        ..color = AppColors.primary.withOpacity(0.7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(55, 48), 12, iconPaint);
      final RRect body = RRect.fromRectAndRadius(
        Rect.fromLTWH(41, 60, 28, 22),
        const Radius.circular(14),
      );
      canvas.drawRRect(body, iconPaint);
    }
    final RRect badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(70, 78, 28, 20),
      const Radius.circular(10),
    );
    final Paint badgePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawRRect(badge, badgePaint);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: stopNumber.toString(),
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: 28);
    tp.paint(canvas, const Offset(70, 79));
    final ui.Image image =
        await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createDefaultStopMarker(int stopNumber) async {
    const int size = 80;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(40, 40), 35, paint);
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(const Offset(40, 40), 35, borderPaint);
    final TextSpan span = TextSpan(
      text: stopNumber.toString(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(40 - tp.width / 2, 30));
    final ui.Image image =
        await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  void _goToCurrentLocation() async {
    if (_mapController != null && _currentPosition != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          16.0,
        ),
      );
    }
  }

  void _toggleVoiceNavigation() async {
    try {
      if (_isVoiceNavigationActive) {
        await VoiceNavigationService.stopNavigation();
        _isVoiceNavigationActive = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sesli navigasyon kapatıldı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (_currentPosition != null && _optimizedRoute.isNotEmpty) {
          final destination =
              LatLng(_optimizedRoute.first.lat, _optimizedRoute.first.lng);
          await VoiceNavigationService.startNavigation(
            route: [
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              destination
            ],
            onInstructionCallback: (instruction) {
              if (mounted) {
                setState(() {
                  _currentInstruction = instruction;
                });
              }
            },
          );
          _isVoiceNavigationActive = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sesli navigasyon başlatıldı'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Konum veya rota bulunamadı'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Sesli navigasyon hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sesli navigasyon hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showETAInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Varış Süresi Bilgileri',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<Map<String, dynamic>?>(
              stream: ETACalculationService.getRealtimeETA(widget.driverId)
                  .map((etaData) => {
                        'nextStopETA': etaData.estimatedArrival?.toString() ??
                            'Hesaplanıyor...',
                        'totalETA': etaData.estimatedArrival?.toString() ??
                            'Hesaplanıyor...',
                        'remainingDistance': 'Hesaplanıyor...',
                        'averageSpeed': 'Hesaplanıyor...',
                      }),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final etaData = snapshot.data!;
                  return Column(
                    children: [
                      _buildETARow('Sonraki Durak',
                          '${etaData['nextStopETA'] ?? 'Hesaplanıyor...'}'),
                      _buildETARow('Toplam Süre',
                          '${etaData['totalETA'] ?? 'Hesaplanıyor...'}'),
                      _buildETARow('Kalan Mesafe',
                          '${etaData['remainingDistance'] ?? 'Hesaplanıyor...'}'),
                      _buildETARow('Ortalama Hız',
                          '${etaData['averageSpeed'] ?? 'Hesaplanıyor...'}'),
                    ],
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildETARow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _storeCacheKeyForPassengerPanel(String cacheKey) {
    print('🔐 Cache key passenger panel için saklandı: $cacheKey');
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(0, 0),
        northeast: const LatLng(0, 0),
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (var point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _writeRouteToCache(String cacheKey, List<Map<String, dynamic>> stops) {
    try {
      final waypoints = stops
          .map((stop) => {
                'latitude':
                    (stop['latitude'] ?? stop['lat'])?.toDouble() ?? 0.0,
                'longitude':
                    (stop['longitude'] ?? stop['lng'])?.toDouble() ?? 0.0,
                'stopId': stop['stopId'] ?? stop['id'],
                'address': stop['address'],
                'order': stop['order'] ?? 0,
              })
          .toList();

      UnifiedRouteOptimizationService.cacheRoute(cacheKey, waypoints);
      print('💾 Rota cache\'e yazıldı: $cacheKey (${waypoints.length} durak)');

      final stats = UnifiedRouteOptimizationService.getCacheStatistics();
      print(
          '📊 Cache istatistikleri: ${stats['cacheSize']} rota, ${stats['timestampCount']} timestamp');

      final cachedRoute =
          UnifiedRouteOptimizationService.getCachedRoute(cacheKey);
      if (cachedRoute != null) {
        print(
            '✅ Cache doğrulaması başarılı: ${cachedRoute.length} durak bulundu');
        print(
            '🔍 İlk durak: ${cachedRoute.first['address']} (${cachedRoute.first['latitude']}, ${cachedRoute.first['longitude']})');
        print(
            '🔍 Son durak: ${cachedRoute.last['address']} (${cachedRoute.last['latitude']}, ${cachedRoute.last['longitude']})');
      } else {
        print('❌ Cache doğrulaması başarısız: Rota bulunamadı');
      }
    } catch (e) {
      print('❌ Cache yazma hatası: $e');
    }
  }

  void _clearCacheForTesting() {
    try {
      final stats = UnifiedRouteOptimizationService.getCacheStatistics();
      print('🧹 Test öncesi cache istatistikleri: ${stats['cacheSize']} rota');

      UnifiedRouteOptimizationService.clearAllCache();

      final newStats = UnifiedRouteOptimizationService.getCacheStatistics();
      print(
          '🧹 Test sonrası cache istatistikleri: ${newStats['cacheSize']} rota');
      print('✅ Cache test için temizlendi');
    } catch (e) {
      print('❌ Cache temizleme hatası: $e');
    }
  }
}
