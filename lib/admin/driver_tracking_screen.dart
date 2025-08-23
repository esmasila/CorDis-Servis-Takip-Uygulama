import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
class DriverTrackingScreen extends StatefulWidget {
  const DriverTrackingScreen({super.key});
  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}
class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  GoogleMapController? _mapController;
  Map<String, dynamic> _selectedDriver = {};
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _stops = [];
  List<Map<String, dynamic>> _trips = [];
  LatLng? _driverLocation;
  Stream<DocumentSnapshot>? _driverLocationStream;
  StreamSubscription<DocumentSnapshot>? _locationSubscription;
  Map<String, dynamic>? _nearestStop;
  Timer? _nearestStopTimer;
  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }
  @override
  void dispose() {
    _locationSubscription?.cancel();
    _nearestStopTimer?.cancel();
    super.dispose();
  }
  Future<void> _loadDrivers() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('drivers').get();
    final list = snapshot.docs.map((e) => {'id': e.id, ...e.data()}).toList();
    setState(() {
      _drivers = list;
      if (list.isNotEmpty) {
        _selectDriver(list.first);
      }
    });
  }
  Future<void> _selectDriver(Map<String, dynamic> driver) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final stopsSnap = await FirebaseFirestore.instance
        .collection('routes')
        .doc(driver['id'])
        .collection('dates')
        .doc(today)
        .collection('enhanced_stops')
        .get();
    final stops = stopsSnap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
    final tripsSnap = await FirebaseFirestore.instance
        .collection('routes')
        .doc(driver['id'])
        .collection('dates')
        .doc(today)
        .collection('trips')
        .get();
    final trips = tripsSnap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
    _locationSubscription?.cancel();
    try {
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver['id'])
          .get();
      if (driverDoc.exists) {
        final driverData = driverDoc.data()!;
        final location = driverData['location'];
        if (location != null &&
            location['lat'] != null &&
            location['lng'] != null) {
          setState(() {
            _driverLocation = LatLng(location['lat'], location['lng']);
          });
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(_driverLocation!, 13),
            );
          }
        }
      }
    } catch (e) {
      print('Şoför konum bilgisi alınamadı: $e');
    }
    final stream = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driver['id'])
        .snapshots();
    _locationSubscription = stream.listen((doc) {
      if (doc.exists) {
        final location = doc.data()?['location'];
        if (location != null &&
            location['lat'] != null &&
            location['lng'] != null) {
          final newLocation = LatLng(location['lat'], location['lng']);
          setState(() {
            _driverLocation = newLocation;
          });
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(newLocation),
            );
          }
          _updateNearestStop();
        }
      }
    });
    setState(() {
      _selectedDriver = driver;
      _stops = stops;
      _trips = trips;
    });
    _startNearestStopUpdates();
  }
  void _startNearestStopUpdates() {
    _nearestStopTimer?.cancel();
    _nearestStopTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateNearestStop();
    });
  }
  void _updateNearestStop() {
    if (_driverLocation == null || _stops.isEmpty) return;
    double minDistance = double.infinity;
    Map<String, dynamic>? nearest;
    for (var stop in _stops) {
      if (stop['lat'] != null && stop['lng'] != null) {
        final distance = _calculateDistance(
          _driverLocation!.latitude,
          _driverLocation!.longitude,
          stop['lat'],
          stop['lng'],
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearest = stop;
        }
      }
    }
    if (nearest != null) {
      setState(() {
        _nearestStop = nearest;
      });
    }
  }
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (var stop in _stops) {
      final isNearest = _nearestStop?['id'] == stop['id'];
      markers.add(
        Marker(
          markerId: MarkerId(stop['id']),
          position: LatLng(stop['lat'], stop['lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isNearest ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: stop['name'],
            snippet:
                "Durum: ${stop['status'] ?? 'Bilinmiyor'}${isNearest ? ' (En Yakın)' : ''}",
          ),
        ),
      );
    }
    if (_driverLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("driver"),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: "Şoför Konumu"),
        ),
      );
    }
    return markers;
  }
  Widget _buildTripCard(Map<String, dynamic> trip) {
    final departureTime = trip['departureTime'] != null
        ? DateTime.parse(trip['departureTime'])
        : null;
    final arrivalTime = trip['arrivalTime'] != null
        ? DateTime.parse(trip['arrivalTime'])
        : null;
    final isDelayed = trip['isDelayed'] ?? false;
    final occupancy = trip['occupancy'] ?? 0;
    final maxCapacity = trip['maxCapacity'] ?? 50;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sefer ${trip['id']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDelayed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'GECİKME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.departure_board,
                              color: Colors.blue, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Kalkış: ${departureTime != null ? DateFormat('HH:mm').format(departureTime) : 'Belirtilmemiş'}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.green, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Varış: ${arrivalTime != null ? DateFormat('HH:mm').format(arrivalTime) : 'Belirtilmemiş'}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Şoför: ${_selectedDriver['name'] ?? 'Bilinmiyor'}',
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people,
                            color: Colors.orange, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          '$occupancy/$maxCapacity',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStopsList() {
    if (_stops.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Durak bulunamadı',
            style: TextStyle(fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stops.length,
      itemBuilder: (context, index) {
        final stop = _stops[index];
        final isNearest = _nearestStop?['id'] == stop['id'];
        final checkInTime = stop['checkInTime'] != null
            ? DateTime.parse(stop['checkInTime'])
            : null;
        final checkOutTime = stop['checkOutTime'] != null
            ? DateTime.parse(stop['checkOutTime'])
            : null;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: isNearest ? Colors.green.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isNearest ? Colors.green : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stop['name'] ?? 'Bilinmeyen Durak',
                              style: TextStyle(
                                fontWeight: isNearest
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNearest) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'EN YAKIN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Durum: ${stop['status'] ?? 'Bilinmiyor'}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (checkInTime != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Check-in: ${DateFormat('HH:mm').format(checkInTime)}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (checkOutTime != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Check-out: ${DateFormat('HH:mm').format(checkOutTime)}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isNearest ? Icons.location_on : Icons.location_off,
                  color: isNearest ? Colors.green : Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servis Takip'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _driverLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Şoför:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<Map<String, dynamic>>(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                          ),
                          value:
                              _selectedDriver.isEmpty ? null : _selectedDriver,
                          hint: const Text(
                            "Şoför Seçin",
                            style: TextStyle(fontSize: 13),
                          ),
                          onChanged: (value) {
                            if (value != null) _selectDriver(value);
                          },
                          items: _drivers
                              .map(
                                (driver) => DropdownMenuItem(
                                  value: driver,
                                  child: Text(
                                    driver['name'] ?? driver['id'],
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_trips.isNotEmpty) ...[
                  Container(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _trips.length,
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 250,
                          child: _buildTripCard(_trips[index]),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 800) {
                        return Column(
                          children: [
                            Expanded(
                              flex: 2,
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: _driverLocation ??
                                      const LatLng(39.9334,
                                          32.8597),
                                  zoom: 13,
                                ),
                                markers: _buildMarkers(),
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                  if (_driverLocation != null) {
                                    controller.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                          _driverLocation!, 13),
                                    );
                                  }
                                },
                              ),
                            ),
                            Container(
                              height: 200,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.grey.shade100,
                                    child: const Row(
                                      children: [
                                        Icon(Icons.list,
                                            color: Colors.blue, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Durak Sırası',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildStopsList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: _driverLocation ??
                                      const LatLng(39.9334,
                                          32.8597),
                                  zoom: 13,
                                ),
                                markers: _buildMarkers(),
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                  if (_driverLocation != null) {
                                    controller.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                          _driverLocation!, 13),
                                    );
                                  }
                                },
                              ),
                            ),
                            Container(
                              width: 320,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.grey.shade100,
                                    child: const Row(
                                      children: [
                                        Icon(Icons.list,
                                            color: Colors.blue, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Durak Sırası',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildStopsList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
