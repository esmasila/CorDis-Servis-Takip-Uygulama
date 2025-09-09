import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math' as math;

class RegionLiveTrackingScreen extends StatefulWidget {
  const RegionLiveTrackingScreen({super.key});
  @override
  State<RegionLiveTrackingScreen> createState() =>
      _RegionLiveTrackingScreenState();
}

class _RegionLiveTrackingScreenState extends State<RegionLiveTrackingScreen> {
  GoogleMapController? _mapController;
  String? _selectedRegionId;
  String? _selectedRegionName;
  String? _selectedSubRegionId;
  String? _selectedSubRegionName;
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _subRegions = [];
  Set<Marker> _markers = {};
  Set<Circle> _regionCircles = {};
  bool _isLoading = true;
  int _activeDriversCount = 0;
  int _totalPassengersCount = 0;
  double _averageDelay = 0.0;
  int _incidentCount = 0;
  int _totalVehicles = 0;
  int _completedServices = 0;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(38.7205, 35.4826),
    zoom: 10,
  );

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadRegions() async {
    try {
      print('🔍 Bölgeler yükleniyor...');
      final snapshot = await FirebaseFirestore.instance
          .collection('regions')
          .orderBy('name')
          .get();

      setState(() {
        _regions = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Bilinmeyen Bölge',
            'type': data['type'] ?? 'ilce',
            'centerLat': data['centerLat'] ?? data['lat'] ?? 38.7205,
            'centerLng': data['centerLng'] ?? data['lng'] ?? 35.4826,
          };
        }).toList();
        _isLoading = false;
      });
      print('✅ ${_regions.length} bölge yüklendi');
    } catch (e) {
      print('❌ Bölge yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSubRegions(String parentRegionId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('sub_regions')
          .where('parentRegionId', isEqualTo: parentRegionId)
          .orderBy('name')
          .get();

      setState(() {
        _subRegions = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Bilinmeyen Alt Bölge',
            'type': data['type'] ?? 'mahalle',
            'parentRegionId': data['parentRegionId'],
          };
        }).toList();
      });
      print('✅ ${_subRegions.length} alt bölge yüklendi');
    } catch (e) {
      print('❌ Alt bölge yükleme hatası: $e');
    }
  }

  void _onRegionSelected(String regionId, String regionName) {
    print('🎯 Bölge seçildi: $regionName ($regionId)');
    setState(() {
      _selectedRegionId = regionId;
      _selectedRegionName = regionName;
      _selectedSubRegionId = null;
      _selectedSubRegionName = null;
      _markers.clear();
      _regionCircles.clear();
      _resetCounters();
    });

    _loadSubRegions(regionId);
    _loadRegionData(regionId);
  }

  void _onSubRegionSelected(String subRegionId, String subRegionName) {
    print('🎯 Alt bölge seçildi: $subRegionName ($subRegionId)');
    setState(() {
      _selectedSubRegionId = subRegionId;
      _selectedSubRegionName = subRegionName;
      _markers.clear();
      _regionCircles.clear();
      _resetCounters();
    });

    _loadRegionData(subRegionId);
  }

  void _resetCounters() {
    _activeDriversCount = 0;
    _totalPassengersCount = 0;
    _averageDelay = 0.0;
    _incidentCount = 0;
    _totalVehicles = 0;
    _completedServices = 0;
  }

  Future<void> _loadRegionData(String regionId) async {
    print('📊 Bölge verileri yükleniyor: $regionId');

    try {
      await _loadStops(regionId);

      await _loadDrivers(regionId);

      await _loadPassengers(regionId);

      await _loadStatistics(regionId);

      _centerMapOnMarkers();
    } catch (e) {
      print('❌ Bölge veri yükleme hatası: $e');
    }
  }

  Future<void> _loadStops(String regionId) async {
    try {
      print('🚏 Duraklar yükleniyor...');

      var stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();

      print('📊 Enhanced stops: ${stopsSnapshot.docs.length} durak bulundu');

      if (stopsSnapshot.docs.isEmpty) {
        stopsSnapshot = await FirebaseFirestore.instance
            .collection('stops')
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .get();
        print('📊 Normal stops: ${stopsSnapshot.docs.length} durak bulundu');
      }

      final Set<Marker> stopMarkers = {};

      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();

        final isDeleted = data['isDeleted'] == true ||
            data['deletedAt'] != null ||
            data['status'] == 'deleted' ||
            data['status'] == 'inactive' ||
            data['deleted'] == true ||
            data['isArchived'] == true ||
            data['archived'] == true;

        final isMainRoad = data['isMainRoad'] == true ||
            data['mainRoad'] == true ||
            data['type'] == 'main_road' ||
            data['category'] == 'main_road';

        if (isDeleted || isMainRoad) {
          print(
              '❌ Durak filtrelendi: ${data['name'] ?? 'İsimsiz'} - Silinmiş: $isDeleted, Ana Yol: $isMainRoad');
          continue;
        }

        double? lat = data['lat'] as double? ??
            data['latitude'] as double? ??
            (data['lat'] as num?)?.toDouble() ??
            (data['latitude'] as num?)?.toDouble();

        double? lng = data['lng'] as double? ??
            data['longitude'] as double? ??
            (data['lng'] as num?)?.toDouble() ??
            (data['longitude'] as num?)?.toDouble();

        final name = data['name'] as String? ?? 'Durak';
        final address = data['address'] as String? ?? 'Adres bilgisi yok';

        print('📍 Durak: $name - Koordinatlar: ($lat, $lng)');

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          stopMarkers.add(
            Marker(
              markerId: MarkerId('stop_${doc.id}'),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: '🚏 $name',
                snippet: 'Adres: $address',
              ),
            ),
          );
        }
      }

      final currentMarkers =
          _markers.where((m) => !m.markerId.value.startsWith('stop_')).toSet();

      setState(() {
        _markers = {...currentMarkers, ...stopMarkers};
      });

      print(
          '✅ ${stopMarkers.length} durak işaretleyicisi eklendi (filtrelenmiş)');
    } catch (e) {
      print('❌ Durak yükleme hatası: $e');
    }
  }

  Future<void> _loadDrivers(String regionId) async {
    try {
      print('🚐 Şoförler yükleniyor...');

      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();

      final Set<Marker> driverMarkers = {};

      for (final doc in driversSnapshot.docs) {
        final data = doc.data();

        double? lat = data['currentLat'] as double? ??
            data['lat'] as double? ??
            data['latitude'] as double? ??
            (data['currentLat'] as num?)?.toDouble() ??
            (data['lat'] as num?)?.toDouble() ??
            (data['latitude'] as num?)?.toDouble();

        double? lng = data['currentLng'] as double? ??
            data['lng'] as double? ??
            data['longitude'] as double? ??
            (data['currentLng'] as num?)?.toDouble() ??
            (data['lng'] as num?)?.toDouble() ??
            (data['longitude'] as num?)?.toDouble();

        final name = data['name'] as String? ?? 'Şoför';
        final vehiclePlate = data['vehiclePlate'] as String? ?? '';
        final isActive = data['isActive'] as bool? ?? false;

        print('🚐 Şoför: $name - Koordinatlar: ($lat, $lng)');

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          driverMarkers.add(
            Marker(
              markerId: MarkerId('driver_${doc.id}'),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(isActive
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueViolet),
              infoWindow: InfoWindow(
                title: '🚐 $name',
                snippet:
                    'Plaka: $vehiclePlate\nDurum: ${isActive ? "Aktif" : "Pasif"}',
              ),
            ),
          );
        }
      }

      final currentMarkers = _markers
          .where((m) => !m.markerId.value.startsWith('driver_'))
          .toSet();

      setState(() {
        _markers = {...currentMarkers, ...driverMarkers};
        _activeDriversCount = driverMarkers.length;
      });

      print('✅ ${driverMarkers.length} şoför işaretleyicisi eklendi');
    } catch (e) {
      print('❌ Şoför yükleme hatası: $e');
    }
  }

  Future<void> _loadPassengers(String regionId) async {
    try {
      print('👥 Yolcular yükleniyor...');

      final passengersSnapshot = await FirebaseFirestore.instance
          .collection('passengers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();

      print('📊 Bölgedeki toplam yolcu: ${passengersSnapshot.docs.length}');

      int totalActivePassengers = 0;
      final Set<Marker> passengerMarkers = {};

      final regionDoc = await FirebaseFirestore.instance
          .collection('regions')
          .doc(regionId)
          .get();

      double? regionLat;
      double? regionLng;

      if (regionDoc.exists) {
        final regionData = regionDoc.data()!;
        regionLat = regionData['centerLat'] as double? ??
            regionData['lat'] as double? ??
            (regionData['centerLat'] as num?)?.toDouble() ??
            (regionData['lat'] as num?)?.toDouble();

        regionLng = regionData['centerLng'] as double? ??
            regionData['lng'] as double? ??
            (regionData['centerLng'] as num?)?.toDouble() ??
            (regionData['lng'] as num?)?.toDouble();
      }

      if (regionLat == null || regionLng == null) {
        regionLat = 38.712769008375865;
        regionLng = 35.34330625087023;
        print(
            '⚠️ Bölge koordinatları bulunamadı, varsayılan koordinatlar kullanılıyor');
      }

      for (final passengerDoc in passengersSnapshot.docs) {
        final data = passengerDoc.data();

        final isDeleted = data['isDeleted'] == true ||
            data['deletedAt'] != null ||
            data['status'] == 'deleted' ||
            data['status'] == 'inactive' ||
            data['deleted'] == true ||
            data['isArchived'] == true ||
            data['archived'] == true;

        if (!isDeleted) {
          totalActivePassengers++;
          print('✅ Aktif yolcu: ${data['name'] ?? 'İsimsiz'}');

          final stopId = data['stopId'] as String? ??
              data['stop_id'] as String? ??
              data['enhancedStopId'] as String? ??
              data['stopId'] as String?;

          if (stopId != null) {
            final stopDoc = await FirebaseFirestore.instance
                .collection('enhanced_stops')
                .doc(stopId)
                .get();

            if (stopDoc.exists) {
              final stopData = stopDoc.data()!;
              double? lat = stopData['lat'] as double? ??
                  stopData['latitude'] as double? ??
                  (stopData['lat'] as num?)?.toDouble() ??
                  (stopData['latitude'] as num?)?.toDouble();

              double? lng = stopData['lng'] as double? ??
                  stopData['longitude'] as double? ??
                  (stopData['lng'] as num?)?.toDouble() ??
                  (stopData['longitude'] as num?)?.toDouble();

              final name = data['name'] as String? ?? 'Yolcu';
              final stopName =
                  stopData['name'] as String? ?? 'Durak bilgisi yok';
              final isActive = data['isActive'] as bool? ?? false;

              if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
                passengerMarkers.add(
                  Marker(
                    markerId: MarkerId('passenger_${passengerDoc.id}'),
                    position: LatLng(lat, lng),
                    icon: BitmapDescriptor.defaultMarkerWithHue(isActive
                        ? BitmapDescriptor.hueBlue
                        : BitmapDescriptor.hueOrange),
                    infoWindow: InfoWindow(
                      title: '👤 $name',
                      snippet:
                          'Durak: $stopName\nDurum: ${isActive ? "Aktif" : "Pasif"}',
                    ),
                  ),
                );
                print(
                    '✅ Yolcu işaretleyicisi eklendi: $name - Durak: $stopName - Koordinatlar: ($lat, $lng)');
              }
            }
          } else {
            print('⚠️ Yolcunun durak ID\'si yok: ${data['name'] ?? 'İsimsiz'}');

            final name = data['name'] as String? ?? 'Yolcu';
            final isActive = data['isActive'] as bool? ?? false;

            final offset = totalActivePassengers * 0.001;
            final passengerLat = regionLat! + offset;
            final passengerLng = regionLng! + offset;

            passengerMarkers.add(
              Marker(
                markerId: MarkerId('passenger_${passengerDoc.id}'),
                position: LatLng(passengerLat, passengerLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(isActive
                    ? BitmapDescriptor.hueBlue
                    : BitmapDescriptor.hueOrange),
                infoWindow: InfoWindow(
                  title: '👤 $name',
                  snippet:
                      'Bölge Merkezi\nDurum: ${isActive ? "Aktif" : "Pasif"}',
                ),
              ),
            );
            print(
                '✅ Yolcu bölge merkezinde gösterildi: $name - Koordinatlar: ($passengerLat, $passengerLng)');
          }
        } else {
          print('❌ Yolcu silinmiş: ${data['name'] ?? 'İsimsiz'}');
        }
      }

      final currentMarkers = _markers
          .where((m) => !m.markerId.value.startsWith('passenger_'))
          .toSet();

      setState(() {
        _markers = {...currentMarkers, ...passengerMarkers};
        _totalPassengersCount = totalActivePassengers;
      });

      print(
          '✅ ${passengerMarkers.length} yolcu işaretleyicisi eklendi (${totalActivePassengers} toplam)');
    } catch (e) {
      print('❌ Yolcu yükleme hatası: $e');
    }
  }

  Future<void> _loadStatistics(String regionId) async {
    try {
      print('📊 İstatistikler yükleniyor...');

      final totalDriversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .get();

      final servicesSnapshot = await FirebaseFirestore.instance
          .collection('service_logs')
          .where('regionId', isEqualTo: regionId)
          .where('status', isEqualTo: 'completed')
          .get();

      final incidentsSnapshot = await FirebaseFirestore.instance
          .collection('incidents')
          .where('regionId', isEqualTo: regionId)
          .where('status', isEqualTo: 'active')
          .get();

      setState(() {
        _totalVehicles = totalDriversSnapshot.docs.length;
        _completedServices = servicesSnapshot.docs.length;
        _incidentCount = incidentsSnapshot.docs.length;
      });

      print('✅ İstatistikler yüklendi');
    } catch (e) {
      print('❌ İstatistik yükleme hatası: $e');
    }
  }

  void _centerMapOnMarkers() {
    if (_mapController == null || _markers.isEmpty) {
      print('⚠️ Harita kontrolcüsü veya işaretleyici bulunamadı');
      return;
    }

    try {
      print('🎯 Harita işaretleyicilere odaklanıyor...');

      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (final marker in _markers) {
        minLat = math.min(minLat, marker.position.latitude);
        maxLat = math.max(maxLat, marker.position.latitude);
        minLng = math.min(minLng, marker.position.longitude);
        maxLng = math.max(maxLng, marker.position.longitude);
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50.0),
      );

      print('✅ Harita ${_markers.length} işaretleyiciye odaklandı');
    } catch (e) {
      print('❌ Harita odaklama hatası: $e');
    }
  }

  String _getRegionTypeText(String type) {
    switch (type) {
      case 'ilce':
        return 'İlçe';
      case 'kampus':
        return 'Kampüs';
      case 'tesis':
        return 'Tesis';
      case 'organize_sanayi':
        return 'Organize Sanayi';
      default:
        return 'Bölge';
    }
  }

  IconData _getRegionTypeIcon(String type) {
    switch (type) {
      case 'ilce':
        return Icons.location_city;
      case 'kampus':
        return Icons.school;
      case 'tesis':
        return Icons.business;
      case 'organize_sanayi':
        return Icons.factory;
      default:
        return Icons.location_on;
    }
  }

  String _getSubRegionTypeText(String type) {
    switch (type) {
      case 'mahalle':
        return 'Mahalle';
      case 'organize_sanayi':
        return 'Organize Sanayi';
      case 'kampus_bolumu':
        return 'Kampüs Bölümü';
      case 'tesis_bolumu':
        return 'Tesis Bölümü';
      default:
        return 'Alt Bölge';
    }
  }

  IconData _getSubRegionTypeIcon(String type) {
    switch (type) {
      case 'mahalle':
        return Icons.home;
      case 'organize_sanayi':
        return Icons.factory;
      case 'kampus_bolumu':
        return Icons.account_balance;
      case 'tesis_bolumu':
        return Icons.business_center;
      default:
        return Icons.location_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Bölge Canlı Takip',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_selectedRegionId != null) ...[
            IconButton(
              onPressed: _centerMapOnMarkers,
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Haritayı Ortala',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Bölgeler yükleniyor...'),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedRegionId,
                            hint: const Text('Ana bölgeyi seçin'),
                            isExpanded: true,
                            items: _regions.map((region) {
                              final type = region['type'] ?? 'ilce';
                              final typeText = _getRegionTypeText(type);
                              return DropdownMenuItem<String>(
                                value: region['id'],
                                child: Row(
                                  children: [
                                    Icon(_getRegionTypeIcon(type), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child:
                                          Text('${region['name']} ($typeText)'),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (regionId) {
                              if (regionId != null) {
                                final region = _regions.firstWhere(
                                  (r) => r['id'] == regionId,
                                );
                                _onRegionSelected(regionId, region['name']);
                              }
                            },
                          ),
                        ),
                      ),
                      if (_selectedRegionId != null &&
                          _subRegions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.blue.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedSubRegionId,
                              hint: const Text('Alt bölgeyi seçin'),
                              isExpanded: true,
                              items: _subRegions.map((subRegion) {
                                final type = subRegion['type'] ?? 'mahalle';
                                final typeText = _getSubRegionTypeText(type);
                                return DropdownMenuItem<String>(
                                  value: subRegion['id'],
                                  child: Row(
                                    children: [
                                      Icon(_getSubRegionTypeIcon(type),
                                          size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                            '${subRegion['name']} ($typeText)'),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (subRegionId) {
                                if (subRegionId != null) {
                                  final subRegion = _subRegions.firstWhere(
                                    (r) => r['id'] == subRegionId,
                                  );
                                  _onSubRegionSelected(
                                      subRegionId, subRegion['name']);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                      if (_selectedRegionName != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.drive_eta,
                                        color: Colors.green.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_activeDriversCount',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Aktif Araç',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.blue.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.local_shipping,
                                        color: Colors.blue.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_totalVehicles',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Toplam Araç',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.purple.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.people,
                                        color: Colors.purple.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_totalPassengersCount',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Toplam Yolcu',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.purple.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.orange.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.schedule,
                                        color: Colors.orange.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_averageDelay.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Ort. Gecikme (dk)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.red.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.warning,
                                        color: Colors.red.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_incidentCount',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Olay Sayısı',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.teal.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.check_circle,
                                        color: Colors.teal.shade600),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_completedServices',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Tamamlanan Servis',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.teal.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.map, color: Colors.blue.shade600),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Ana Bölge: $_selectedRegionName',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedSubRegionName != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.location_on,
                                        color: Colors.blue.shade400),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Alt Bölge: $_selectedSubRegionName',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _selectedRegionId == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Takip için bir bölge seçin',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ana bölge seçerek canlı takip\nyapabilir ve detaylı istatistikleri\ngörebilirsiniz.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GoogleMap(
                          initialCameraPosition: _initialPosition,
                          markers: _markers,
                          circles: _regionCircles,
                          onMapCreated: (GoogleMapController controller) {
                            _mapController = controller;
                          },
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: true,
                          mapToolbarEnabled: false,
                        ),
                ),
                if (_selectedRegionId != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('Aktif Araç',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('Aktif Yolcu',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('Pasif Yolcu',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('Durak',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.layers,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'Toplam ${_markers.length} işaretleyici gösteriliyor',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}



 Again


