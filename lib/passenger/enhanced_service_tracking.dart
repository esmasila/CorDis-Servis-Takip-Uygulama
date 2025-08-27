import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import '../service/location_service.dart';
import '../service/user_session.dart';
import '../service/avatar_marker_service.dart';
import '../service/stop_completion_tracker.dart';
import '../service/simple_stop_service.dart';
import '../service/enhanced_stop_management_service.dart';
import '../service/background_location_service.dart';
import '../service/unified_route_optimization_service.dart';
import '../models/stop_model.dart';
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
    // Durak tamamlama takibini durdur
    StopCompletionTracker().stopTracking();

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
    debugPrint('🚀 Takip başlatılıyor...');
    setState(() => _isLoading = true);

    try {
      // Avatar marker cache'ini temizle
      debugPrint('🧹 Avatar marker cache temizleniyor...');
      AvatarMarkerService.clearCache();

      // Bölge ID'yi çözümle
      debugPrint('🔍 Bölge ID çözümleniyor...');
      await _resolveRegionId();

      // Mevcut konumu al
      debugPrint('📍 Mevcut konum alınıyor...');
      Future.microtask(_getCurrentLocation);

      // Servis durumu takibini başlat
      debugPrint('📡 Servis durumu takibi başlatılıyor...');
      _startServiceStatusTracking();

      // Konum takibini başlat
      debugPrint('📍 Konum takibi başlatılıyor...');
      _startLocationTracking();

      // Durak takibini başlat
      debugPrint('🎯 Durak takibi başlatılıyor...');
      _startStopsTracking();

      // Tüm durakları yükle
      debugPrint('📋 Tüm duraklar yükleniyor...');
      Future.microtask(_loadAllStops);

      debugPrint('✅ Takip başlatma tamamlandı');
    } catch (e) {
      debugPrint('❌ Takip başlatma hatası: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveRegionId() async {
    String rid = widget.regionId;
    debugPrint('🔍 Bölge ID çözümleniyor - Widget: $rid');

    if (rid.isEmpty) {
      rid = UserSession.regionId ?? '';
      debugPrint('🔍 UserSession bölge ID: $rid');
    }

    if (rid.isEmpty) {
      try {
        debugPrint('🔍 Users koleksiyonundan bölge ID aranıyor...');
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.passengerId)
            .get();
        if (u.exists) {
          rid = (u.data()?['regionId'] as String?) ?? '';
          debugPrint('✅ Users koleksiyonundan bölge ID bulundu: $rid');
        } else {
          debugPrint('⚠️ Users koleksiyonunda yolcu bulunamadı');
        }
      } catch (e) {
        debugPrint('❌ Users koleksiyonundan bölge ID alma hatası: $e');
      }
    }

    if (rid.isEmpty) {
      try {
        debugPrint('🔍 Passengers koleksiyonundan bölge ID aranıyor...');
        final p = await FirebaseFirestore.instance
            .collection('passengers')
            .doc(widget.passengerId)
            .get();
        if (p.exists) {
          rid = (p.data()?['regionId'] as String?) ?? '';
          debugPrint('✅ Passengers koleksiyonundan bölge ID bulundu: $rid');
        } else {
          debugPrint('⚠️ Passengers koleksiyonunda yolcu bulunamadı');
        }
      } catch (e) {
        debugPrint('❌ Passengers koleksiyonundan bölge ID alma hatası: $e');
      }
    }

    if (rid.isEmpty) {
      debugPrint('❌ Bölge ID bulunamadı!');
    } else {
      debugPrint('✅ Bölge ID çözümlendi: $rid');
    }

    setState(() => _resolvedRegionId = rid);
  }

  Future<void> _getCurrentLocation() async {
    try {
      debugPrint('📍 Mevcut konum alınıyor...');
      final position = await _locationService.getCurrentLocation();

      if (position != null) {
        debugPrint(
            '✅ Konum alındı: ${position.latitude}, ${position.longitude}');
        setState(() => _currentPosition = position);
        _debouncedRouteAndEta();

        if (_mapController != null) {
          debugPrint('🗺️ Harita kamerası güncelleniyor...');
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              16.0,
            ),
          );
          debugPrint('✅ Harita kamerası güncellendi');
        }
      } else {
        debugPrint('⚠️ Konum alınamadı');
      }
    } catch (e) {
      debugPrint('❌ Konum alma hatası: $e');
    }
  }

  Future<void> _loadAllStops() async {
    try {
      List<Map<String, dynamic>> fetchedStops = [];
      final String regionForStops =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

      // Önce EnhancedStopManagementService ile dene
      try {
        final advStops = await EnhancedStopManagementService.getStopsForRegion(
            regionForStops);
        fetchedStops = advStops;
        debugPrint('Enhanced stops yüklendi: ${fetchedStops.length} durak');
      } catch (e) {
        debugPrint('Enhanced stops yüklenemedi, simple fallback: $e');
        fetchedStops =
            await SimpleStopService.getStopsForRegion(regionForStops);
        debugPrint('Simple stops yüklendi: ${fetchedStops.length} durak');
      }

      // Eğer hala az durak varsa, SimpleStopService ile de dene
      if (fetchedStops.length < 3) {
        try {
          final simpleStops =
              await SimpleStopService.getStopsForRegion(regionForStops);
          debugPrint('Ek simple stops yüklendi: ${simpleStops.length} durak');

          // Tüm durakları birleştir
          final allStops = [...fetchedStops, ...simpleStops];
          fetchedStops = _dedupeStops(allStops);
          debugPrint('Birleştirilmiş toplam durak: ${fetchedStops.length}');
        } catch (e) {
          debugPrint('Ek simple stops yükleme hatası: $e');
        }
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
      debugPrint('Final durak sayısı: ${stops.length}');

      // Durak detaylarını yazdır
      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i];
        final address = stop['address'] ?? 'adres yok';
        final passengerCount = (stop['passengerIds'] as List?)?.length ?? 0;
        debugPrint('📍 Durak ${i + 1}: $address (${passengerCount} yolcu)');
      }

      setState(() {
        _allStops = stops;
        _totalStops = stops.length;
        _completedStops =
            stops.where((stop) => stop['isCompleted'] == true).length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });

      debugPrint(
          '📊 Durak istatistikleri: Toplam: $_totalStops, Tamamlanan: $_completedStops, İlerleme: ${(_routeProgress * 100).toStringAsFixed(1)}%');

      // Progress debug bilgisi
      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i];
        final isCompleted = stop['isCompleted'] == true;
        final address = stop['address'] ?? 'adres yok';
        debugPrint('   ${i + 1}. $address - Tamamlandı: $isCompleted');
      }

      await _updateMapWithAllStops();
    } catch (e) {
      debugPrint('❌ Duraklar yükleme hatası: $e');
    }
  }

  void _startLocationTracking() {
    debugPrint('📍 Konum takibi başlatılıyor (10 saniyede bir)...');
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final position = await _locationService.getCurrentLocation();
        if (position != null && mounted) {
          debugPrint(
              '📍 Konum güncellendi: ${position.latitude}, ${position.longitude}');
          setState(() => _currentPosition = position);
        } else {
          debugPrint('⚠️ Konum güncellenemedi');
        }
      } catch (e) {
        debugPrint('❌ Konum takip hatası: $e');
      }
    });
  }

  void _startServiceStatusTracking() {
    final String rid =
        _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

    debugPrint('📡 Servis durumu takibi başlatılıyor - Bölge: $rid');

    _serviceStatusStream = FirebaseFirestore.instance
        .collection('service_status')
        .doc(rid)
        .snapshots()
        .listen(
      (snapshot) async {
        final data = snapshot.data();
        debugPrint(
            '📡 Servis durumu güncellendi: ${snapshot.exists ? 'var' : 'yok'}');

        if (snapshot.exists && data != null) {
          final newDriverId = data['driverId'] as String?;
          _vehiclePlate = (data['vehiclePlate'] as String?) ?? _vehiclePlate;

          debugPrint('🚌 Şoför ID: $newDriverId, Plaka: $_vehiclePlate');

          if (newDriverId != null && newDriverId.isNotEmpty) {
            if (_activeDriverId != newDriverId) {
              debugPrint('🔄 Yeni şoför tespit edildi: $newDriverId');
              _activeDriverId = newDriverId;
              _subscribeToLiveLocation(newDriverId);
              await _refreshDriverStops();
              _debouncedRouteAndEta();
              _startEtaAutoRecompute();
              _startStopLogsTracking();
            } else {
              debugPrint('✅ Aynı şoför devam ediyor: $newDriverId');
            }
          } else {
            debugPrint('⚠️ Şoför atanmamış, fallback kullanılıyor');
            await _fallbackSubscribeToRegionLatestLiveLocation();
            await _refreshDriverStops();
          }
        } else {
          debugPrint('⚠️ Servis durumu bulunamadı, fallback kullanılıyor');
          await _fallbackSubscribeToRegionLatestLiveLocation();
          await _refreshDriverStops();
        }
      },
      onError: (error) => debugPrint('❌ Servis durumu takip hatası: $error'),
    );
  }

  Future<void> _fallbackSubscribeToRegionLatestLiveLocation() async {
    try {
      debugPrint('🔄 Fallback canlı konum aboneliği başlatılıyor...');

      Query<Map<String, dynamic>> base =
          FirebaseFirestore.instance.collection('live_locations');
      final rid =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

      debugPrint('🔍 Bölge ID: $rid');

      if (rid.isNotEmpty) {
        base = base.where('regionId', isEqualTo: rid);
        debugPrint('📍 Bölge filtresi uygulandı');
      }

      final q =
          await base.orderBy('timestamp', descending: true).limit(1).get();
      debugPrint('📡 Canlı konum sorgusu sonucu: ${q.docs.length} doküman');

      if (q.docs.isNotEmpty) {
        final doc = q.docs.first;
        final driverId = (doc.data()['driverId'] as String?) ?? doc.id;
        debugPrint('🚌 Fallback şoför ID: $driverId');

        if (driverId.isNotEmpty && _activeDriverId != driverId) {
          debugPrint('✅ Yeni fallback şoför aboneliği: $driverId');
          _activeDriverId = driverId;
          _subscribeToLiveLocation(driverId);
        } else {
          debugPrint('⚠️ Fallback şoför değişmedi veya boş');
        }
      } else {
        debugPrint('⚠️ Fallback canlı konum bulunamadı');
      }
    } catch (e) {
      debugPrint('❌ Fallback canlı konum abonelik hatası: $e');
    }
  }

  void _startStopsTracking() {
    final rid =
        _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

    debugPrint('🎯 Durak takibi başlatılıyor - Bölge: $rid');

    // Tüm aktif durakları dinle (source filtresi olmadan)
    _stopsStream = FirebaseFirestore.instance
        .collection('enhanced_stops')
        .where('regionId', isEqualTo: rid)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen(
      (snapshot) async {
        debugPrint(
            '📡 Firestore durak değişikliği: ${snapshot.docs.length} durak');

        // Durak detaylarını yazdır
        for (int i = 0; i < math.min(snapshot.docs.length, 5); i++) {
          final doc = snapshot.docs[i];
          final data = doc.data();
          final address = data['address'] ?? 'adres yok';
          final passengerCount = (data['passengerIds'] as List?)?.length ?? 0;
          final source =
              data['source'] ?? data['createdFromMap'] ?? 'bilinmeyen';
          debugPrint(
              '  📍 Durak ${i + 1}: $address (${passengerCount} yolcu) - Kaynak: $source');
        }

        // Durak sayısını kontrol et
        if (snapshot.docs.length < 3) {
          debugPrint(
              '⚠️ Az durak tespit edildi (${snapshot.docs.length}), durakları yeniden yükle');
          _stopsRedrawDebounce?.cancel();
          _stopsRedrawDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) {
              _loadAllStops(); // Tüm durakları yeniden yükle
            }
          });
        } else {
          debugPrint('✅ Yeterli durak var, şoför duraklarını yenile');
          _stopsRedrawDebounce?.cancel();
          _stopsRedrawDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) {
              _refreshDriverStops();
            }
          });
        }
      },
      onError: (error) => debugPrint('❌ Duraklar takip hatası: $error'),
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
    debugPrint('📋 Durak tamamlama takibi başlatılıyor...');

    _stopLogsSubscription?.cancel();
    final String rid =
        _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

    if (rid.isEmpty) {
      debugPrint('⚠️ Bölge ID bulunamadı, durak takibi başlatılamadı');
      return;
    }

    debugPrint('🔍 Bölge ID: $rid ile durak takibi başlatılıyor');

    _stopLogsSubscription = FirebaseFirestore.instance
        .collection('stop_logs')
        .where('regionId', isEqualTo: rid)
        .where('timestamp',
            isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(hours: 24))))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) async {
      debugPrint('📋 Durak logları güncellendi: ${snapshot.docs.length} kayıt');

      if (snapshot.docs.isEmpty) {
        debugPrint('📋 Henüz durak logu bulunamadı');
        return;
      }

      final Set<String> newCompletedStops = <String>{};
      final Set<String> newCompletedStopIds = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final String? stopId = data['stopId'] as String?;
        final String? stopAddress = data['stopAddress'] as String?;
        final String? action = data['action'] as String?;
        final Timestamp? timestamp = data['timestamp'] as Timestamp?;

        if (stopId != null && action == 'completed' && timestamp != null) {
          // Son 2 saat içindeki tamamlanan durakları kabul et
          final timeDiff = DateTime.now().difference(timestamp.toDate());
          if (timeDiff.inHours <= 2) {
            newCompletedStops.add(stopId);
            newCompletedStopIds.add(stopId);
            debugPrint(
                '✅ Durak tamamlandı: $stopAddress (ID: $stopId) - ${timeDiff.inMinutes} dk önce');
          }
        }
      }

      // Durak tamamlama durumlarını güncelle
      if (newCompletedStops.isNotEmpty || newCompletedStopIds.isNotEmpty) {
        debugPrint('🔄 Durak tamamlama durumları güncelleniyor...');
        debugPrint(
            '   - Yeni tamamlanan duraklar: ${newCompletedStops.length}');
        debugPrint(
            '   - Yeni tamamlanan durak ID\'leri: ${newCompletedStopIds.length}');

        setState(() {
          _completedStopsSet.addAll(newCompletedStops);
          _completedStopIds.addAll(newCompletedStopIds);

          // Toplam tamamlanan durak sayısını güncelle
          _completedStops = _completedStopsSet.length;
          _routeProgress =
              _totalStops > 0 ? _completedStops / _totalStops : 0.0;
        });

        debugPrint('📊 Güncellenmiş istatistikler:');
        debugPrint('   - Toplam durak: $_totalStops');
        debugPrint('   - Tamamlanan durak: $_completedStops');
        debugPrint(
            '   - İlerleme: ${(_routeProgress * 100).toStringAsFixed(1)}%');

        // Haritayı güncelle - avatar renklerini yeniden çiz
        debugPrint(
            '🎨 Harita güncelleniyor - avatar renkleri yeniden çiziliyor');
        await _updateMapWithAllStops();
      }
    }, onError: (e) => debugPrint('❌ Durak logları takip hatası: $e'));
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

        // Check if driver is within 50 meters of the stop and mark as completed
        if (distance <= 50 && !_completedStopsSet.contains(stop['id'])) {
          _updateProgressWhenArrivingAtStop(stop);
        }

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
      // Durak tamamlama takibinde de işaretle
      StopCompletionTracker().markStopAsCompleted(stopId);

      setState(() {
        _completedStopsSet.add(stopId);
        _completedStops = _completedStopsSet.length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });
      _logStopArrival(stopId);

      // Avatar marker cache'ini temizle ve map'i güncelle
      AvatarMarkerService.clearCache();
      _updateMapWithAllStops();

      // Show notification for completed stop
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Durak tamamlandı: ${stop['name'] ?? 'Durak'}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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

      // Şoför duraklarını al
      final driverStops =
          await SimpleStopService.getStopsForDriver(_activeDriverId!);

      // Bölge duraklarını da al (tüm durakları göstermek için)
      final String regionForStops =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;
      List<Map<String, dynamic>> regionStops = [];
      try {
        regionStops = await EnhancedStopManagementService.getStopsForRegion(
            regionForStops);
      } catch (e) {
        debugPrint('Enhanced stops yüklenemedi, simple fallback: $e');
        regionStops = await SimpleStopService.getStopsForRegion(regionForStops);
      }

      // Şoför durakları ve bölge duraklarını birleştir
      var allStops = [...driverStops, ...regionStops];

      // Tekrarlanan durakları temizle
      allStops = _dedupeStops(allStops);

      // Geçici olarak pasif olmayan ve koordinatı olan durakları filtrele
      var filtered = allStops
          .where((s) => (s['temporarilyInactive'] ?? false) != true)
          .where((s) => (s['latitude'] != null && s['longitude'] != null))
          .toList();

      try {
        final mine = await EnhancedStopManagementService.getStopForPassenger(
            widget.passengerId);
        if (mine != null) filtered.add(mine);
      } catch (_) {}

      // Son tekrar tekilleştirme
      filtered = _dedupeStops(filtered);

      debugPrint('🔄 Şoför durakları yenilendi: ${filtered.length} durak');

      // Durak detaylarını yazdır
      for (int i = 0; i < filtered.length; i++) {
        final stop = filtered[i];
        final address = stop['address'] ?? 'adres yok';
        final passengerCount = (stop['passengerIds'] as List?)?.length ?? 0;
        final isMyStop = (stop['passengerId'] == widget.passengerId) ||
            (List<String>.from(stop['passengerIds'] ?? [])
                .contains(widget.passengerId));
        debugPrint(
            '📍 Durak ${i + 1}: $address (${passengerCount} yolcu) ${isMyStop ? '🎯' : ''}');
      }

      if (!mounted) return;
      setState(() {
        _allStops = filtered;
        _totalStops = filtered.length;
        _completedStops = _completedStopIds.length;
        _routeProgress = _totalStops > 0 ? _completedStops / _totalStops : 0.0;
      });

      debugPrint(
          '📊 Güncellenmiş istatistikler: Toplam: $_totalStops, Tamamlanan: $_completedStops, İlerleme: ${(_routeProgress * 100).toStringAsFixed(1)}%');

      await _updateMapWithAllStops();
      _debouncedRouteAndEta();
    } catch (e) {
      debugPrint('❌ Aktif şoför duraklarını yenileme hatası: $e');
    }
  }

  List<Map<String, dynamic>> _dedupeStops(List<Map<String, dynamic>> list) {
    final Map<String, Map<String, dynamic>> uniq = {};
    debugPrint('🔍 Tekilleştirme başlıyor: ${list.length} durak');

    for (final s in list) {
      final String id = (s['id'] as String?)?.trim() ?? '';
      final List<dynamic> pids = (s['passengerIds'] as List<dynamic>?) ?? [];
      final String pid = (s['passengerId'] as String?)?.trim() ??
          (pids.isNotEmpty ? pids.first.toString() : '');
      final double? lat = (s['latitude'] ?? s['lat'])?.toDouble();
      final double? lng = (s['longitude'] ?? s['lng'])?.toDouble();
      final String address = (s['address'] as String?)?.trim() ?? '';

      // Daha kapsamlı tekilleştirme anahtarı
      String key;
      if (id.isNotEmpty) {
        key = 'id:$id';
      } else if (pid.isNotEmpty) {
        key = 'pid:$pid';
      } else if (lat != null && lng != null) {
        // Koordinat bazlı tekilleştirme (100m hassasiyet)
        final latKey = (lat * 1000).round() / 1000;
        final lngKey = (lng * 1000).round() / 1000;
        key = 'geo:${latKey.toStringAsFixed(3)},${lngKey.toStringAsFixed(3)}';
      } else if (address.isNotEmpty) {
        // Adres bazlı tekilleştirme
        key = 'addr:${address.toLowerCase().hashCode}';
      } else {
        // Son çare olarak hash
        key = 'hash:${s.hashCode}';
      }

      if (!uniq.containsKey(key)) {
        uniq[key] = s;
        debugPrint('✅ Yeni durak eklendi: $key - $address');
      } else {
        final prev = uniq[key]!;
        final prevTs = prev['createdAt'];
        final curTs = s['createdAt'];
        final bool isNewer = (prevTs is Timestamp && curTs is Timestamp)
            ? curTs.compareTo(prevTs) > 0
            : true;
        if (isNewer) {
          uniq[key] = s;
          debugPrint('🔄 Durak güncellendi: $key - $address');
        } else {
          debugPrint('⏭️ Eski durak atlandı: $key - $address');
        }
      }
    }

    final result = uniq.values.toList();
    debugPrint(
        '✅ Tekilleştirme tamamlandı: ${list.length} -> ${result.length} durak');

    // Sonuç detaylarını yazdır
    for (int i = 0; i < result.length; i++) {
      final stop = result[i];
      final address = stop['address'] ?? 'adres yok';
      final passengerCount = (stop['passengerIds'] as List?)?.length ?? 0;
      debugPrint('  📍 Sonuç ${i + 1}: $address (${passengerCount} yolcu)');
    }

    return result;
  }

  void _startEtaAutoRecompute() {
    _etaRecomputeTimer?.cancel();
    _etaRecomputeTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      if (_driverLatLng == null || _myStopLatLng == null) return;
      // Gereksiz tekrar kaldırıldı
      await _recomputeETA();
    });
  }

  void _subscribeToLiveLocation(String driverId) {
    debugPrint('📡 Şoför canlı konum aboneliği başlatılıyor: $driverId');

    _liveLocationDocStream?.cancel();
    _liveLocationDocStream = FirebaseFirestore.instance
        .collection('live_locations')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) async {
      if (_isTestMode) {
        debugPrint('🧪 Test modu aktif, konum güncellenmedi');
        return;
      }

      final data = snapshot.data();
      if (data != null) {
        debugPrint('📍 Şoför konum güncellendi');

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
            debugPrint('🚗 Hız: ${speedKmh.toStringAsFixed(1)} km/h');
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
            debugPrint('📍 Mesafe değişimi: ${distance.toStringAsFixed(1)}m');
          }

          final bool isMoving = isMovingBySpeed || isMovingByLocation;
          _recentDriverPositions.add(pos);
          if (_recentDriverPositions.length > _maxRecentPositions) {
            _recentDriverPositions.removeAt(0);
          }

          final bool isMovingByTime = _analyzeMovementByTime();
          final bool finalIsMoving = isMoving || isMovingByTime;

          debugPrint(
              '🔄 Şoför durumu: ${finalIsMoving ? 'Hareket Halinde' : 'Durakta'}');

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
          // Sadece debounced versiyonu çağır, çakışmayı önle
          _debouncedRouteAndEta();
        } else {
          debugPrint('⚠️ Şoför konum koordinatları geçersiz');
        }
      } else {
        debugPrint('⚠️ Şoför konum verisi bulunamadı');
      }
    }, onError: (e) => debugPrint('❌ live_locations hata: $e'));
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
    debugPrint('🗺️ Harita güncelleniyor - ${_allStops.length} durak');

    // Avatar marker cache'ini temizle - yeni durumları yansıtmak için
    AvatarMarkerService.clearCache();

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
      debugPrint('📍 Mevcut konum markeri eklendi');
    }

    _myStopLatLng = null;
    int validStopCount = 0;

    for (int i = 0; i < _allStops.length; i++) {
      final stop = _allStops[i];
      final stopLatLng = _extractStopLatLng(stop);

      if (stopLatLng == null) {
        debugPrint(
            '⚠️ Durak ${i + 1} koordinatı geçersiz: ${stop['id'] ?? 'bilinmeyen'}');
        continue;
      }

      validStopCount++;
      final bool isMyStop = (stop['passengerId'] == widget.passengerId) ||
          (List<String>.from(stop['passengerIds'] ?? [])
              .contains(widget.passengerId));

      if (isMyStop) {
        _myStopLatLng = stopLatLng;
        debugPrint(
            '🎯 Yolcunun durağı bulundu: ${stop['address'] ?? 'adres yok'}');
      }

      // Check if stop is completed/visited - DÜZELTME: Başlangıçta tüm duraklar kırmızı olmalı
      final bool isStopCompleted = _completedStopsSet.contains(stop['id']) ||
          stop['isCompleted'] == true ||
          stop['status'] == 'completed' ||
          stop['status'] == 'visited';

      // Debug: Durak durumunu yazdır
      debugPrint(
          '📍 Durak ${i + 1}: ${stop['address'] ?? 'adres yok'} - Tamamlandı: $isStopCompleted');

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

      debugPrint(
          '📍 Durak ${i + 1} markeri eklendi: ${stop['address'] ?? 'adres yok'}');
    }

    debugPrint('✅ Toplam ${validStopCount} geçerli durak markeri eklendi');
    if (!mounted) return;
    setState(() => _markers = newMarkers);

    debugPrint('🎨 Avatar markerlar oluşturuluyor...');
    const int maxAvatarized = 30;
    final int limit = math.min(_allStops.length, maxAvatarized);

    Future.microtask(() async {
      int avatarCount = 0;
      for (int i = 0; i < limit; i++) {
        if (!mounted) return;
        final stop = _allStops[i];
        final stopLatLng = _extractStopLatLng(stop);
        if (stopLatLng == null) continue;

        final bool isMyStop = (stop['passengerId'] == widget.passengerId) ||
            (List<String>.from(stop['passengerIds'] ?? [])
                .contains(widget.passengerId));

        // DÜZELTME: Avatar renk mantığı - başlangıçta kırmızı, tamamlandığında yeşil
        final bool isStopCompleted = _completedStopsSet.contains(stop['id']) ||
            stop['isCompleted'] == true ||
            stop['status'] == 'completed' ||
            stop['status'] == 'visited';

        // Debug: Avatar renk durumunu yazdır
        debugPrint(
            '🎨 Avatar ${i + 1}: ${stop['address'] ?? 'adres yok'} - Renk: ${isStopCompleted ? 'Yeşil (Tamamlandı)' : 'Kırmızı (Bekliyor)'}');

        try {
          final avatarIcon = await AvatarMarkerService.createAvatarMarker(
            profileImageUrl: (stop['profileImageUrl'] ?? '') as String?,
            stopNumber: i + 1,
            size: 60,
            isCompleted:
                isStopCompleted, // DÜZELTME: Renk mantığı burada belirleniyor
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
          avatarCount++;
        } catch (e) {
          debugPrint('⚠️ Avatar marker oluşturma hatası (durak $i): $e');
        }
      }
      debugPrint('✅ ${avatarCount} avatar marker oluşturuldu');
    });
    if (_myStopLatLng == null &&
        (_estimatedArrival != null || _etaMinuteTicker != null)) {
      debugPrint('⚠️ Yolcunun durağı bulunamadı, ETA temizleniyor');
      _etaMinuteTicker?.cancel();
      if (mounted) {
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
      }
    }

    debugPrint('🗺️ Harita güncelleme tamamlandı - ${_markers.length} marker');
    _debouncedRouteAndEta();
  }

  Future<void> _updateDriverMarker(LatLng driverPosition) async {
    try {
      debugPrint('🎨 Şoför marker güncelleniyor...');

      // Şoför marker'ı için sadece emoji göster, avatar yok
      final avatarIcon = await AvatarMarkerService.createEmojiMarker(
        emoji: '🚌',
        size: 80.0,
        backgroundColor: const Color(0xFF2563EB),
        borderColor: const Color(0xFFFFFFFF),
        borderWidth: 3.0,
      );

      final driverMarker = Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition,
        icon: avatarIcon,
        infoWindow: InfoWindow(
          title:
              '🚌 Şoför${_vehiclePlate.isNotEmpty ? ' ($_vehiclePlate)' : ''}',
          snippet: _driverStatus,
        ),
      );

      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'driver');
        _markers.add(driverMarker);
      });

      debugPrint(
          '✅ Şoför marker güncellendi: ${driverPosition.latitude}, ${driverPosition.longitude}');
    } catch (e) {
      debugPrint('❌ Şoför marker güncelleme hatası: $e');
    }
  }

  void _debouncedRouteAndEta() {
    debugPrint(
        '⏱️ Rota ve ETA güncelleme başlatılıyor (${kDirectionsDebounceMs}ms gecikme)...');

    _directionsDebounce?.cancel();
    _directionsDebounce =
        Timer(const Duration(milliseconds: kDirectionsDebounceMs), () async {
      debugPrint('🚀 Rota ve ETA güncelleme başlatıldı');

      await _updateRoutePolylineViaDirections();
      await _recomputeETA();

      if (_followDriverCamera &&
          _driverLatLng != null &&
          _mapController != null) {
        debugPrint('📷 Şoför kamerası takip ediliyor');
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _driverLatLng!, zoom: 16.0),
          ),
        );
      }

      debugPrint('✅ Rota ve ETA güncelleme tamamlandı');
    });
  }

  Future<void> _updateRoutePolylineViaDirections() async {
    if (_driverLatLng == null || _allStops.isEmpty) {
      debugPrint('⚠️ Rota güncellenemedi: Şoför konumu veya duraklar eksik');
      return;
    }

    debugPrint('🗺️ Rota güncelleniyor...');
    debugPrint(
        '   - Şoför konumu: ${_driverLatLng!.latitude}, ${_driverLatLng!.longitude}');
    debugPrint('   - Toplam durak sayısı: ${_allStops.length}');

    try {
      if (_isDrawingRoute) {
        debugPrint('⚠️ Rota çizimi zaten devam ediyor, atlandı');
        return;
      }

      if (_driverLatLng == null) {
        debugPrint('⚠️ Şoför konumu bulunamadı, rota temizleniyor');
        if (mounted) setState(() => _polylines.clear());
        return;
      }

      debugPrint('🗺️ Rota polyline güncelleniyor...');
      _isDrawingRoute = true;

      try {
        if (_allStops.isEmpty) {
          debugPrint(
              '⚠️ Durak listesi boş, sadece yolcu durağına rota çiziliyor');
          await _ensureMyStopLatLng();
          if (_myStopLatLng != null) {
            await _drawDriverToMyStopRoute();
          } else {
            if (mounted) setState(() => _polylines.clear());
          }
          return;
        }

        debugPrint(
            '📋 ${_allStops.length} durak şoför paneli ile uyumlu sıralanıyor...');
        // Şoför panelindeki gibi sıralama yap
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

        debugPrint(
            '✅ ${activeOrdered.length} aktif durak bulundu (şoför paneli ile uyumlu)');

        if (activeOrdered.isEmpty) {
          debugPrint(
              '⚠️ Aktif durak bulunamadı, sadece yolcu durağına rota çiziliyor');
          await _ensureMyStopLatLng();
          if (_myStopLatLng != null) {
            await _drawDriverToMyStopRoute();
          } else {
            if (mounted) setState(() => _polylines.clear());
          }
          return;
        }
        debugPrint('🚀 Şoför paneli ile uyumlu rota çiziliyor...');

        // Şoför panelindeki gibi optimize edilmiş rota kullan
        final origin =
            PointLatLng(_driverLatLng!.latitude, _driverLatLng!.longitude);
        debugPrint('📍 Başlangıç: ${origin.latitude}, ${origin.longitude}');

        // Durakları şoför panelindeki sırayla sırala
        final optimizedStops = await _optimizeStopsForRoute(activeOrdered);
        debugPrint(
            '🎯 ${optimizedStops.length} optimize edilmiş durak ile rota çiziliyor');

        final double? destLatNum =
            (optimizedStops.last['latitude'] ?? optimizedStops.last['lat'])
                ?.toDouble();
        final double? destLngNum =
            (optimizedStops.last['longitude'] ?? optimizedStops.last['lng'])
                ?.toDouble();

        if (destLatNum == null || destLngNum == null) {
          debugPrint('❌ Son durak koordinatları geçersiz, rota temizleniyor');
          if (mounted) setState(() => _polylines.clear());
          return;
        }

        final destination = PointLatLng(destLatNum, destLngNum);
        debugPrint(
            '🎯 Hedef: ${destination.latitude}, ${destination.longitude}');

        // DÜZELTME: Tüm durak noktalarını waypoint olarak ekle
        final waypoints = <PolylineWayPoint>[];
        if (optimizedStops.length > 1) {
          debugPrint('📍 Tüm durak noktaları waypoint olarak ekleniyor...');
          for (int i = 0; i < optimizedStops.length - 1; i++) {
            final lat =
                (optimizedStops[i]['latitude'] ?? optimizedStops[i]['lat'])
                    ?.toDouble();
            final lng =
                (optimizedStops[i]['longitude'] ?? optimizedStops[i]['lng'])
                    ?.toDouble();
            if (lat == null || lng == null) {
              debugPrint(
                  '⚠️ Ara nokta ${i + 1} koordinatları geçersiz, atlandı');
              continue;
            }
            // Tüm durak noktalarını ekle - optimize:false ile sırayı koru
            waypoints.add(PolylineWayPoint(location: '$lat,$lng'));
            debugPrint(
                '📍 Waypoint ${i + 1}: $lat, $lng (${optimizedStops[i]['address'] ?? 'adres yok'})');
          }
          debugPrint(
              '✅ ${waypoints.length} waypoint eklendi (tüm durak noktaları dahil)');
        }

        if (_isApiKeyValid) {
          // DÜZELTME: Tüm durak noktaları dahil edilerek rota çizimi
          final polylinePoints = PolylinePoints(apiKey: kGoogleApiKey);
          final result = await polylinePoints.getRouteBetweenCoordinates(
            request: PolylineRequest(
              origin: origin,
              destination: destination,
              mode: TravelMode.driving,
              wayPoints: waypoints,
              optimizeWaypoints:
                  false, // DÜZELTME: Sırayı koru, tüm noktaları dahil et
            ),
          );
          if (result.points.isNotEmpty) {
            final pts = result.points
                .map((e) => LatLng(e.latitude, e.longitude))
                .toList();

            debugPrint(
                '✅ Google Directions API rota noktaları alındı: ${pts.length} nokta');

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

            if (mounted) {
              setState(() {
                _polylines = set;
                _lastRoutePoints = pts;
              });
              debugPrint('✅ Rota polyline güncellendi - ${pts.length} nokta');
            }

            if (_mapController != null) {
              debugPrint('🗺️ Harita kamerası rota sınırlarına ayarlanıyor...');
              final bounds = _computeBounds(includePolyline: pts);
              if (bounds != null) {
                await _mapController!.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, 80),
                );
                debugPrint('✅ Harita kamerası rota sınırlarına ayarlandı');
              }
            }

            debugPrint(
                '✅ Google Directions API rota başarıyla çizildi - Tüm durak noktaları dahil');
            return;
          } else {
            debugPrint(
                '⚠️ Google Directions API boş rota döndürdü, fallback kullanılıyor');
          }
        } else {
          debugPrint('⚠️ Google API anahtarı geçersiz');
        }

        debugPrint('🔄 Fallback rota çizimi deneniyor...');
        await _ensureMyStopLatLng();
        if (_myStopLatLng != null) {
          debugPrint('📍 Yolcu durağına fallback rota çiziliyor');
          await _drawDriverToMyStopRoute();
          return;
        }

        // DÜZELTME: Gelişmiş fallback rota - tüm durak noktaları dahil
        debugPrint(
            '📍 Gelişmiş fallback rota çiziliyor - tüm durak noktaları dahil');
        final fallbackPts = <LatLng>[_driverLatLng!];
        for (final s in optimizedStops) {
          final p = _extractStopLatLng(s);
          if (p != null) {
            fallbackPts.add(p);
            debugPrint(
                '📍 Fallback nokta eklendi: ${p.latitude}, ${p.longitude}');
          }
        }

        if (fallbackPts.length >= 2) {
          debugPrint(
              '✅ Gelişmiş fallback rota çizildi: ${fallbackPts.length} nokta (tüm durak noktaları dahil)');
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
          debugPrint('⚠️ Fallback rota çizilemedi, polyline temizleniyor');
          if (mounted) setState(() => _polylines.clear());
        }
      } catch (e) {
        debugPrint('❌ Polyline (Directions) hatası: $e');
      } finally {
        _isDrawingRoute = false;
        debugPrint('✅ Rota çizimi tamamlandı');
      }
    } catch (e) {
      debugPrint('❌ Polyline (Directions) hatası: $e');
    }
  }

  Future<void> _drawDriverToMyStopRoute() async {
    if (_driverLatLng == null || _myStopLatLng == null) {
      debugPrint('⚠️ Şoför veya yolcu durağı konumu bulunamadı');
      return;
    }

    debugPrint('📍 Yolcu durağına rota çiziliyor...');
    debugPrint(
        '🚌 Şoför: ${_driverLatLng!.latitude}, ${_driverLatLng!.longitude}');
    debugPrint(
        '🎯 Yolcu durağı: ${_myStopLatLng!.latitude}, ${_myStopLatLng!.longitude}');
    try {
      if (_isApiKeyValid) {
        debugPrint('🚀 Google Directions API ile rota çiziliyor...');
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
    } catch (e) {
      debugPrint('❌ Google Directions API rota çizme hatası: $e');
    }

    debugPrint('📍 Basit fallback rota çiziliyor...');
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
      debugPrint('✅ Yolcu durağına basit fallback rota çizildi');
    }

    if (_mapController != null) {
      debugPrint('🗺️ Harita kamerası basit rota sınırlarına ayarlanıyor...');
      final bounds = _computeBounds(includePolyline: pts);
      if (bounds != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );
        debugPrint('✅ Harita kamerası basit rota sınırlarına ayarlandı');
      }
    }

    debugPrint('✅ Yolcu durağına rota çizimi tamamlandı');
  }

  Future<void> _ensureMyStopLatLng() async {
    if (_myStopLatLng != null) {
      debugPrint('✅ Yolcu durağı zaten mevcut');
      return;
    }

    debugPrint('🔍 Yolcu durağı aranıyor...');

    // İlk yöntem: EnhancedStopManagementService
    try {
      debugPrint('🔍 EnhancedStopManagementService ile aranıyor...');
      final mine = await EnhancedStopManagementService.getStopForPassenger(
          widget.passengerId);

      if (mine != null) {
        debugPrint(
            '✅ EnhancedStopManagementService ile yolcu durağı bulundu: ${mine['address'] ?? 'adres yok'}');
        final p = _extractStopLatLng(mine);

        if (p != null) {
          _myStopLatLng = p;
          debugPrint(
              '📍 Yolcu durağı koordinatları: ${p.latitude}, ${p.longitude}');
          return;
        } else {
          debugPrint(
              '⚠️ EnhancedStopManagementService ile bulunan durak koordinatları geçersiz');
        }
      } else {
        debugPrint(
            '⚠️ EnhancedStopManagementService ile yolcu durağı bulunamadı');
      }
    } catch (e) {
      debugPrint('❌ EnhancedStopManagementService arama hatası: $e');
    }

    // İkinci yöntem: Firestore sorgusu
    try {
      debugPrint('🔍 Firestore sorgusu ile aranıyor...');
      final rid =
          _resolvedRegionId.isNotEmpty ? _resolvedRegionId : widget.regionId;

      if (rid.isEmpty) {
        debugPrint('⚠️ Bölge ID bulunamadı');
        return;
      }

      debugPrint('🔍 Bölge ID: $rid');
      final snap = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: rid)
          .where('isActive', isEqualTo: true)
          .where('passengerIds', arrayContains: widget.passengerId)
          .limit(1)
          .get();

      debugPrint('📡 Firestore sorgu sonucu: ${snap.docs.length} doküman');

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        debugPrint(
            '✅ Firestore ile yolcu durağı bulundu: ${data['address'] ?? 'adres yok'}');

        final p = _extractStopLatLng(data);
        if (p != null) {
          _myStopLatLng = p;
          debugPrint(
              '📍 Yolcu durağı koordinatları: ${p.latitude}, ${p.longitude}');
        } else {
          debugPrint('⚠️ Firestore ile bulunan durak koordinatları geçersiz');
        }
      } else {
        debugPrint('⚠️ Firestore ile yolcu durağı bulunamadı');
      }
    } catch (e) {
      debugPrint('❌ Firestore arama hatası: $e');
    }

    if (_myStopLatLng == null) {
      debugPrint('❌ Yolcu durağı koordinatları alınamadı');
    }
  }

  Future<void> _recomputeETA() async {
    debugPrint('⏱️ ETA yeniden hesaplanıyor...');

    if (_driverLatLng == null || _myStopLatLng == null) {
      debugPrint(
          '⚠️ Şoför veya yolcu durağı konumu bulunamadı, ETA temizleniyor');
      if (mounted)
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
      return;
    }

    debugPrint(
        '🚌 Şoför konumu: ${_driverLatLng!.latitude}, ${_driverLatLng!.longitude}');
    debugPrint(
        '🎯 Yolcu durağı: ${_myStopLatLng!.latitude}, ${_myStopLatLng!.longitude}');

    if (!_isApiKeyValid) {
      debugPrint('⚠️ Google API anahtarı geçersiz, fallback ETA kullanılıyor');
      _fallbackEta();
      return;
    }

    try {
      debugPrint('🚀 Google Directions API ile ETA hesaplanıyor...');
      final eta = await _fetchETAWithDirections(
        origin: _driverLatLng!,
        destination: _myStopLatLng!,
      );

      debugPrint('✅ Google Directions API ETA: $eta');

      if (mounted) {
        setState(() {
          _estimatedArrival = eta;
          _etaRemainingMinutes = _parseMinutes(eta);
        });
        debugPrint(
            '✅ ETA güncellendi: $_estimatedArrival (${_etaRemainingMinutes} dk)');
      }

      _startEtaMinuteTicker();
    } catch (e) {
      debugPrint(
          '❌ Google Directions API ETA hatası: $e, fallback kullanılıyor');
      _fallbackEta();
    }
  }

  void _fallbackEta() {
    debugPrint('🔄 Şoför paneli ile uyumlu fallback ETA hesaplanıyor...');

    try {
      final dMeters = Geolocator.distanceBetween(
        _driverLatLng!.latitude,
        _driverLatLng!.longitude,
        _myStopLatLng!.latitude,
        _myStopLatLng!.longitude,
      );

      final distanceKm = dMeters / 1000.0;
      // Şoför panelindeki gibi daha gerçekçi hız kullan
      final speedKmh = _lastDriverSpeedKmh.clamp(15.0, 80.0);

      debugPrint('📏 Mesafe: ${distanceKm.toStringAsFixed(2)} km');
      debugPrint('🚗 Hız: ${speedKmh.toStringAsFixed(1)} km/h');

      // Şoför panelindeki gibi daha detaylı trafik faktörü
      final traffic = distanceKm > 15
          ? 1.35 // Uzun mesafe - daha fazla trafik
          : distanceKm > 8
              ? 1.25 // Orta mesafe
              : distanceKm > 3
                  ? 1.15 // Kısa mesafe
                  : 1.08; // Çok kısa mesafe

      debugPrint('🚦 Trafik faktörü: $traffic');

      final minutes = (distanceKm / speedKmh * 60) * traffic;
      debugPrint('⏱️ Hesaplanan süre: ${minutes.toStringAsFixed(1)} dk');

      if (mounted) {
        final m = minutes
            .clamp(1, 120)
            .round(); // Şoför paneli ile uyumlu maksimum süre
        setState(() {
          _estimatedArrival = '$m dk';
          _etaRemainingMinutes = m;
        });

        debugPrint('✅ Şoför paneli ile uyumlu fallback ETA güncellendi: $m dk');
        _startEtaMinuteTicker();
      }
    } catch (e) {
      debugPrint('❌ Fallback ETA hesaplama hatası: $e');
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
    debugPrint(
        '🌐 Şoför paneli ile uyumlu Google Directions API ETA sorgusu...');
    debugPrint('📍 Başlangıç: ${origin.latitude}, ${origin.longitude}');
    debugPrint('🎯 Hedef: ${destination.latitude}, ${destination.longitude}');

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'departure_time': 'now',
        'traffic_model': 'best_guess',
        'avoid': 'tolls', // Şoför paneli ile uyumlu
        'units': 'metric', // Şoför paneli ile uyumlu
        'language': 'tr', // Şoför paneli ile uyumlu
        'region': 'tr', // Şoför paneli ile uyumlu
        'key': kGoogleApiKey,
      },
    );

    debugPrint(
        '🔗 API URL: ${uri.toString().replaceAll(kGoogleApiKey, '***')}');

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      debugPrint('📡 HTTP yanıt kodu: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        throw Exception('Directions HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final status = body['status'];
      debugPrint('📊 API durumu: $status');

      if (status != 'OK') {
        throw Exception('Directions status: $status');
      }

      final routes = body['routes'] as List<dynamic>;
      debugPrint('🛣️ Rota sayısı: ${routes.length}');

      if (routes.isEmpty) throw Exception('No routes');

      final legs = routes.first['legs'] as List<dynamic>;
      debugPrint('🦵 Bacak sayısı: ${legs.length}');

      if (legs.isEmpty) throw Exception('No legs');

      final leg0 = legs.first as Map<String, dynamic>;
      final durTraffic = leg0['duration_in_traffic'] as Map<String, dynamic>?;
      final dur = leg0['duration'] as Map<String, dynamic>?;

      debugPrint('⏱️ Trafik süresi: ${durTraffic?['text'] ?? 'yok'}');
      debugPrint('⏱️ Normal süre: ${dur?['text'] ?? 'yok'}');

      int seconds;
      if (durTraffic != null && durTraffic['value'] is num) {
        seconds = (durTraffic['value'] as num).toInt();
        debugPrint('✅ Trafik süresi kullanıldı: ${seconds}s');
      } else if (dur != null && dur['value'] is num) {
        seconds = (dur['value'] as num).toInt();
        debugPrint('✅ Normal süre kullanıldı: ${seconds}s');
      } else {
        throw Exception('No duration');
      }

      final formattedDuration = _formatDuration(seconds);
      debugPrint('✅ ETA formatlandı: $formattedDuration');
      return formattedDuration;
    } catch (e) {
      debugPrint('❌ Google Directions API ETA hatası: $e');
      rethrow;
    }
  }

  String _formatDuration(int seconds) {
    debugPrint('⏱️ Süre formatlanıyor: ${seconds}s');

    if (seconds <= 60) {
      debugPrint('✅ 1 dakika veya daha az: 1 dk');
      return '1 dk';
    }

    final minutes = (seconds / 60).round();
    debugPrint('⏱️ Dakika: $minutes dk');

    if (minutes < 60) {
      debugPrint('✅ 60 dakikadan az: $minutes dk');
      return '$minutes dk';
    }

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    debugPrint('🕐 Saat: $hours, Dakika: $mins');

    if (mins == 0) {
      debugPrint('✅ Tam saat: $hours sa');
      return '$hours sa';
    }

    final formatted = '$hours sa $mins dk';
    debugPrint('✅ Saat ve dakika: $formatted');
    return formatted;
  }

  void _startEtaMinuteTicker() {
    debugPrint('⏱️ ETA dakika sayacı başlatılıyor...');

    _etaMinuteTicker?.cancel();
    if (_etaRemainingMinutes == null) {
      debugPrint('⚠️ ETA dakika sayısı bulunamadı, sayaç başlatılamadı');
      return;
    }

    debugPrint('✅ ETA dakika sayacı başlatıldı: ${_etaRemainingMinutes} dk');

    _etaMinuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        debugPrint('⚠️ Widget mounted değil, sayaç durduruluyor');
        return;
      }

      if (_etaRemainingMinutes == null) {
        debugPrint('⚠️ ETA dakika sayısı null, sayaç durduruluyor');
        return;
      }

      if (_myStopLatLng == null) {
        debugPrint(
            '⚠️ Yolcu durağı bulunamadı, ETA temizleniyor ve sayaç durduruluyor');
        _etaMinuteTicker?.cancel();
        setState(() {
          _estimatedArrival = null;
          _etaRemainingMinutes = null;
        });
        return;
      }

      if (_etaRemainingMinutes! <= 1) {
        debugPrint('🎯 ETA 1 dakika veya daha az, sayaç durduruluyor');
        setState(() {
          _etaRemainingMinutes = 0;
          _estimatedArrival = '1 dk';
        });
        _etaMinuteTicker?.cancel();
      } else {
        final newMinutes = (_etaRemainingMinutes! - 1).clamp(0, 9999);
        debugPrint(
            '⏱️ ETA güncelleniyor: ${_etaRemainingMinutes} -> $newMinutes dk');
        setState(() {
          _etaRemainingMinutes = newMinutes;
          _estimatedArrival = '${_etaRemainingMinutes!} dk';
        });
      }
    });
  }

  int? _parseMinutes(String? label) {
    if (label == null) {
      debugPrint('⚠️ ETA etiketi null, dakika ayrıştırılamadı');
      return null;
    }

    debugPrint('🔍 ETA etiketi ayrıştırılıyor: "$label"');

    try {
      if (label.endsWith(' dk')) {
        final minutes = int.parse(label.replaceAll(' dk', '').trim());
        debugPrint('✅ Dakika formatı ayrıştırıldı: $minutes dk');
        return minutes;
      }

      if (label.contains('sa')) {
        debugPrint('🕐 Saat formatı ayrıştırılıyor...');
        final parts = label.split(' ');
        int hours = 0;
        int mins = 0;

        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == 'sa') {
            hours = int.tryParse(parts[i - 1]) ?? 0;
            debugPrint('🕐 Saat: $hours');
          } else if (parts[i] == 'dk') {
            mins = int.tryParse(parts[i - 1]) ?? 0;
            debugPrint('⏱️ Dakika: $mins');
          }
        }

        final totalMinutes = hours * 60 + mins;
        debugPrint(
            '✅ Saat formatı ayrıştırıldı: $hours sa $mins dk = $totalMinutes dk');
        return totalMinutes;
      }

      debugPrint('⚠️ Bilinmeyen ETA formatı: "$label"');
      return null;
    } catch (e) {
      debugPrint('❌ ETA etiketi ayrıştırma hatası: $e');
      return null;
    }
  }

  LatLng? _extractLatLng(Map<String, dynamic> data) {
    try {
      // Daha kapsamlı koordinat çıkarma
      final num? latN =
          (data['lat'] ?? data['latitude'] ?? data['latNum']) as num?;
      final num? lngN =
          (data['lng'] ?? data['longitude'] ?? data['lngNum']) as num?;

      if (latN == null || lngN == null) {
        debugPrint('⚠️ Koordinat bulunamadı: lat=$latN, lng=$lngN');
        return null;
      }

      final lat = latN.toDouble();
      final lng = lngN.toDouble();

      // Geçersiz koordinatları filtrele
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) {
        debugPrint('⚠️ Geçersiz koordinat: lat=$lat, lng=$lng');
        return null;
      }

      // Türkiye sınırları içinde mi kontrol et
      if (lat < 35.0 || lat > 43.0 || lng < 25.0 || lng > 45.0) {
        debugPrint('⚠️ Türkiye sınırları dışında: lat=$lat, lng=$lng');
        return null;
      }

      debugPrint('✅ Koordinat çıkarıldı: lat=$lat, lng=$lng');
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint('❌ Koordinat çıkarma hatası: $e');
      return null;
    }
  }

  LatLng? _extractStopLatLng(Map<String, dynamic> data) {
    try {
      // Daha kapsamlı koordinat çıkarma
      final num? latN =
          (data['latitude'] ?? data['lat'] ?? data['latNum']) as num?;
      final num? lngN =
          (data['longitude'] ?? data['lng'] ?? data['lngNum']) as num?;

      if (latN == null || lngN == null) {
        debugPrint(
            '⚠️ Durak koordinatı bulunamadı: ${data['id'] ?? 'bilinmeyen'} - lat=$latN, lng=$lngN');
        return null;
      }

      final lat = latN.toDouble();
      final lng = lngN.toDouble();

      // Geçersiz koordinatları filtrele
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) {
        debugPrint(
            '⚠️ Geçersiz durak koordinatı: ${data['id'] ?? 'bilinmeyen'} - lat=$lat, lng=$lng');
        return null;
      }

      // Türkiye sınırları içinde mi kontrol et
      if (lat < 35.0 || lat > 43.0 || lng < 25.0 || lng > 45.0) {
        debugPrint(
            '⚠️ Türkiye sınırları dışında durak: ${data['id'] ?? 'bilinmeyen'} - lat=$lat, lng=$lng');
        return null;
      }

      debugPrint(
          '✅ Durak koordinatı çıkarıldı: ${data['id'] ?? 'bilinmeyen'} - lat=$lat, lng=$lng');
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint(
          '❌ Durak koordinat çıkarma hatası: ${data['id'] ?? 'bilinmeyen'} - $e');
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
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.percent, color: Colors.purple.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'Tamamlanan: ${(_routeProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _routeProgress,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade600, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Kırmızı: Bekleyen duraklar • Yeşil: Tamamlanan duraklar',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetProgress,
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text('İlerlemeyi Sıfırla'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
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
          _driverStatus = 'Test Modu - Durak Takibi Aktif';
        });
        await _updateDriverMarker(p);

        // Check if driver is near any stops and mark them as completed
        _checkAndMarkStopsAsCompleted(p);

        // Avatar marker cache'ini temizle - test modunda hızlı güncelleme için
        AvatarMarkerService.clearCache();

        _debouncedRouteAndEta();
        idx = (idx + 1) % route.length;
      });
    } else {
      setState(() {
        _driverStatus = _isDriverMoving ? 'Hareket Halinde' : 'Bekliyor';
      });

      // Reset progress when exiting test mode
      if (mounted) {
        setState(() {
          _completedStopsSet.clear();
          _completedStops = 0;
          _routeProgress = 0.0;
        });
        _updateMapWithAllStops();
      }
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
    if (_isDrawingRoute) {
      debugPrint('⚠️ Rota çizimi zaten devam ediyor, atlandı');
      return;
    }

    _isDrawingRoute = true;
    try {
      setState(() {
        _lastRoutePoints = routePoints;
      });
      if (_mapController != null) {
        _drawRouteOnMap(routePoints);
      }
    } finally {
      _isDrawingRoute = false;
    }
  }

  void _checkAndMarkStopsAsCompleted(LatLng driverPosition) {
    if (_allStops.isEmpty) return;

    for (int i = 0; i < _allStops.length; i++) {
      final stop = _allStops[i];
      final stopLatLng = _extractStopLatLng(stop);
      if (stopLatLng == null) continue;

      // Check if driver is within 50 meters of the stop
      final distance = Geolocator.distanceBetween(
        driverPosition.latitude,
        driverPosition.longitude,
        stopLatLng.latitude,
        stopLatLng.longitude,
      );

      // If driver is within 50 meters and stop is not already completed
      if (distance <= 50 && !_completedStopsSet.contains(stop['id'])) {
        setState(() {
          _completedStopsSet.add(stop['id']);
          _completedStops = _completedStopsSet.length;
          _routeProgress =
              _totalStops > 0 ? _completedStops / _totalStops : 0.0;
        });

        // Avatar marker cache'ini temizle ve map'i güncelle
        AvatarMarkerService.clearCache();
        _updateMapWithAllStops();

        // Show notification for completed stop
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Durak tamamlandı: ${stop['name'] ?? 'Durak ${i + 1}'}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _resetProgress() {
    setState(() {
      _completedStopsSet.clear();
      _completedStops = 0;
      _routeProgress = 0.0;
    });

    // Avatar marker cache'ini temizle ve map'i güncelle
    AvatarMarkerService.clearCache();
    _updateMapWithAllStops();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İlerleme sıfırlandı'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _drawRouteOnMap(List<LatLng> routePoints) {
    if (routePoints.length < 2) return;
    if (_isDrawingRoute) {
      debugPrint('⚠️ Rota çizimi zaten devam ediyor, atlandı');
      return;
    }

    _isDrawingRoute = true;
    try {
      _polylines.clear();
      _polylines.add(Polyline(
        polylineId: const PolylineId('test_route'),
        points: routePoints,
        color: Colors.blue,
        width: 4,
        geodesic: true,
      ));
      setState(() {});
    } finally {
      _isDrawingRoute = false;
    }
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

  /// Şoför paneli ile tamamen uyumlu durak optimizasyonu yapar
  /// Unified Route Optimization Service kullanarak tutarlılık sağlar
  Future<List<Map<String, dynamic>>> _optimizeStopsForRoute(
      List<Map<String, dynamic>> stops) async {
    if (stops.isEmpty) return stops;

    try {
      debugPrint(
          '🎯 Unified Route Optimization Service ile durak optimizasyonu başlatılıyor...');

      // Eğer şoför konumu varsa, unified service kullan
      if (_driverLatLng != null && _activeDriverId != null) {
        final driverLocation = {
          'latitude': _driverLatLng!.latitude,
          'longitude': _driverLatLng!.longitude,
        };

        final stopsAsWaypoints = stops
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

        // Cache key oluştur (şoför paneli ile aynı format)
        final cacheKey =
            'driver_${_activeDriverId}_${stops.length}_${_driverLatLng!.latitude.toStringAsFixed(6)}_${_driverLatLng!.longitude.toStringAsFixed(6)}';
        debugPrint('🔑 Cache key: $cacheKey');
        debugPrint(
            '📍 Şoför konumu: ${_driverLatLng!.latitude}, ${_driverLatLng!.longitude}');
        debugPrint(
            '📍 Şoför konumu (6 ondalık): ${_driverLatLng!.latitude.toStringAsFixed(6)}, ${_driverLatLng!.longitude.toStringAsFixed(6)}');
        debugPrint('👤 Driver ID: $_activeDriverId');
        debugPrint('🚌 Durak sayısı: ${stops.length}');

        // Önce cache'den kontrol et
        final cachedRoute =
            UnifiedRouteOptimizationService.getCachedRoute(cacheKey);
        debugPrint(
            '🔍 Cache kontrolü: ${cachedRoute != null ? "BULUNDU" : "BULUNAMADI"}');

        // Cache istatistiklerini kontrol et
        final stats = UnifiedRouteOptimizationService.getCacheStatistics();
        debugPrint(
            '📊 Cache istatistikleri: ${stats['cacheSize']} rota, ${stats['timestampCount']} timestamp');

        if (cachedRoute != null) {
          debugPrint(
              '✅ Cache\'den tutarlı rota alındı: ${cachedRoute.length} durak');

          // Cache'den gelen rotayı orijinal stop verileriyle eşleştir
          final optimizedStops = <Map<String, dynamic>>[];
          for (final cachedStop in cachedRoute) {
            final originalStop = stops.firstWhere(
              (stop) =>
                  (stop['latitude'] ?? stop['lat'])?.toDouble() ==
                      cachedStop['latitude'] &&
                  (stop['longitude'] ?? stop['lng'])?.toDouble() ==
                      cachedStop['longitude'],
              orElse: () => stops.first,
            );
            optimizedStops.add({
              ...originalStop,
              'order': cachedStop['order'],
            });
          }

          debugPrint(
              '🎯 Cache\'den ${optimizedStops.length} durak başarıyla alındı');
          return optimizedStops;
        }

        // Cache'de yoksa, getOrCreateCachedRoute kullanarak yeni rota oluştur
        debugPrint('⚠️ Cache\'de rota bulunamadı, yeni rota oluşturuluyor...');

        try {
          final optimizedWaypoints =
              await UnifiedRouteOptimizationService.getOrCreateCachedRoute(
            cacheKey: cacheKey,
            driverLocation: driverLocation,
            stops: stopsAsWaypoints,
            useGoogleApi: true,
          );

          if (optimizedWaypoints.isNotEmpty) {
            debugPrint(
                '✅ Yeni rota oluşturuldu ve cache\'lendi: ${optimizedWaypoints.length} durak');

            // Waypoint'leri orijinal stop verileriyle eşleştir
            final optimizedStops = <Map<String, dynamic>>[];
            for (final waypoint in optimizedWaypoints) {
              final originalStop = stops.firstWhere(
                (stop) =>
                    (stop['latitude'] ?? stop['lat'])?.toDouble() ==
                        waypoint['latitude'] &&
                    (stop['longitude'] ?? stop['lng'])?.toDouble() ==
                        waypoint['longitude'],
                orElse: () => stops.first,
              );
              optimizedStops.add({
                ...originalStop,
                'order': waypoint['order'],
              });
            }

            debugPrint(
                '🎯 Yeni rota ile ${optimizedStops.length} durak optimize edildi');
            return optimizedStops;
          }
        } catch (e) {
          debugPrint('❌ Yeni rota oluşturma hatası: $e');
        }

        debugPrint(
            '⚠️ Cache\'de rota bulunamadı, şoför paneli ile uyumlu sıralama yapılıyor...');
      }

      // Cache'de yoksa, şoför paneli ile aynı sıralamayı kullan
      // Şoför paneli zaten optimize etmiş olmalı, bu yüzden order'a göre sırala
      final sortedStops = List<Map<String, dynamic>>.from(stops);
      sortedStops.sort((a, b) {
        final int ai = (a['order'] ?? 0) as int;
        final int bi = (b['order'] ?? 0) as int;
        return ai.compareTo(bi);
      });

      // Order yoksa, şoför konumuna göre mesafe bazlı sıralama yap
      if (sortedStops.every((s) => (s['order'] ?? 0) == 0) &&
          _driverLatLng != null) {
        debugPrint(
            '📍 Order yok, şoför konumuna göre mesafe bazlı sıralama yapılıyor...');
        sortedStops.sort((a, b) {
          final aLat = (a['latitude'] ?? a['lat'])?.toDouble();
          final aLng = (a['longitude'] ?? a['lng'])?.toDouble();
          final bLat = (b['latitude'] ?? b['lat'])?.toDouble();
          final bLng = (b['longitude'] ?? b['lng'])?.toDouble();

          if (aLat == null || aLng == null || bLat == null || bLng == null)
            return 0;

          final aDistance = Geolocator.distanceBetween(
            _driverLatLng!.latitude,
            _driverLatLng!.longitude,
            aLat,
            aLng,
          );
          final bDistance = Geolocator.distanceBetween(
            _driverLatLng!.latitude,
            _driverLatLng!.longitude,
            bLat,
            bLng,
          );

          return aDistance.compareTo(bDistance);
        });
      }

      // Şoför paneli ile uyumlu maksimum waypoint sayısı
      const int maxWaypoints = 20;
      if (sortedStops.length > maxWaypoints) {
        debugPrint(
            '⚠️ Durak sayısı $maxWaypoints\'i aşıyor, şoför paneli ile uyumlu olarak ilk $maxWaypoints durak alınıyor');
        sortedStops.removeRange(maxWaypoints, sortedStops.length);
      }

      debugPrint(
          '✅ ${sortedStops.length} durak şoför paneli ile uyumlu olarak optimize edildi');
      return sortedStops;
    } catch (e) {
      debugPrint('❌ Şoför paneli ile uyumlu durak optimizasyon hatası: $e');
      return stops; // Hata durumunda orijinal listeyi döndür
    }
  }
}
