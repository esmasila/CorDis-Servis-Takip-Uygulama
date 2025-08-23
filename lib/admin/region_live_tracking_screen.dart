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
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  StreamSubscription<QuerySnapshot>? _passengersSubscription;
  bool _isLoading = true;
  int _activeDriversCount = 0;
  int _totalPassengersCount = 0;
  double _averageDelay = 0.0;
  int _incidentCount = 0;
  int _totalVehicles = 0;
  int _completedServices = 0;
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(41.0082, 28.9784),
    zoom: 10,
  );
  @override
  void initState() {
    super.initState();
    _loadRegions();
  }
  @override
  void dispose() {
    _driversSubscription?.cancel();
    _passengersSubscription?.cancel();
    super.dispose();
  }
  Future<void> _loadRegions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('regions')
          .orderBy('name')
          .get();
      setState(() {
        _regions = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  'name': doc.data()['name'] ?? 'Bilinmeyen Bölge',
                  'type': doc.data()['type'] ?? 'ilce',
                  'centerLat': doc.data()['centerLat'],
                  'centerLng': doc.data()['centerLng'],
                })
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bölgeler yüklenirken hata: $e')),
        );
      }
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
        _subRegions = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  'name': doc.data()['name'] ?? 'Bilinmeyen Alt Bölge',
                  'type': doc.data()['type'] ?? 'mahalle',
                  'parentRegionId': doc.data()['parentRegionId'],
                })
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alt bölgeler yüklenirken hata: $e')),
        );
      }
    }
  }
  void _onRegionSelected(String regionId, String regionName) {
    setState(() {
      _selectedRegionId = regionId;
      _selectedRegionName = regionName;
      _selectedSubRegionId = null;
      _selectedSubRegionName = null;
      _markers.clear();
      _resetCounters();
    });
    _loadSubRegions(regionId);
    _startTrackingRegion();
    _loadRegionStatistics(regionId);
    Future.delayed(const Duration(milliseconds: 500), () {
      _centerMapToRegion();
    });
  }
  void _onSubRegionSelected(String subRegionId, String subRegionName) {
    setState(() {
      _selectedSubRegionId = subRegionId;
      _selectedSubRegionName = subRegionName;
      _markers.clear();
      _resetCounters();
    });
    _startTrackingSubRegion();
    _loadSubRegionStatistics(subRegionId);
  }
  void _resetCounters() {
    _activeDriversCount = 0;
    _totalPassengersCount = 0;
    _averageDelay = 0.0;
    _incidentCount = 0;
    _totalVehicles = 0;
    _completedServices = 0;
  }
  Future<void> _loadRegionStatistics(String regionId) async {
    try {
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      final totalDriversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .get();
      final servicesSnapshot = await FirebaseFirestore.instance
          .collection('service_logs')
          .where('regionId', isEqualTo: regionId)
          .where('status', isEqualTo: 'completed')
          .get();
      double totalDelay = 0.0;
      int delayCount = 0;
      int completedCount = 0;
      for (final doc in servicesSnapshot.docs) {
        final data = doc.data();
        final scheduledTime = data['scheduledTime'] as Timestamp?;
        final actualTime = data['actualTime'] as Timestamp?;
        if (scheduledTime != null && actualTime != null) {
          final delay =
              actualTime.toDate().difference(scheduledTime.toDate()).inMinutes;
          if (delay > 0) {
            totalDelay += delay;
            delayCount++;
          }
          completedCount++;
        }
      }
      final incidentsSnapshot = await FirebaseFirestore.instance
          .collection('incidents')
          .where('regionId', isEqualTo: regionId)
          .where('status', isEqualTo: 'active')
          .get();
      final activePassengersSnapshot = await FirebaseFirestore.instance
          .collection('passengers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      setState(() {
        _activeDriversCount = driversSnapshot.docs.length;
        _totalVehicles = totalDriversSnapshot.docs.length;
        _totalPassengersCount = activePassengersSnapshot.docs.length;
        _completedServices = completedCount;
        _averageDelay = delayCount > 0 ? totalDelay / delayCount : 0.0;
        _incidentCount = incidentsSnapshot.docs.length;
      });
    } catch (e) {
      print('İstatistik yüklenirken hata: $e');
    }
  }
  Future<void> _loadSubRegionStatistics(String subRegionId) async {
    try {
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('subRegionId', isEqualTo: subRegionId)
          .where('isActive', isEqualTo: true)
          .get();
      final totalDriversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('subRegionId', isEqualTo: subRegionId)
          .get();
      final servicesSnapshot = await FirebaseFirestore.instance
          .collection('service_logs')
          .where('subRegionId', isEqualTo: subRegionId)
          .where('status', isEqualTo: 'completed')
          .get();
      double totalDelay = 0.0;
      int delayCount = 0;
      int completedCount = 0;
      for (final doc in servicesSnapshot.docs) {
        final data = doc.data();
        final scheduledTime = data['scheduledTime'] as Timestamp?;
        final actualTime = data['actualTime'] as Timestamp?;
        if (scheduledTime != null && actualTime != null) {
          final delay =
              actualTime.toDate().difference(scheduledTime.toDate()).inMinutes;
          if (delay > 0) {
            totalDelay += delay;
            delayCount++;
          }
          completedCount++;
        }
      }
      final incidentsSnapshot = await FirebaseFirestore.instance
          .collection('incidents')
          .where('subRegionId', isEqualTo: subRegionId)
          .where('status', isEqualTo: 'active')
          .get();
      final activePassengersSnapshot = await FirebaseFirestore.instance
          .collection('passengers')
          .where('subRegionId', isEqualTo: subRegionId)
          .where('isActive', isEqualTo: true)
          .get();
      setState(() {
        _activeDriversCount = driversSnapshot.docs.length;
        _totalVehicles = totalDriversSnapshot.docs.length;
        _totalPassengersCount = activePassengersSnapshot.docs.length;
        _completedServices = completedCount;
        _averageDelay = delayCount > 0 ? totalDelay / delayCount : 0.0;
        _incidentCount = incidentsSnapshot.docs.length;
      });
    } catch (e) {
      print('Alt bölge istatistik yüklenirken hata: $e');
    }
  }
  void _startTrackingRegion() {
    _driversSubscription?.cancel();
    _passengersSubscription?.cancel();
    _driversSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .where('regionId', isEqualTo: _selectedRegionId)
        .snapshots()
        .listen((snapshot) {
      _updateDriverMarkers(snapshot.docs);
    });
    _passengersSubscription = FirebaseFirestore.instance
        .collection('passengers')
        .where('regionId', isEqualTo: _selectedRegionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      _updatePassengerMarkers(snapshot.docs);
    });
  }
  void _startTrackingSubRegion() {
    _driversSubscription?.cancel();
    _passengersSubscription?.cancel();
    _driversSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .where('subRegionId', isEqualTo: _selectedSubRegionId)
        .snapshots()
        .listen((snapshot) {
      _updateDriverMarkers(snapshot.docs);
    });
    _passengersSubscription = FirebaseFirestore.instance
        .collection('passengers')
        .where('subRegionId', isEqualTo: _selectedSubRegionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      _updatePassengerMarkers(snapshot.docs);
    });
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
  Future<void> _debugRegionData() async {
    if (_selectedRegionId == null) return;
    try {
      final allPassengersSnapshot =
          await FirebaseFirestore.instance.collection('passengers').get();
      final regionPassengersSnapshot = await FirebaseFirestore.instance
          .collection('passengers')
          .where('regionId', isEqualTo: _selectedRegionId)
          .get();
      final activePassengersSnapshot = await FirebaseFirestore.instance
          .collection('passengers')
          .where('regionId', isEqualTo: _selectedRegionId)
          .where('isActive', isEqualTo: true)
          .get();
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('stops')
          .where('regionId', isEqualTo: _selectedRegionId)
          .get();
      String debugInfo = '''
🔍 DEBUG BİLGİSİ
📊 YOLCU VERİLERİ:
• Toplam Yolcu: ${allPassengersSnapshot.docs.length}
• Bölge ID'si Olan: ${regionPassengersSnapshot.docs.length}
• Aktif Yolcu: ${activePassengersSnapshot.docs.length}
📍 DURAK VERİLERİ:
• Bölge Durakları: ${stopsSnapshot.docs.length}
📋 ÖRNEK YOLCU VERİLERİ:
''';
      for (int i = 0;
          i < math.min(5, regionPassengersSnapshot.docs.length);
          i++) {
        final doc = regionPassengersSnapshot.docs[i];
        final data = doc.data();
        debugInfo += '''
• ${data['name'] ?? 'İsimsiz'}: 
  - regionId: ${data['regionId'] ?? 'YOK'}
  - isActive: ${data['isActive'] ?? 'YOK'}
  - stopLat: ${data['stopLat'] ?? 'YOK'}
  - stopLng: ${data['stopLng'] ?? 'YOK'}
''';
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Debug Bilgisi'),
            content: SingleChildScrollView(
              child: Text(debugInfo,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kapat'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debug hatası: $e')),
        );
      }
    }
  }
  void _updateDriverMarkers(List<QueryDocumentSnapshot> drivers) {
    final Set<Marker> newMarkers = {};
    int activeDrivers = 0;
    for (final doc in drivers) {
      final data = doc.data() as Map<String, dynamic>;
      final currentLat = data['currentLat'] as double?;
      final currentLng = data['currentLng'] as double?;
      final isActive = data['isActive'] as bool? ?? false;
      final name = data['name'] as String? ?? 'Bilinmeyen Şoför';
      final vehiclePlate = data['vehiclePlate'] as String? ?? '';
      final isLocationSharing = data['isLocationSharing'] as bool? ?? false;
      if (currentLat != null && currentLng != null && isLocationSharing) {
        activeDrivers++;
        newMarkers.add(
          Marker(
            markerId: MarkerId('driver_${doc.id}'),
            position: LatLng(currentLat, currentLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isActive ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueViolet,
            ),
            infoWindow: InfoWindow(
              title: '🚐 $name',
              snippet:
                  'Plaka: $vehiclePlate\nDurum: ${isActive ? "Aktif" : "Pasif"}',
            ),
          ),
        );
      }
    }
    final passengerMarkers = _markers
        .where((marker) => marker.markerId.value.startsWith('passenger_'))
        .toSet();
    setState(() {
      _markers = {...newMarkers, ...passengerMarkers};
      _activeDriversCount = activeDrivers;
    });
  }
  void _updatePassengerMarkers(List<QueryDocumentSnapshot> passengers) {
    final Set<Marker> newMarkers = {};
    int totalPassengers = passengers.length;
    int validPassengers = 0;
    print(
        '[RegionTracking] Yolcu güncelleniyor: ${passengers.length} yolcu bulundu');
    for (final doc in passengers) {
      final data = doc.data() as Map<String, dynamic>;
      double? stopLat = data['stopLat'] as double? ??
          data['latitude'] as double? ??
          data['lat'] as double?;
      double? stopLng = data['stopLng'] as double? ??
          data['longitude'] as double? ??
          data['lng'] as double?;
      final name = data['name'] as String? ?? 'Bilinmeyen Yolcu';
      final stopName = data['stopName'] as String? ??
          data['stop_name'] as String? ??
          'Bilinmeyen Durak';
      final isActive = data['isActive'] as bool? ??
          data['is_active'] as bool? ??
          data['status'] == 'active' ??
          true;
      if (isActive == true &&
          stopLat != null &&
          stopLng != null &&
          stopLat != 0.0 &&
          stopLng != 0.0 &&
          stopLat.abs() > 0.001 &&
          stopLng.abs() > 0.001) {
        validPassengers++;
        newMarkers.add(
          Marker(
            markerId: MarkerId('passenger_${doc.id}'),
            position: LatLng(stopLat, stopLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isActive ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: '👤 $name',
              snippet:
                  'Durak: $stopName\nDurum: ${isActive ? "Aktif" : "Pasif"}\nKoordinat: ${stopLat.toStringAsFixed(4)}, ${stopLng.toStringAsFixed(4)}',
            ),
          ),
        );
        print(
            '[RegionTracking] Geçerli yolcu eklendi: $name, Durak: $stopName');
      } else {
        print(
            '[RegionTracking] Filtrelenen yolcu: $name, Aktif: $isActive, Koordinatlar: ($stopLat, $stopLng)');
      }
    }
    print(
        '[RegionTracking] Toplam $totalPassengers yolcu, $validPassengers geçerli koordinat');
    final driverMarkers = _markers
        .where((marker) => marker.markerId.value.startsWith('driver_'))
        .toSet();
    setState(() {
      _markers = {...driverMarkers, ...newMarkers};
      _totalPassengersCount = validPassengers;
    });
    if (newMarkers.isNotEmpty && _mapController != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _centerMapOnRegionMarkers();
      });
    }
  }
  void _centerMapToRegion() async {
    if (_selectedRegionId != null && _mapController != null) {
      try {
        final regionDoc = await FirebaseFirestore.instance
            .collection('regions')
            .doc(_selectedRegionId)
            .get();
        if (regionDoc.exists) {
          final data = regionDoc.data()!;
          final lat = (data['centerLat'] as num?)?.toDouble();
          final lng = (data['centerLng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(lat, lng), 13),
            );
            return;
          }
        }
      } catch (e) {
      }
      _centerMapOnRegionMarkers();
    }
  }
  void _centerMapOnRegionMarkers() {
    if (_markers.isNotEmpty && _mapController != null) {
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;
      for (final marker in _markers) {
        final lat = marker.position.latitude;
        final lng = marker.position.longitude;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
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
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          if (_selectedRegionId != null) ...[
            IconButton(
              onPressed: _centerMapOnRegionMarkers,
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Haritayı Ortala',
            ),
            IconButton(
              onPressed: _debugRegionData,
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug Bilgisi',
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
                            hint: const Text(
                                'Ana bölgeyi seçin (İlçe/Kampüs/Tesis)'),
                            isExpanded: true,
                            items: [
                              ..._regions.map((region) {
                                final type = region['type'] ?? 'ilce';
                                final typeText = _getRegionTypeText(type);
                                return DropdownMenuItem<String>(
                                  value: region['id'],
                                  child: Row(
                                    children: [
                                      Icon(_getRegionTypeIcon(type), size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                            '${region['name']} ($typeText)'),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
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
                              hint: const Text(
                                  'Alt bölgeyi seçin (Mahalle/Organize Sanayi)'),
                              isExpanded: true,
                              items: [
                                ..._subRegions.map((subRegion) {
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
                              ],
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
                                'Ana bölge (İlçe/Kampüs/Tesis) seçerek\nalt bölge (Mahalle/Organize Sanayi) filtrelemesi\nyapabilir ve detaylı istatistikleri görebilirsiniz.',
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
                                'Bölge Katmanı: ${_getRegionTypeText(_regions.firstWhere((r) => r['id'] == _selectedRegionId)['type'] ?? 'ilce')}${_selectedSubRegionName != null ? ' > ${_getSubRegionTypeText(_subRegions.firstWhere((r) => r['id'] == _selectedSubRegionId)['type'] ?? 'mahalle')}' : ''}',
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
