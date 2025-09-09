import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../service/user_session.dart';
import '../service/location_service.dart';
import '../service/background_location_service.dart';
import '../service/simple_stop_service.dart';
class LiveTrackingScreen extends StatefulWidget {
  final String? driverId;
  const LiveTrackingScreen({super.key, this.driverId});
  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}
class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isTracking = false;
  bool _isLoading = false;
  Position? _currentPosition;
  String? _regionName;
  int _passengerCount = 0;
  bool _showRoute = true;
  List<LatLng> _passengerStops = [];
  @override
  void initState() {
    super.initState();
    _initializeBackgroundService();
    _loadInitialData();
    _checkTrackingStatus();
  }
  Future<void> _initializeBackgroundService() async {
    await BackgroundLocationService.initializeService();
  }
  Future<void> _checkTrackingStatus() async {
    setState(() {
      _isTracking = UserSession.isLocationSharing;
    });
    print('Live tracking ekranı konum durumu: $_isTracking');
  }
  Future<void> _toggleLocationSharing() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    try {
      print('Konum paylaşımı değiştiriliyor. Mevcut durum: $_isTracking');
      if (_isTracking) {
        print('Konum paylaşımı durduruluyor...');
        await _stopTracking();
      } else {
        print('Konum paylaşımı başlatılıyor...');
        await _startTracking();
      }
    } catch (e) {
      print('Konum paylaşımı değiştirme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _loadRegionInfo();
      await _getCurrentLocation();
      await _loadPassengerStops();
      _listenToLocationUpdates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yüklenirken hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  Future<void> _loadRegionInfo() async {
    if (UserSession.regionId != null) {
      final regionDoc = await FirebaseFirestore.instance
          .collection('regions')
          .doc(UserSession.regionId)
          .get();
      if (regionDoc.exists && mounted) {
        setState(() {
          _regionName = regionDoc.data()?['name'] ?? 'Bilinmeyen Bölge';
        });
      }
    }
  }
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _updateDriverMarker(position);
        _moveCamera(LatLng(position.latitude, position.longitude));
      }
    } catch (e) {
      print('Konum alınırken hata: $e');
    }
  }
  Future<void> _loadPassengerStops() async {
    try {
      print(
          'Yolcu durakları yükleniyor. Şoför ID: ${widget.driverId ?? FirebaseAuth.instance.currentUser!.uid}');
      final stops = await SimpleStopService.getStopsForDriver(
          widget.driverId ?? FirebaseAuth.instance.currentUser!.uid);
      print('Bulunan durak sayısı: ${stops.length}');
      final markers = <Marker>{};
      final stopLocations = <LatLng>[];
      int count = 0;
      for (final stop in stops) {
        final lat = stop['latitude']?.toDouble();
        final lng = stop['longitude']?.toDouble();
        if (lat != null && lng != null) {
          count++;
          final stopLocation = LatLng(lat, lng);
          stopLocations.add(stopLocation);
          final marker = Marker(
            markerId: MarkerId('stop_${stop['id']}'),
            position: stopLocation,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: stop['name'] ?? stop['address'] ?? 'Durak',
              snippet:
                  '${stop['assignedPassengerCount'] ?? stop['passengerCount'] ?? 0} yolcu',
            ),
          );
          markers.add(marker);
          print('Durak markeri eklendi: ${stop['id']}, Lat: $lat, Lng: $lng');
        } else {
          print('Durak koordinatları eksik: ${stop['id']}');
        }
      }
      if (mounted) {
        setState(() {
          _markers.addAll(markers);
          _passengerCount = count;
          _passengerStops = stopLocations;
        });
        print('Toplam marker sayısı: ${_markers.length}, Yolcu sayısı: $count');
        if (_showRoute &&
            _currentPosition != null &&
            stopLocations.isNotEmpty) {
          _drawRouteToStops();
        }
      }
    } catch (e) {
      print('Yolcu durakları yüklenirken hata: $e');
    }
  }
  void _updateDriverMarker(Position position) {
    final driverMarker = Marker(
      markerId: const MarkerId('driver'),
      position: LatLng(position.latitude, position.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: InfoWindow(
        title: 'Şoför Konumu',
        snippet: 'Plaka: ${UserSession.vehiclePlate ?? "Bilinmiyor"}',
      ),
    );
    setState(() {
      _currentPosition = position;
      _markers.removeWhere((marker) => marker.markerId.value == 'driver');
      _markers.add(driverMarker);
    });
    if (_showRoute && _passengerStops.isNotEmpty) {
      _drawRouteToStops();
    }
  }
  void _listenToLocationUpdates() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (mounted && _isTracking) {
        setState(() {
          _currentPosition = position;
        });
        _updateDriverMarker(position);
        _updateLocationInFirestore(position);
      }
    });
  }
  Future<void> _updateLocationInFirestore(Position position) async {
    try {
      final driverId =
          widget.driverId ?? FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .set({
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'driverId': driverId,
        'regionId': UserSession.regionId,
        'vehiclePlate': UserSession.vehiclePlate,
        'isActive': _isTracking,
      });
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .update({
        'currentLat': position.latitude,
        'currentLng': position.longitude,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Konum güncellenirken hata: $e');
    }
  }
  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _stopTracking();
    } else {
      await _startTracking();
    }
  }
  Future<void> _startTracking() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await LocationService().requestAndShareLocation();
      if (_currentPosition != null) {
        await _updateLocationInFirestore(_currentPosition!);
      }
      setState(() {
        _isTracking = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konum paylaşımı başlatıldı!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum paylaşımı başlatılırken hata: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _stopTracking() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final driverId =
          widget.driverId ?? FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .update({
        'isActive': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      setState(() {
        _isTracking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konum paylaşımı durduruldu!'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum paylaşımı durdurulurken hata: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  void _moveCamera(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: 15.0,
        ),
      ),
    );
  }
  Future<void> _drawRouteToStops() async {
    if (_currentPosition == null || _passengerStops.isEmpty) return;
    try {
      final currentLocation =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      LatLng? nearestStop;
      double minDistance = double.infinity;
      for (final stop in _passengerStops) {
        final distance = _calculateDistance(currentLocation, stop);
        if (distance < minDistance) {
          minDistance = distance;
          nearestStop = stop;
        }
      }
      if (nearestStop != null) {
        await _drawRoute(currentLocation, nearestStop);
      }
    } catch (e) {
      print('Rota çizimi hatası: $e');
    }
  }
  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }
  Future<void> _drawRoute(LatLng start, LatLng end) async {
    try {
      const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ',
  );
      final String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&key=$apiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']['points'];
          final decodedPoints = _decodePolyline(polylinePoints);
          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: decodedPoints,
                color: Colors.red,
                width: 4,
                patterns: [],
              ),
            );
          });
        }
      }
    } catch (e) {
      print('Rota çizimi hatası: $e');
      _drawSimpleRoute(start, end);
    }
  }
  void _drawSimpleRoute(LatLng start, LatLng end) {
    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('simple_route'),
          points: [start, end],
          color: Colors.red,
          width: 3,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );
    });
  }
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polylineCoordinates = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;
    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      polylineCoordinates.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polylineCoordinates;
  }
  void _toggleRoute() {
    setState(() {
      _showRoute = !_showRoute;
      if (!_showRoute) {
        _polylines.clear();
      } else if (_currentPosition != null && _passengerStops.isNotEmpty) {
        _drawRouteToStops();
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_regionName ?? 'Harita'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _showRoute ? Icons.route : Icons.route_outlined,
              color: _showRoute ? Colors.red : Colors.white,
            ),
            onPressed: _toggleRoute,
            tooltip: _showRoute ? 'Rotayı Gizle' : 'Rotayı Göster',
          ),
          IconButton(
            icon: Icon(_isTracking ? Icons.location_off : Icons.location_on),
            onPressed: _toggleLocationSharing,
            tooltip: _isTracking
                ? 'Konum Paylaşımını Durdur'
                : 'Konum Paylaşımını Başlat',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isTracking
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isTracking ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isTracking ? Icons.location_on : Icons.location_off,
                        color: _isTracking ? Colors.green : Colors.orange,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isTracking
                                  ? 'Konum Paylaşımı Aktif'
                                  : 'Konum Paylaşımı Pasif',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isTracking
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                            Text(
                              _isTracking
                                  ? 'Konumunuz arka planda paylaşılıyor'
                                  : 'Konum paylaşımını başlatın',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard('Yolcu Sayısı', _passengerCount.toString(),
                          Icons.people),
                      _buildStatCard(
                          'Bölge', _regionName ?? '-', Icons.location_city),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GoogleMap(
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                        },
                        initialCameraPosition: CameraPosition(
                          target: _currentPosition != null
                              ? LatLng(_currentPosition!.latitude,
                                  _currentPosition!.longitude)
                              : const LatLng(41.0082, 28.9784),
                          zoom: 14,
                        ),
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        mapType: MapType.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleLocationSharing,
        backgroundColor: _isTracking ? Colors.red : Colors.green,
        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(_isTracking ? 'Durdur' : 'Başlat'),
      ),
    );
  }
  Widget _buildStatCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade600, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

// Updated


// Updated Again


