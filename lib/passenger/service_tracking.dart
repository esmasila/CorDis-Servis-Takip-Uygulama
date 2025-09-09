import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
class ServiceTracking extends StatefulWidget {
  const ServiceTracking({super.key});
  @override
  State<ServiceTracking> createState() => _ServiceTrackingState();
}
class _ServiceTrackingState extends State<ServiceTracking> {
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;
  String? etaText;
  String? _driverId;
  String? _regionId;
  LatLng? _initialPosition;
  LatLng? _userCurrentLocation;
  LatLng? _driverCurrentLocation;
  bool _isLoading = true;
  String? _driverName;
  String? _vehiclePlate;
  bool _showRoute = false;
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadPassengerData();
  }
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Konum servisleri kapalı');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Konum izni reddedildi');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('Konum izni kalıcı olarak reddedildi');
        return;
      }
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _userCurrentLocation = LatLng(position.latitude, position.longitude);
        _initialPosition = _userCurrentLocation;
      });
      _updateUserLocationMarker();
      print(
          'Kullanıcı konumu alındı: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Konum alma hatası: $e');
    }
  }
  void _updateUserLocationMarker() {
    if (_userCurrentLocation != null) {
      _markers
          .removeWhere((marker) => marker.markerId.value == 'user_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: _userCurrentLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Benim Konumum',
            snippet: 'Mevcut konumunuz',
          ),
        ),
      );
    }
  }
  Future<void> _loadPassengerData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      print('Yolcu verisi yükleniyor...');
      final passengerDoc = await FirebaseFirestore.instance
          .collection('passengers')
          .doc(user.uid)
          .get();
      if (passengerDoc.exists) {
        final passengerData = passengerDoc.data()!;
        _driverId = passengerData['driverId'];
        _regionId = passengerData['regionId'];
        print('Yolcu verisi: driverId=$_driverId, regionId=$_regionId');
        if (_driverId != null) {
          await _loadDriverInfo();
          _listenToDriverLocation();
          if (_regionId != null) {
            await _loadRegionCenter();
          }
        } else {
          setState(() {
            etaText = 'Size henüz şoför atanmamış';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          etaText = 'Şoför bilgileri yükleniyor...';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Yolcu verisi yükleme hatası: $e');
      setState(() {
        etaText = 'Veri yükleme hatası: $e';
        _isLoading = false;
      });
    }
  }
  Future<void> _loadDriverInfo() async {
    try {
      if (_driverId == null) return;
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId!)
          .get();
      if (driverDoc.exists) {
        final driverData = driverDoc.data()!;
        setState(() {
          _driverName = driverData['name'] ?? 'Bilinmeyen Şoför';
          _vehiclePlate = driverData['vehiclePlate'] ?? 'Bilinmeyen Plaka';
        });
      }
    } catch (e) {
      print('Şoför bilgisi yükleme hatası: $e');
    }
  }
  Future<void> _loadRegionCenter() async {
    try {
      if (_regionId == null) return;
      final regionDoc = await FirebaseFirestore.instance
          .collection('regions')
          .doc(_regionId!)
          .get();
      if (regionDoc.exists) {
        final regionData = regionDoc.data()!;
        final lat = regionData['centerLat']?.toDouble();
        final lng = regionData['centerLng']?.toDouble();
        if (lat != null && lng != null) {
          if (_userCurrentLocation == null) {
            setState(() {
              _initialPosition = LatLng(lat, lng);
            });
          }
          if (_mapController != null) {
            final targetLocation = _userCurrentLocation ?? LatLng(lat, lng);
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(targetLocation, 15),
            );
          }
        }
      }
    } catch (e) {
      print('Bölge merkezi yükleme hatası: $e');
    }
  }
  void _listenToDriverLocation() {
    if (_driverId == null) return;
    print('Şoför konumu dinleniyor: $_driverId');
    FirebaseFirestore.instance
        .collection('live_locations')
        .doc(_driverId)
        .snapshots()
        .listen((doc) {
      print('Şoför konum verisi alındı: ${doc.exists}');
      if (!doc.exists) {
        setState(() {
          etaText = _driverName != null
              ? '$_driverName şoförünün konumu bulunamadı'
              : 'Şoför konumu bulunamadı';
          _isLoading = false;
        });
        return;
      }
      final data = doc.data()!;
      final lat = (data['lat'] ?? 0).toDouble();
      final lng = (data['lng'] ?? 0).toDouble();
      final vehiclePlate =
          data['vehiclePlate'] ?? _vehiclePlate ?? 'Bilinmeyen Plaka';
      final isActive = data['isActive'] ?? false;
      print(
          'Şoför konumu: lat=$lat, lng=$lng, plaka=$vehiclePlate, aktif=$isActive');
      setState(() {
        _isLoading = false;
        if (isActive) {
          etaText = _driverName != null
              ? '$_driverName şoförü ($vehiclePlate) aktif'
              : '$vehiclePlate plakalı servis aktif';
          _driverCurrentLocation = LatLng(lat, lng);
          _markers.removeWhere((marker) => marker.markerId.value == _driverId);
          _markers.add(
            Marker(
              markerId: MarkerId(_driverId!),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue),
              infoWindow: InfoWindow(
                title: 'Servis Aracı',
                snippet: _driverName != null
                    ? '$_driverName ($vehiclePlate)'
                    : vehiclePlate,
              ),
            ),
          );
          _updateUserLocationMarker();
          if (_userCurrentLocation != null && _showRoute) {
            _drawRoute(_userCurrentLocation!, LatLng(lat, lng));
          }
          if (_mapController != null && _userCurrentLocation != null) {
            _fitBothLocations(LatLng(lat, lng));
          } else if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
            );
          }
        } else {
          etaText = _driverName != null
              ? '$_driverName şoförü ($vehiclePlate) şu anda aktif değil'
              : '$vehiclePlate plakalı servis şu anda aktif değil';
        }
      });
    }, onError: (error) {
      print('Şoför konum dinleme hatası: $error');
      setState(() {
        etaText = 'Konum dinleme hatası: $error';
        _isLoading = false;
      });
    });
  }
  void _fitBothLocations(LatLng driverLocation) {
    if (_userCurrentLocation == null || _mapController == null) return;
    double minLat = _userCurrentLocation!.latitude < driverLocation.latitude
        ? _userCurrentLocation!.latitude
        : driverLocation.latitude;
    double maxLat = _userCurrentLocation!.latitude > driverLocation.latitude
        ? _userCurrentLocation!.latitude
        : driverLocation.latitude;
    double minLng = _userCurrentLocation!.longitude < driverLocation.longitude
        ? _userCurrentLocation!.longitude
        : driverLocation.longitude;
    double maxLng = _userCurrentLocation!.longitude > driverLocation.longitude
        ? _userCurrentLocation!.longitude
        : driverLocation.longitude;
    double padding = 0.01;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - padding, minLng - padding),
          northeast: LatLng(maxLat + padding, maxLng + padding),
        ),
        100.0,
      ),
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
      } else if (_userCurrentLocation != null &&
          _driverCurrentLocation != null) {
        _drawRoute(_userCurrentLocation!, _driverCurrentLocation!);
      }
    });
  }
  Future<void> fetchETA() async {
    if (_driverId == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("etas")
          .where("driverId", isEqualTo: _driverId)
          .where("passengerId",
              isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy("createdAt", descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final eta = data['minutes'] as int?;
        if (eta != null && mounted) {
          setState(() {
            etaText = "${etaText ?? ''} - Tahmini varış: $eta dakika";
          });
        }
      }
    } catch (e) {
      print('ETA alma hatası: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                const Text(
                  "Servis Takibi",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_isLoading)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Servis bilgileri yükleniyor...'),
                    ],
                  )
                else if (etaText != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.directions_bus, color: Colors.blue.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            etaText!,
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.green.shade600, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Yeşil: Sizin konumunuz • Mavi: Servis konumu',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _initialPosition ??
                    const LatLng(39.92077, 32.85411),
                zoom: _initialPosition != null ? 15 : 6,
              ),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (controller) {
                _mapController = controller;
                if (_initialPosition != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialPosition!, 15),
                  );
                }
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "route_toggle",
            onPressed: _toggleRoute,
            backgroundColor: _showRoute ? Colors.red : Colors.grey,
            child: Icon(
              _showRoute ? Icons.route : Icons.route_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "my_location",
            onPressed: () {
              if (_userCurrentLocation != null && _mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(_userCurrentLocation!, 16),
                );
              }
            },
            backgroundColor: Colors.green.shade600,
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// Updated

