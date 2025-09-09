import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../service/simple_stop_service.dart';
import '../service/user_session.dart';
import '../service/route_service.dart';
import '../service/route_optimization_service.dart';
import '../service/geocoding_service.dart';
import '../models/stop_model.dart';
import 'package:url_launcher/url_launcher.dart';

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key});
  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  List<Map<String, dynamic>> _stops = [];
  bool _isLoading = true;
  bool _isOptimizing = false;
  bool _isRouteActive = false;
  GoogleMapController? _mapController;
  Position? _currentLocation;
  String? _currentRouteId;
  String? _currentRouteLogId;
  Set<Polyline> _polylines = {};
  static const String _googleApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ',
  );
  late PolylinePoints _polylinePoints;
  final RouteOptimizationService _routeService = RouteOptimizationService();
  final RouteService _routeServiceManager = RouteService();
  @override
  void initState() {
    super.initState();
    _polylinePoints = PolylinePoints(apiKey: _googleApiKey);
    _loadStops();
    _getLocation();
    _startLocationTracking();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    print('🗺️ Harita oluşturuldu');
    if (_stops.isNotEmpty && !_isRouteActive && _currentLocation != null) {
      print('🚀 Harita hazır, rota çizimi başlatılıyor...');
      _drawRoute();
    }
  }

  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _currentLocation = position;
      });
      if (_isRouteActive && _currentRouteId != null) {
        _checkStopArrival();
      }
    });
  }

  Future<void> _loadStops() async {
    setState(() => _isLoading = true);
    try {
      print('Duraklar yükleniyor. Şoför ID: ${UserSession.userId}');
      final stops =
          await SimpleStopService.getStopsForDriver(UserSession.userId!);
      print('Yüklenen durak sayısı: ${stops.length}');
      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i];
        final distance =
            stop['distanceFromDriver']?.toStringAsFixed(0) ?? 'Bilinmiyor';
        print(
            '${i + 1}. Durak: ${stop['id']}, Mesafe: ${distance}m, Yolcu: ${stop['assignedPassengerCount']}');
      }
      if (mounted) {
        setState(() {
          _stops = stops;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fitMapToStops();
        });
        if (!_isRouteActive &&
            _stops.isNotEmpty &&
            _mapController != null &&
            _currentLocation != null) {
          print('🚀 Duraklar yüklendi, rota çizimi başlatılıyor...');
          _drawRoute();
        }
      }
    } catch (e) {
      print('Durak yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duraklar yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  void _fitMapToStops() {
    if (_stops.isEmpty || _mapController == null) return;
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    if (_currentLocation != null) {
      minLat = math.min(minLat, _currentLocation!.latitude);
      maxLat = math.max(maxLat, _currentLocation!.latitude);
      minLng = math.min(minLng, _currentLocation!.longitude);
      maxLng = math.max(maxLng, _currentLocation!.longitude);
    }
    for (final stop in _stops) {
      final lat = stop['latitude'] as double?;
      final lng = stop['longitude'] as double?;
      if (lat != null && lng != null) {
        minLat = math.min(minLat, lat);
        maxLat = math.max(maxLat, lat);
        minLng = math.min(minLng, lng);
        maxLng = math.max(maxLng, lng);
      }
    }
    if (minLat != double.infinity) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          100.0,
        ),
      );
    }
  }

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = position;
      });
      if (_stops.isNotEmpty && !_isRouteActive) {
        await _drawRoute();
      }
    } catch (e) {
      print('Konum alma hatası: $e');
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    print(
        'Durak markerları oluşturuluyor. Toplam durak sayısı: ${_stops.length}');
    for (final stop in _stops) {
      final latitude = stop['latitude'] as double?;
      final longitude = stop['longitude'] as double?;
      final stopId = stop['id'] ?? 'unknown';
      print('Durak işleniyor: $stopId, lat: $latitude, lng: $longitude');
      if (latitude != null && longitude != null) {
        final marker = Marker(
          markerId: MarkerId(stopId),
          position: LatLng(latitude, longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: stop['name'] ?? stop['address'] ?? 'Durak',
            snippet:
                '${stop['assignedPassengerCount'] ?? stop['passengerCount'] ?? 0} yolcu',
          ),
        );
        markers.add(marker);
        print('Durak markeri eklendi: $stopId');
      } else {
        print('Durak koordinatları eksik: $stopId');
      }
    }
    if (_currentLocation != null) {
      final driverMarker = Marker(
        markerId: const MarkerId('driver_location'),
        position: LatLng(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: 'Şoför Konumu',
          snippet: 'Plaka: ${UserSession.vehiclePlate ?? "Bilinmiyor"}',
        ),
      );
      markers.add(driverMarker);
      print('Şoför markeri eklendi');
    }
    print('Toplam marker sayısı: ${markers.length}');
    return markers;
  }

  Future<void> _optimizeRoute() async {
    if (_currentLocation == null || _stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum veya durak bilgisi bulunamadı')),
      );
      return;
    }
    setState(() {
      _isOptimizing = true;
    });
    try {
      final stopModels = _stops
          .map((stop) => StopModel(
                id: stop['id'],
                driverId: UserSession.userId!,
                passengerName: stop['name'] ?? 'Durak',
                address: stop['address'] ?? '',
                lat: stop['latitude'] ?? 0.0,
                lng: stop['longitude'] ?? 0.0,
                date: DateTime.now(),
                order: 0,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                passengerIds:
                    List<String>.from(stop['assignedPassengerIds'] ?? []),
              ))
          .toList();
      final routeData = await _routeService.optimizeRouteWithFirebase(
        _currentLocation!,
        stopModels,
      );
      if (routeData != null) {
        setState(() {
          _currentRouteId = routeData['routeId'];
          _isRouteActive = true;
        });
        await _drawRoute();
        if (routeData['overview_polyline'] != null) {
          await _drawRoutePolyline(routeData['overview_polyline']);
        }
        _currentRouteLogId = await _routeServiceManager.createRouteLog(
          routeId: _currentRouteId!,
          driverId: UserSession.userId!,
          startLocation: _currentLocation!,
          plannedStops: stopModels,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rota optimize edildi ve çizildi!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rota optimizasyonu başarısız')),
        );
      }
    } catch (e) {
      print('Rota optimizasyon hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      setState(() {
        _isOptimizing = false;
      });
    }
  }

  Future<void> _drawRoute() async {
    if (_currentLocation == null || _stops.isEmpty) {
      print('⚠️ Rota çizilemez: Konum veya duraklar eksik');
      return;
    }
    if (_mapController == null) {
      print('⏳ Harita henüz hazır değil, rota çizimi erteleniyor...');
      return;
    }
    if (_googleApiKey.isEmpty) {
      print('❌ Google API key bulunamadı');
      _showErrorSnackBar('Google API anahtarı eksik');
      return;
    }
    try {
      print('🚀 Rota çizimi başlatılıyor...');
      final origin =
          PointLatLng(_currentLocation!.latitude, _currentLocation!.longitude);
      final lastStop = _stops.last;
      final destination =
          PointLatLng(lastStop['latitude'], lastStop['longitude']);
      List<PolylineWayPoint> waypoints = [];
      if (_stops.length > 1) {
        final waypointStops = _stops.take(_stops.length - 1).toList();
        if (waypointStops.length > 23) {
          print(
              '⚠️ Waypoint sayısı limiti aşıldı (${waypointStops.length}/23), ilk 23 durak kullanılacak');
          _showErrorSnackBar('Çok fazla durak var, ilk 23 durak kullanılacak');
          waypointStops.removeRange(23, waypointStops.length);
        }
        for (final stop in waypointStops) {
          waypoints.add(PolylineWayPoint(
              location: '${stop['latitude']},${stop['longitude']}'));
        }
      }
      print('📍 Origin: ${origin.latitude}, ${origin.longitude}');
      print(
          '📍 Destination: ${destination.latitude}, ${destination.longitude}');
      print('📍 Waypoints: ${waypoints.length}');
      PolylineRequest request = PolylineRequest(
        origin: origin,
        destination: destination,
        mode: TravelMode.driving,
        wayPoints: waypoints,
      );
      print('📡 Google Directions API çağrısı yapılıyor...');
      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        request: request,
      );
      print('📡 API yanıtı alındı. Status: ${result.status}');
      if (result.points.isNotEmpty) {
        final polylinePoints = result.points
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylinePoints,
              color: Colors.blue,
              width: 5,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          };
        });
        print('✅ Rota başarıyla çizildi! ${polylinePoints.length} nokta');
        _fitMapToRoute(polylinePoints);
      } else {
        String errorMsg = 'Bilinmeyen hata';
        if (result.errorMessage?.isNotEmpty == true) {
          errorMsg = result.errorMessage!;
          print('❌ API Hatası: ${result.errorMessage}');
        }
        if (result.status?.isNotEmpty == true) {
          print('❌ API Durumu: ${result.status}');
        }
        print('❌ Polyline result boş ($errorMsg)');
        _showErrorSnackBar('Rota bilgisi alınamadı, basit rota çiziliyor');
        await _drawSimpleRoute();
      }
    } catch (e) {
      print('❌ Rota çizim hatası: $e');
      _showErrorSnackBar('Rota çiziminde hata oluştu');
      await _drawSimpleRoute();
    }
  }

  Future<void> _drawSimpleRoute() async {
    if (_currentLocation == null || _stops.isEmpty) return;
    try {
      print('🔄 Basit rota çizimi başlatılıyor...');
      List<LatLng> routePoints = [];
      routePoints
          .add(LatLng(_currentLocation!.latitude, _currentLocation!.longitude));
      for (final stop in _stops) {
        final lat = stop['latitude'] as double?;
        final lng = stop['longitude'] as double?;
        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          routePoints.add(LatLng(lat, lng));
        }
      }
      if (routePoints.length >= 2) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('simple_route'),
              points: routePoints,
              color: Colors.red,
              width: 3,
              patterns: [PatternItem.dash(15), PatternItem.gap(10)],
            ),
          };
        });
        print('✅ Basit rota çizildi! ${routePoints.length} nokta');
        _fitMapToRoute(routePoints);
      }
    } catch (e) {
      print('❌ Basit rota çizim hatası: $e');
    }
  }

  void _fitMapToRoute(List<LatLng> routePoints) {
    if (_mapController == null || routePoints.isEmpty) {
      print('⚠️ Harita kontrolcüsü veya rota noktaları eksik');
      return;
    }
    try {
      final lats = routePoints.map((p) => p.latitude);
      final lngs = routePoints.map((p) => p.longitude);
      final bounds = LatLngBounds(
        southwest: LatLng(
          lats.reduce(math.min),
          lngs.reduce(math.min),
        ),
        northeast: LatLng(
          lats.reduce(math.max),
          lngs.reduce(math.max),
        ),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 120),
      );
      print('🎯 Harita rotaya odaklandı');
    } catch (e) {
      print('❌ Harita odaklama hatası: $e');
    }
  }

  Future<void> _drawRoutePolyline(String encodedPolyline) async {
    try {
      final points = _routeService.decodePolyline(encodedPolyline);
      final polylinePoints = points
          .map((point) => LatLng(
                point['latitude']!,
                point['longitude']!,
              ))
          .toList();
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: polylinePoints,
            color: Colors.blue,
            width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        };
      });
    } catch (e) {
      print('Polyline çizim hatası: $e');
    }
  }

  Future<void> _clearRoute() async {
    setState(() {
      _polylines.clear();
      _isRouteActive = false;
      _currentRouteId = null;
    });
    if (_currentRouteLogId != null && _currentLocation != null) {
      await _routeServiceManager.completeRoute(
        routeId: _currentRouteId!,
        endLocation: _currentLocation!,
      );
      _currentRouteLogId = null;
    }
  }

  Future<void> _checkStopArrival() async {
    if (!_isRouteActive ||
        _currentLocation == null ||
        _currentRouteId == null) {
      return;
    }
    final stopModels = _stops
        .map((stop) => StopModel(
              id: stop['id'],
              driverId: UserSession.userId!,
              passengerName: stop['name'] ?? 'Durak',
              address: stop['address'] ?? '',
              lat: stop['latitude'] ?? 0.0,
              lng: stop['longitude'] ?? 0.0,
              date: DateTime.now(),
              order: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              passengerIds:
                  List<String>.from(stop['assignedPassengerIds'] ?? []),
            ))
        .toList();
    final nearestStop = _findNearestStop(_currentLocation!, stopModels);
    if (nearestStop != null) {
      final success = await _routeServiceManager.completeStop(
        routeId: _currentRouteId!,
        stopId: nearestStop.id,
        completedAt: DateTime.now(),
      );
      if (success) {
        setState(() {
          _stops.removeWhere((stop) => stop['id'] == nearestStop.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${nearestStop.address} durağı tamamlandı! Sıradaki durağa geçiliyor...')),
        );
        if (_stops.isNotEmpty) {
          await _optimizeRoute();
        } else {
          await _completeRoute();
        }
      }
    }
  }

  StopModel? _findNearestStop(Position currentPosition, List<StopModel> stops) {
    if (stops.isEmpty) return null;
    double minDistance = double.infinity;
    StopModel? nearestStop;
    for (final stop in stops) {
      final distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        stop.lat,
        stop.lng,
      );
      if (distance <= 100 && distance < minDistance) {
        minDistance = distance;
        nearestStop = stop;
      }
    }
    return nearestStop;
  }

  Future<void> _completeRoute() async {
    if (_currentRouteId != null && _currentLocation != null) {
      await _routeServiceManager.completeRoute(
        routeId: _currentRouteId!,
        endLocation: _currentLocation!,
      );
      setState(() {
        _isRouteActive = false;
        _currentRouteId = null;
        _polylines.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('🎉 Tüm duraklar tamamlandı! Rota başarıyla bitirildi.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _completeStopManually(String stopId) async {
    if (!_isRouteActive || _currentRouteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktif rota bulunamadı!')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Durağı Tamamla'),
        content: const Text(
            'Bu durağı tamamlandı olarak işaretlemek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Tamamla'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await _routeServiceManager.completeStop(
        routeId: _currentRouteId!,
        stopId: stopId,
        completedAt: DateTime.now(),
      );
      if (success) {
        final completedStop = _stops.firstWhere((stop) => stop['id'] == stopId);
        setState(() {
          _stops.removeWhere((stop) => stop['id'] == stopId);
        });
        print('🎯 Durak tamamlandı: ${completedStop['address'] ?? 'Durak'}');
        print('📍 Kalan durak sayısı: ${_stops.length}');
        if (_stops.isNotEmpty) {
          await _navigateToNextStop();
        } else {
          await _completeRoute();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Durak tamamlanırken hata oluştu!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _navigateToNextStop() async {
    if (_stops.isEmpty || _currentLocation == null) return;
    try {
      final nextStop = _stops.first;
      final stopName =
          nextStop['address'] ?? nextStop['name'] ?? 'Sıradaki Durak';
      final passengerCount = nextStop['assignedPassengerCount'] ?? 0;
      print('🚗 Sıradaki durağa yönlendiriliyor: $stopName');
      final driverLocation = {
        'latitude': _currentLocation!.latitude,
        'longitude': _currentLocation!.longitude,
      };
      final waypointStops = _stops
          .map((stop) => {
                'latitude': stop['latitude'] as double,
                'longitude': stop['longitude'] as double,
                'name': stop['name'] ?? 'Durak',
              })
          .toList();
      final navigationUrl = GeocodingService.generateNavigationUrl(
        origin: driverLocation,
        waypoints: waypointStops,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎯 Sıradaki durak: $stopName ($passengerCount yolcu)\n'
            '🚗 Waypoints rotası hazırlandı!',
          ),
          backgroundColor: Colors.blue.shade600,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Navigasyonu Başlat',
            textColor: Colors.white,
            onPressed: () {
              _launchWaypointsNavigation(navigationUrl);
            },
          ),
        ),
      );
      await _optimizeRoute();
      _focusOnNextStop();
    } catch (e) {
      print('❌ Sıradaki durağa yönlendirme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sıradaki durağa yönlendirme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _launchWaypointsNavigation(String navigationUrl) async {
    try {
      final uri = Uri.parse(navigationUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('🗺️ Waypoints navigasyonu başlatıldı: $navigationUrl');
      } else {
        throw 'Navigasyon uygulaması açılamadı';
      }
    } catch (e) {
      print('❌ Navigasyon başlatma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigasyon başlatılamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToSingleStop(Map<String, dynamic> stop) async {
    try {
      final double lat = stop['latitude']?.toDouble() ?? 0.0;
      final double lng = stop['longitude']?.toDouble() ?? 0.0;
      if (lat == 0.0 || lng == 0.0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Durak koordinatları bulunamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final String googleMapsUrl =
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
      final Uri uri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${stop['name']} durağına navigasyon başlatıldı'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google Maps açılamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigasyon hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _focusOnNextStop() {
    if (_stops.isEmpty || _mapController == null) return;
    final nextStop = _stops.first;
    final lat = nextStop['latitude'] as double?;
    final lng = nextStop['longitude'] as double?;
    if (lat != null && lng != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: 16.0,
          ),
        ),
      );
      print('🎯 Harita sıradaki durağa odaklandı: $lat, $lng');
    }
  }

  Widget _buildStopCard(Map<String, dynamic> stop) {
    final passengerCount = stop['assignedPassengerCount'] ?? 0;
    final passengerNames =
        List<String>.from(stop['assignedPassengerNames'] ?? []);
    final addresses = List<String>.from(stop['assignedAddresses'] ?? []);
    final distance = stop['distanceFromDriver']?.toDouble();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: Colors.green.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop['name'] ?? 'Durak',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (stop['address'] != null)
                        Text(
                          stop['address'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$passengerCount yolcu',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (distance != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${distance.toStringAsFixed(1)} km',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    if (_isRouteActive) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _navigateToSingleStop(stop),
                        icon: const Icon(Icons.navigation, size: 16),
                        label: const Text('Navigasyon',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _completeStopManually(stop['id']),
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: const Text('Tamamla',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (passengerCount > 0) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.people, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Bu Durağı Kullanan Yolcular:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(passengerNames.length, (index) {
                final name = passengerNames[index];
                final address =
                    index < addresses.length ? addresses[index] : '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'Y',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (address.isNotEmpty)
                              Text(
                                address,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    Icons.access_time,
                    'Oluşturulma',
                    _formatDate(stop['createdAt']),
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    Icons.update,
                    'Güncelleme',
                    _formatDate(stop['lastUpdated']),
                    Colors.indigo,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Bilinmiyor';
    try {
      DateTime date;
      if (timestamp is DateTime) {
        date = timestamp;
      } else {
        date = timestamp.toDate();
      }
      return DateFormat('dd.MM.yyyy HH:mm').format(date);
    } catch (e) {
      return 'Bilinmiyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Duraklar'),
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        actions: [
          if (!_isRouteActive)
            IconButton(
              icon: _isOptimizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.route),
              onPressed: _isOptimizing ? null : _optimizeRoute,
              tooltip: 'Rota Oluştur',
            ),
          if (_isRouteActive)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearRoute,
              tooltip: 'Rotayı Temizle',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStops,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Duraklar yükleniyor...'),
                ],
              ),
            )
          : _stops.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz durak bulunmuyor',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Yolcular adres ekledikçe duraklar otomatik oluşturulacak',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      height: 250,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _currentLocation != null
                                ? LatLng(
                                    _currentLocation!.latitude,
                                    _currentLocation!.longitude,
                                  )
                                : _stops.isNotEmpty
                                    ? LatLng(
                                        _stops.first['latitude'] ?? 0.0,
                                        _stops.first['longitude'] ?? 0.0,
                                      )
                                    : const LatLng(39.9334, 32.8597),
                            zoom: 13,
                          ),
                          markers: _buildMarkers(),
                          polylines: _polylines,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          onMapCreated: _onMapCreated,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.green.shade600),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Toplam ${_stops.length} durak bulundu. Size atanmış yolcuların durakları gösteriliyor.',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _stops.length,
                        itemBuilder: (context, index) {
                          return _buildStopCard(_stops[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}



 Again


