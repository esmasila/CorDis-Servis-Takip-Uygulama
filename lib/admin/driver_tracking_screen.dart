import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../service/enhanced_stop_management_service.dart';

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
  bool _isLoading = true;

  static const LatLng _defaultLocation = LatLng(38.7205, 35.4826);

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
    try {
      setState(() {
        _isLoading = true;
      });

      final snapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isActive', isEqualTo: true)
          .where('status', isNotEqualTo: 'deleted')
          .get();

      final activeDrivers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] == true;
        final isNotDeleted = data['isDeleted'] != true;
        final hasValidStatus =
            data['status'] != 'deleted' && data['status'] != 'inactive';

        final finalIsActive = data['isActive'] == null ? true : isActive;
        final finalIsNotDeleted =
            data['isDeleted'] == null ? true : isNotDeleted;
        final finalHasValidStatus =
            data['status'] == null ? true : hasValidStatus;

        if (finalIsActive && finalIsNotDeleted && finalHasValidStatus) {
          String? regionInfo = data['regionId'] ??
              data['assignedRegion'] ??
              data['region'] ??
              data['area'] ??
              data['bolge'];
          if (regionInfo != null) {
            try {
              final regionDoc = await FirebaseFirestore.instance
                  .collection('regions')
                  .doc(regionInfo)
                  .get();

              if (regionDoc.exists) {
                final regionData = regionDoc.data()!;
                final regionName = regionData['name'] ?? regionInfo;
                data['regionName'] = regionName;
                data['regionId'] = regionInfo;
                print(
                    '✅ Aktif sürücü eklendi: ${doc.id} - ${data['name'] ?? 'İsimsiz'} (Bölge: $regionName)');
              } else {
                data['regionName'] = regionInfo;
                data['regionId'] = regionInfo;
                print(
                    '✅ Aktif sürücü eklendi: ${doc.id} - ${data['name'] ?? 'İsimsiz'} (Bölge: $regionInfo)');
              }
            } catch (e) {
              data['regionName'] = regionInfo;
              data['regionId'] = regionInfo;
              print(
                  '✅ Aktif sürücü eklendi: ${doc.id} - ${data['name'] ?? 'İsimsiz'} (Bölge: $regionInfo)');
            }
          } else {
            print(
                '✅ Aktif sürücü eklendi: ${doc.id} - ${data['name'] ?? 'İsimsiz'} (Bölge: Belirtilmemiş)');
          }

          activeDrivers.add({'id': doc.id, ...data});
        } else {
          print(
              '❌ Sürücü filtrelendi: ${doc.id} - isActive: $finalIsActive, isDeleted: ${!finalIsNotDeleted}, status: ${!finalHasValidStatus}');
        }
      }

      setState(() {
        _drivers = activeDrivers;
        if (activeDrivers.isNotEmpty) {
          _selectDriver(activeDrivers.first);
        }
        _isLoading = false;
      });

      print('📊 Toplam aktif sürücü: ${activeDrivers.length}');
    } catch (e) {
      print('Sürücü yükleme hatası: $e');
      setState(() {
        _drivers = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDriver(Map<String, dynamic> driver) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      print('🔍 Şoför seçildi: ${driver['name'] ?? driver['id']}');
      print('📅 Bugünün tarihi: $today');

      print(
          '📍 Şoför ${driver['name']} için şoföre ait durakları yükleniyor...');
      List<Map<String, dynamic>> stops = [];

      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver['id'])
          .get();

      if (driverDoc.exists) {
        final driverData = driverDoc.data()!;
        String? assignedRegion = driverData['regionId'] ??
            driverData['assignedRegion'] ??
            driverData['region'] ??
            driverData['area'] ??
            driverData['bolge'];

        if (assignedRegion != null) {
          List<Map<String, dynamic>> regionStopsSnap = [];

          print('🔍 Durak arama başlıyor...');
          print('🔍 Bölge adı: $assignedRegion');
          print('🔍 Bölge ID: ${driver['regionId']}');

          try {
            print('🔍 Enhanced stops koleksiyonundan durak arama...');

            final regionDoc = await FirebaseFirestore.instance
                .collection('regions')
                .doc(assignedRegion)
                .get();

            String? regionName;
            if (regionDoc.exists) {
              final regionData = regionDoc.data()!;
              regionName = regionData['name'];
              print('🔍 Bölge adı: $regionName');
            }

            final stopsQuery = await FirebaseFirestore.instance
                .collection('enhanced_stops')
                .where('isActive', isEqualTo: true)
                .get();

            regionStopsSnap = stopsQuery.docs.where((doc) {
              final data = doc.data();

              if (data['isActive'] != true ||
                  data['isDeleted'] == true ||
                  data['deletedAt'] != null ||
                  data['status'] == 'deleted' ||
                  data['status'] == 'inactive' ||
                  data['deleted'] == true ||
                  data['isArchived'] == true ||
                  data['archived'] == true) {
                print(
                    '❌ Durak filtrelendi: ${data['name']} - isActive: ${data['isActive']}, isDeleted: ${data['isDeleted']}, deletedAt: ${data['deletedAt']}, status: ${data['status']}');
                return false;
              }

              final stopRegionId = data['regionId'] ??
                  data['assignedRegion'] ??
                  data['region'] ??
                  data['area'] ??
                  data['bolge'];

              if (stopRegionId == assignedRegion) {
                return true;
              }

              if (stopRegionId == null && regionName != null) {
                final stopRegionName = data['region'] ??
                    data['regionName'] ??
                    data['area'] ??
                    data['bolge'];

                if (stopRegionName != null) {
                  return stopRegionName.toString().toLowerCase() ==
                      regionName.toString().toLowerCase();
                }
              }

              return false;
            }).map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();

            print('🔍 Enhanced stops sonucu: ${regionStopsSnap.length} durak');

            for (var stop in regionStopsSnap) {
              print(
                  '📍 Durak: ${stop['name']} - Bölge: ${stop['regionId'] ?? stop['region']} - Aktif: ${stop['isActive']} - Silinmiş: ${stop['isDeleted']} - Durum: ${stop['status']}');
            }
          } catch (e) {
            print('❌ Enhanced stops arama hatası: $e');
          }

          if (regionStopsSnap.isNotEmpty) {
            stops = regionStopsSnap.where((stop) {
              final isActive = stop['isActive'] == true;
              final isNotDeleted = stop['isDeleted'] != true;
              final notDeletedAt = stop['deletedAt'] == null;
              final hasValidStatus =
                  stop['status'] != 'deleted' && stop['status'] != 'inactive';
              final isNotMainRoad = stop['isMainRoad'] != true;

              if (!isActive ||
                  !isNotDeleted ||
                  !notDeletedAt ||
                  !hasValidStatus ||
                  !isNotMainRoad) {
                print(
                    '❌ Durak filtrelendi: ${stop['name']} - isActive: $isActive, isDeleted: ${!isNotDeleted}, deletedAt: ${!notDeletedAt}, status: ${stop['status']}, isMainRoad: ${!isNotMainRoad}');
                return false;
              }

              return true;
            }).toList();

            print(
                '✅ Şoför ${driver['name']} bölgesinde (${driver['regionName']}) ${stops.length} aktif durak bulundu');

            for (var stop in stops) {
              print('✅ Aktif durak: ${stop['name']} - ID: ${stop['id']}');
            }
          } else {
            print('❌ Şoför ${driver['name']} bölgesinde durak bulunamadı');
          }
        } else {
          print('❌ Şoför ${driver['name']} için bölge bilgisi bulunamadı');
        }
      }

      setState(() {
        _stops = stops;
        _selectedDriver = driver;
        _trips = [];
      });

      if (stops.isNotEmpty) {
        _moveMapToStops(stops);
      }

      print('📍 Şoför ${driver['name']} konumu yükleniyor...');
      await _loadDriverLocation(driver['id']);
    } catch (e) {
      print('❌ Şoför seçimi hatası: $e');
    }
  }

  void _showDriverSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Şoför Seçin'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _drivers.length,
              itemBuilder: (context, index) {
                final driver = _drivers[index];
                return ListTile(
                  leading: Icon(Icons.person, color: Colors.blue),
                  title: Text(
                    driver['name'] ?? driver['id'] ?? 'Bilinmeyen',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Bölge: ${driver['regionName'] ?? 'Bilinmeyen'}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _selectDriver(driver);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('İptal'),
            ),
          ],
        );
      },
    );
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
      double? lat, lng;

      if (stop['lat'] != null && stop['lng'] != null) {
        try {
          lat = (stop['lat'] is int)
              ? (stop['lat'] as int).toDouble()
              : stop['lat'] as double?;
          lng = (stop['lng'] is int)
              ? (stop['lng'] as int).toDouble()
              : stop['lng'] as double?;
        } catch (e) {
          print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
          continue;
        }
      } else if (stop['latitude'] != null && stop['longitude'] != null) {
        try {
          lat = (stop['latitude'] is int)
              ? (stop['latitude'] as int).toDouble()
              : stop['latitude'] as double?;
          lng = (stop['longitude'] is int)
              ? (stop['longitude'] as int).toDouble()
              : stop['longitude'] as double?;
        } catch (e) {
          print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
          continue;
        }
      }

      if (lat == null || lng == null) {
        continue;
      }

      final distance = _calculateDistance(
        _driverLocation!.latitude,
        _driverLocation!.longitude,
        lat,
        lng,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearest = stop;
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
      double? lat, lng;

      if (stop['lat'] != null && stop['lng'] != null) {
        try {
          lat = (stop['lat'] is int)
              ? (stop['lat'] as int).toDouble()
              : stop['lat'] as double?;
          lng = (stop['lng'] is int)
              ? (stop['lng'] as int).toDouble()
              : stop['lng'] as double?;
        } catch (e) {
          print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
          continue;
        }
      } else if (stop['latitude'] != null && stop['longitude'] != null) {
        try {
          lat = (stop['latitude'] is int)
              ? (stop['latitude'] as int).toDouble()
              : stop['latitude'] as double?;
          lng = (stop['longitude'] is int)
              ? (stop['longitude'] as int).toDouble()
              : stop['longitude'] as double?;
        } catch (e) {
          print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
          continue;
        }
      }

      if (lat == null || lng == null) {
        print(
            '⚠️ Durak ${stop['name']} için koordinat bulunamadı: lat=${stop['lat'] ?? stop['latitude']}, lng=${stop['lng'] ?? stop['longitude']}');
        continue;
      }

      final isNearest = _nearestStop?['id'] == stop['id'];
      markers.add(
        Marker(
          markerId: MarkerId(stop['id']),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isNearest ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: stop['name'] ?? 'Bilinmeyen Durak',
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
    final tripName = trip['name'] ??
        trip['routeName'] ??
        trip['route'] ??
        'Sefer ${trip['id'].toString().substring(0, 8)}...';

    String departureText = 'Belirtilmemiş';
    String arrivalText = 'Belirtilmemiş';

    try {
      if (trip['departureTime'] != null) {
        final departureTime = DateTime.parse(trip['departureTime']);
        departureText = DateFormat('HH:mm').format(departureTime);
      } else if (trip['departure'] != null) {
        final departureTime = DateTime.parse(trip['departure']);
        departureText = DateFormat('HH:mm').format(departureTime);
      } else if (trip['startTime'] != null) {
        final departureTime = DateTime.parse(trip['startTime']);
        departureText = DateFormat('HH:mm').format(departureTime);
      }
    } catch (e) {
      print('❌ Kalkış zamanı parse hatası: $e');
    }

    try {
      if (trip['arrivalTime'] != null) {
        final arrivalTime = DateTime.parse(trip['arrivalTime']);
        arrivalText = DateFormat('HH:mm').format(arrivalTime);
      } else if (trip['arrival'] != null) {
        final arrivalTime = DateTime.parse(trip['arrival']);
        arrivalText = DateFormat('HH:mm').format(arrivalTime);
      } else if (trip['endTime'] != null) {
        final arrivalTime = DateTime.parse(trip['endTime']);
        arrivalText = DateFormat('HH:mm').format(arrivalTime);
      }
    } catch (e) {
      print('❌ Varış zamanı parse hatası: $e');
    }

    final isDelayed = trip['isDelayed'] ?? trip['delayed'] ?? false;
    final occupancy = trip['occupancy'] ??
        trip['currentPassengers'] ??
        trip['passengers'] ??
        trip['currentCapacity'] ??
        0;
    final maxCapacity = trip['maxCapacity'] ??
        trip['capacity'] ??
        trip['totalCapacity'] ??
        trip['maxPassengers'] ??
        50;

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
                    tripName,
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
                              'Kalkış: $departureText',
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
                              'Varış: $arrivalText',
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
          child: Column(
            children: [
              Icon(Icons.location_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Durak bulunamadı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Durak yönetiminde aktif durak ekleyin',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final allStops = _stops;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: allStops.length,
      itemBuilder: (context, index) {
        final stop = allStops[index];
        final stopName = stop['name'] ?? stop['stopName'] ?? 'Bilinmeyen Durak';
        final stopAddress =
            stop['address'] ?? stop['location'] ?? 'Adres bilgisi yok';

        bool hasCoordinates = false;
        String coordinateStatus = '';

        if (stop['lat'] != null && stop['lng'] != null) {
          hasCoordinates = true;
          coordinateStatus = 'Koordinat: ${stop['lat']}, ${stop['lng']}';
        } else if (stop['latitude'] != null && stop['longitude'] != null) {
          hasCoordinates = true;
          coordinateStatus =
              'Koordinat: ${stop['latitude']}, ${stop['longitude']}';
        } else {
          coordinateStatus = 'Koordinat bilgisi eksik';
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: hasCoordinates ? Colors.white : Colors.orange.shade50,
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasCoordinates
                    ? Colors.blue.shade100
                    : Colors.orange.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Icon(
                  hasCoordinates ? Icons.location_on : Icons.location_off,
                  color: hasCoordinates
                      ? Colors.blue.shade700
                      : Colors.orange.shade700,
                  size: 20,
                ),
              ),
            ),
            title: Text(
              stopName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: hasCoordinates ? Colors.black : Colors.orange.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stopAddress,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                SizedBox(height: 2),
                Text(
                  coordinateStatus,
                  style: TextStyle(
                    color: hasCoordinates
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            trailing: Icon(
              hasCoordinates ? Icons.location_on : Icons.warning,
              color: hasCoordinates ? Colors.blue : Colors.orange,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  void _loadStopsForDriver() {
    if (_selectedDriver != null) {
      _selectDriver(_selectedDriver!);
    }
  }

  void _moveMapToStops(List<Map<String, dynamic>> stops) {
    if (stops.isEmpty || _mapController == null) return;

    try {
      List<LatLng> stopCoordinates = [];

      for (var stop in stops) {
        double? lat, lng;

        if (stop['lat'] != null && stop['lng'] != null) {
          try {
            lat = (stop['lat'] is int)
                ? (stop['lat'] as int).toDouble()
                : stop['lat'] as double?;
            lng = (stop['lng'] is int)
                ? (stop['lng'] as int).toDouble()
                : stop['lng'] as double?;
          } catch (e) {
            print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
            continue;
          }
        } else if (stop['latitude'] != null && stop['longitude'] != null) {
          try {
            lat = (stop['latitude'] is int)
                ? (stop['latitude'] as int).toDouble()
                : stop['latitude'] as double?;
            lng = (stop['longitude'] is int)
                ? (stop['longitude'] as int).toDouble()
                : stop['longitude'] as double?;
          } catch (e) {
            print('❌ Durak ${stop['name']} koordinat dönüşüm hatası: $e');
            continue;
          }
        }

        if (lat != null && lng != null) {
          stopCoordinates.add(LatLng(lat, lng));
        }
      }

      if (stopCoordinates.isNotEmpty) {
        final bounds = _calculateBounds(stopCoordinates);
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 50.0),
        );
        print('✅ Harita durakların konumuna taşındı');
      }
    } catch (e) {
      print('❌ Harita taşıma hatası: $e');
    }
  }

  LatLngBounds _calculateBounds(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(38.5, 35.0),
        northeast: const LatLng(39.0, 36.0),
      );
    }

    double minLat = coordinates.first.latitude;
    double maxLat = coordinates.first.latitude;
    double minLng = coordinates.first.longitude;
    double maxLng = coordinates.first.longitude;

    for (var coord in coordinates) {
      if (coord.latitude < minLat) minLat = coord.latitude;
      if (coord.latitude > maxLat) maxLat = coord.latitude;
      if (coord.longitude < minLng) minLng = coord.longitude;
      if (coord.longitude > maxLng) maxLng = coord.longitude;
    }

    const margin = 0.01;
    return LatLngBounds(
      southwest: LatLng(minLat - margin, minLng - margin),
      northeast: LatLng(maxLat + margin, maxLng + margin),
    );
  }

  Future<void> _loadDriverTrips(String driverId, String today) async {
    try {
      List<Map<String, dynamic>> trips = [];

      final tripsSnap = await FirebaseFirestore.instance
          .collection('routes')
          .doc(driverId)
          .collection('dates')
          .doc(today)
          .collection('trips')
          .get();

      if (tripsSnap.docs.isNotEmpty) {
        trips = tripsSnap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
        print('✅ Şoför bugün ${trips.length} sefer yapıyor');
      } else {
        print('⚠️ Şoför bugün sefer yapmıyor, genel seferler deneniyor...');
        final generalTripsSnap = await FirebaseFirestore.instance
            .collection('routes')
            .doc(driverId)
            .collection('trips')
            .get();

        if (generalTripsSnap.docs.isNotEmpty) {
          trips = generalTripsSnap.docs
              .map((e) => {'id': e.id, ...e.data()})
              .toList();
          print('✅ Şoför genel rotasında ${trips.length} sefer bulundu');
        } else {
          print('⚠️ Şoför için hiç sefer bulunamadı');
        }
      }

      if (trips.isNotEmpty) {
        trips.sort((a, b) {
          final timeA =
              a['departureTime'] ?? a['departure'] ?? a['startTime'] ?? '';
          final timeB =
              b['departureTime'] ?? b['departure'] ?? b['startTime'] ?? '';
          if (timeA.isEmpty && timeB.isEmpty) return 0;
          if (timeA.isEmpty) return 1;
          if (timeB.isEmpty) return -1;
          try {
            final dateA = DateTime.parse(timeA);
            final dateB = DateTime.parse(timeB);
            return dateA.compareTo(dateB);
          } catch (e) {
            return 0;
          }
        });
      }

      setState(() {
        _trips = trips;
      });
    } catch (e) {
      print('❌ Şoför sefer yükleme hatası: $e');
      setState(() {
        _trips = [];
      });
    }
  }

  Future<void> _loadDriverLocation(String driverId) async {
    try {
      final locationDoc = await FirebaseFirestore.instance
          .collection('driver_locations')
          .doc(driverId)
          .get();

      if (locationDoc.exists) {
        final locationData = locationDoc.data()!;
        final lat = locationData['lat'];
        final lng = locationData['lng'];

        if (lat != null && lng != null) {
          setState(() {
            _driverLocation = LatLng(
              (lat is int) ? lat.toDouble() : lat as double,
              (lng is int) ? lng.toDouble() : lng as double,
            );
          });
          print('✅ Şoför konumu güncellendi: $_driverLocation');
        } else {
          print('⚠️ Şoför konum bilgisi eksik');
        }
      } else {
        print('⚠️ Şoför konum dokümanı bulunamadı');
      }

      _locationSubscription?.cancel();
      _locationSubscription = FirebaseFirestore.instance
          .collection('driver_locations')
          .doc(driverId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          final lat = data['lat'];
          final lng = data['lng'];

          if (lat != null && lng != null) {
            setState(() {
              _driverLocation = LatLng(
                (lat is int) ? lat.toDouble() : lat as double,
                (lng is int) ? lng.toDouble() : lng as double,
              );
            });
          }
        }
      });
    } catch (e) {
      print('❌ Şoför konum yükleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Şoför Takibi'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, color: Colors.blue, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Şoför Seçimi',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _showDriverSelectionDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, color: Colors.blue),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _selectedDriver != null
                                            ? 'Şoför: ${_selectedDriver!['name'] ?? 'Bilinmeyen'}'
                                            : 'Şoför seçin',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_selectedDriver != null) ...[
                                        SizedBox(height: 4),
                                        Text(
                                          'Bölge: ${_selectedDriver!['regionName'] ?? 'Bilinmeyen'}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 300,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _driverLocation ?? _defaultLocation,
                            zoom: 13,
                          ),
                          markers: _buildMarkers(),
                          onMapCreated: (controller) {
                            setState(() {
                              _mapController = controller;
                            });
                            if (_driverLocation != null) {
                              controller.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                    _driverLocation!, 13),
                              );
                            }
                          },
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: true,
                          mapToolbarEnabled: false,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 300,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.grey.shade100,
                          child: Row(
                            children: [
                              Icon(Icons.list, color: Colors.blue, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Durak Sırası',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    if (_selectedDriver != null) ...[
                                      SizedBox(height: 4),
                                      Text(
                                        '${_selectedDriver!['name'] ?? 'Bilinmeyen'} - ${_selectedDriver!['regionName'] ?? 'Bilinmeyen'} Bölgesi',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (_stops.isNotEmpty) ...[
                                Text(
                                  '${_stops.length} Durak',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                                SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _loadStopsForDriver(),
                                  icon: Icon(Icons.refresh, color: Colors.blue),
                                  tooltip: 'Yenile',
                                ),
                              ],
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
              ),
            ),
    );
  }
}
