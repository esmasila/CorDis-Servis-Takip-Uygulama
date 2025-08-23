import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../widget/snackbar.dart';
import '../service/stop_tracking_service.dart';
import '../utils/marker_color_helper.dart';
import '../models/stop_model.dart';
import '../models/region_model.dart';
class EnhancedLiveMapScreen extends StatefulWidget {
  const EnhancedLiveMapScreen({super.key});
  @override
  _EnhancedLiveMapScreenState createState() => _EnhancedLiveMapScreenState();
}
class _EnhancedLiveMapScreenState extends State<EnhancedLiveMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};
  final Set<Circle> _circles = <Circle>{};
  String? _selectedRegionId;
  String? _selectedDriverId;
  String? _selectedServiceId;
  String? _selectedVehicleType;
  String? _selectedShift;
  bool _showStops = true;
  bool _showRoutes = true;
  bool _showDrivers = true;
  bool _showOfflineDrivers = false;
  bool _onlyOnline = false;
  bool _isTrackingDriver = false;
  bool _autoRefresh = true;
  bool _enableClustering = true;
  StreamSubscription<QuerySnapshot>? _locationSub;
  StreamSubscription<QuerySnapshot>? _stopsSub;
  StreamSubscription<QuerySnapshot>? _routesSub;
  StreamSubscription<QuerySnapshot>? _permissionsSub;
  StreamSubscription<QuerySnapshot>? _servicesSub;
  StreamSubscription<QuerySnapshot>? _driversSub;
  Timer? _refreshTimer;
  List<RegionModel> _regions = [];
  Map<String, dynamic> _driverStats = {};
  Map<String, List<StopModel>> _regionStops = {};
  Map<String, dynamic> _services = {};
  Map<String, dynamic> _drivers = {};
  Map<String, dynamic> _vehicleData = {};
  Map<String, dynamic> _vehicleTypes = {
    'minibus': 'Minibüs',
    'bus': 'Otobüs',
    'van': 'Van',
    'car': 'Araba',
  };
  Map<String, dynamic> _shifts = {
    'morning': 'Sabah',
    'evening': 'Akşam',
    'night': 'Gece',
  };
  bool _isLoading = true;
  String _lastUpdateTime = '';
  DateTime _lastRefreshTime = DateTime.now();
  Map<String, List<Marker>> _clusteredMarkers = {};
  double _currentZoom = 11.0;
  @override
  void initState() {
    super.initState();
    _initializeEnhancedMap();
  }
  void _initializeEnhancedMap() {
    _loadServices();
    _loadDrivers();
    _listenServiceLocations();
    _startAutoRefresh();
    if (_showStops) _loadStops();
  }
  @override
  void dispose() {
    _locationSub?.cancel();
    _stopsSub?.cancel();
    _routesSub?.cancel();
    _permissionsSub?.cancel();
    _servicesSub?.cancel();
    _driversSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _listenServiceLocations();
        setState(() {
          _lastRefreshTime = DateTime.now();
        });
      }
    });
  }
  void _loadServices() {
    _servicesSub = FirebaseFirestore.instance
        .collection('services')
        .snapshots()
        .listen((snapshot) {
      final services = <String, dynamic>{};
      for (var doc in snapshot.docs) {
        services[doc.id] = doc.data();
      }
      if (mounted) {
        setState(() {
          _services = services;
        });
      }
    });
  }
  void _loadDrivers() {
    _driversSub = FirebaseFirestore.instance
        .collection('drivers')
        .snapshots()
        .listen((snapshot) {
      final drivers = <String, dynamic>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['vehiclePlate'] != null &&
            data['vehiclePlate'].toString().isNotEmpty) {
          drivers[doc.id] = data;
        }
      }
      if (mounted) {
        setState(() {
          _drivers = drivers;
        });
        print('📊 Sürücüler yüklendi: ${drivers.length} kayıtlı araç');
      }
    }, onError: (error) {
      print('❌ Sürücü yükleme hatası: $error');
      showSnackBar(
        text: 'Sürücü bilgileri yüklenirken hata: $error',
        backgroundColor: Colors.red.shade700,
      );
    });
  }
  void _listenServiceLocations() {
    Query query = FirebaseFirestore.instance.collection('live_locations');
    if (_selectedRegionId != null) {
      query = query.where('regionId', isEqualTo: _selectedRegionId);
    }
    if (_selectedServiceId != null) {
      query = query.where('serviceId', isEqualTo: _selectedServiceId);
    }
    if (_selectedDriverId != null) {
      query = query.where('driverId', isEqualTo: _selectedDriverId);
    }
    if (_selectedVehicleType != null) {
      query = query.where('vehicleType', isEqualTo: _selectedVehicleType);
    }
    if (_selectedShift != null) {
      query = query.where('shift', isEqualTo: _selectedShift);
    }
    _locationSub?.cancel();
    _locationSub = query.snapshots().listen(
      (snap) {
        final newMarkers = <Marker>{};
        for (var doc in snap.docs) {
          final data = doc.data()! as Map<String, dynamic>;
          final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['lng'] as num?)?.toDouble() ?? 0.0;
          if (lat != 0.0 && lng != 0.0) {
            final timestamp = data['timestamp'] as Timestamp?;
            final lastUpdate = timestamp?.toDate();
            final isOnline = lastUpdate != null &&
                DateTime.now().difference(lastUpdate).inMinutes < 5;
            if (_onlyOnline && !isOnline) continue;
            final vehicleStatus = _getVehicleStatus(data, lastUpdate);
            final markerColor = _getMarkerColorByStatus(vehicleStatus);
            _vehicleData[doc.id] = data;
            newMarkers.add(
              Marker(
                markerId: MarkerId('vehicle_${doc.id}'),
                position: LatLng(lat, lng),
                icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
                infoWindow: InfoWindow(
                  title: data['vehiclePlate'] ?? 'Araç',
                  snippet:
                      'Servis: ${_getServiceDisplayName(data['serviceId'])}\n'
                      'Şoför: ${_getDriverDisplayName(data['driverId'])}\n'
                      'Durum: ${_getStatusText(vehicleStatus)}\n'
                      'Son Güncelleme: ${lastUpdate != null ? _formatTimeAgo(lastUpdate) : '-'}',
                ),
                onTap: () => _showDriverDetails(doc.id, data),
              ),
            );
          }
        }
        if (mounted) {
          setState(() {
            _markers
              ..removeWhere(
                  (marker) => marker.markerId.value.startsWith('vehicle_'))
              ..addAll(newMarkers);
            _lastUpdateTime = _formatTimeAgo(_lastRefreshTime);
          });
          final activeVehicleCount = newMarkers.length;
          print('🚗 Aktif araç sayısı: $activeVehicleCount');
          print('📊 Toplam kayıtlı araç: ${_drivers.length}');
          if (_enableClustering) {
            _applyMarkerClustering();
          }
        }
      },
      onError: (error) {
        showSnackBar(
          text: 'Canlı harita yüklenirken hata: $error',
          backgroundColor: Colors.red.shade700,
        );
      },
    );
  }
  String _getVehicleStatus(Map<String, dynamic> data, DateTime? lastUpdate) {
    if (lastUpdate == null) return 'offline';
    final now = DateTime.now();
    final timeDiff = now.difference(lastUpdate).inMinutes;
    if (timeDiff > 5) return 'offline';
    final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
    final isInRoute = data['isInRoute'] ?? true;
    if (speed > 5) return 'moving';
    if (speed <= 5 && isInRoute) return 'waiting';
    if (!isInRoute) return 'off_route';
    return 'waiting';
  }
  double _getMarkerColorByStatus(String status) {
    switch (status) {
      case 'moving':
        return BitmapDescriptor.hueGreen;
      case 'waiting':
        return BitmapDescriptor.hueYellow;
      case 'off_route':
        return BitmapDescriptor.hueRed;
      case 'offline':
        return BitmapDescriptor.hueViolet;
      default:
        return BitmapDescriptor.hueBlue;
    }
  }
  Color _getStatusColor(String status) {
    switch (status) {
      case 'moving':
        return Colors.green;
      case 'waiting':
        return Colors.orange;
      case 'off_route':
        return Colors.red;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
  String _getStatusText(String status) {
    switch (status) {
      case 'moving':
        return 'Hareket Halinde';
      case 'waiting':
        return 'Beklemede';
      case 'off_route':
        return 'Rota Dışı';
      case 'offline':
        return 'Çevrimdışı';
      default:
        return 'Bilinmiyor';
    }
  }
  String _getServiceDisplayName(String? serviceId) {
    if (serviceId == null) return '-';
    final service = _services[serviceId];
    if (service == null) return serviceId;
    return service['name'] ??
        service['serviceName'] ??
        service['title'] ??
        serviceId;
  }
  String _getDriverDisplayName(String? driverId) {
    if (driverId == null) return '-';
    final driver = _drivers[driverId];
    if (driver == null) return driverId;
    return driver['name'] ??
        driver['driverName'] ??
        driver['fullName'] ??
        driver['firstName'] ??
        driverId;
  }
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inSeconds < 60) {
      return '⏱ ${difference.inSeconds} sn önce';
    } else if (difference.inMinutes < 60) {
      return '⏱ ${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return '⏱ ${difference.inHours} sa önce';
    } else {
      return '⏱ ${difference.inDays} gün önce';
    }
  }
  void _applyMarkerClustering() {
    if (_markers.length < 100)
      return;
    final vehicleMarkers =
        _markers.where((m) => !m.markerId.value.startsWith('stop_')).toList();
    if (vehicleMarkers.length < 100) return;
    final clusterRadius = _getClusterRadius(_currentZoom);
    final clusters = <String, List<Marker>>{};
    for (final marker in vehicleMarkers) {
      final clusterKey = _getClusterKey(marker.position, clusterRadius);
      clusters.putIfAbsent(clusterKey, () => []).add(marker);
    }
    final clusteredMarkers = <Marker>{};
    clusters.forEach((clusterKey, markers) {
      if (markers.length == 1) {
        clusteredMarkers.add(markers.first);
      } else {
        final center = _calculateClusterCenter(markers);
        final clusterMarker = Marker(
          markerId: MarkerId('cluster_$clusterKey'),
          position: center,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: '${markers.length} Araç',
            snippet: 'Detay için tıklayın',
          ),
          onTap: () => _showClusterDetails(markers, center),
        );
        clusteredMarkers.add(clusterMarker);
      }
    });
    final stopMarkers =
        _markers.where((m) => m.markerId.value.startsWith('stop_')).toSet();
    clusteredMarkers.addAll(stopMarkers);
    setState(() {
      _markers.clear();
      _markers.addAll(clusteredMarkers);
    });
  }
  String _getClusterKey(LatLng position, double radius) {
    final lat = (position.latitude / radius).round();
    final lng = (position.longitude / radius).round();
    return '${lat}_$lng';
  }
  double _getClusterRadius(double zoom) {
    if (zoom < 10) return 0.1;
    if (zoom < 12) return 0.05;
    if (zoom < 14) return 0.02;
    if (zoom < 16) return 0.01;
    return 0.005;
  }
  LatLng _calculateClusterCenter(List<Marker> markers) {
    double totalLat = 0;
    double totalLng = 0;
    for (final marker in markers) {
      totalLat += marker.position.latitude;
      totalLng += marker.position.longitude;
    }
    return LatLng(totalLat / markers.length, totalLng / markers.length);
  }
  void _showClusterDetails(List<Marker> markers, LatLng center) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.group_work, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Araç Grubu (${markers.length} Araç)',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: markers.length,
                  itemBuilder: (context, index) {
                    final marker = markers[index];
                    final data = _getMarkerData(marker.markerId.value);
                    if (data == null) return const SizedBox.shrink();
                    final vehicleStatus = _getVehicleStatus(
                        data,
                        data['timestamp'] != null
                            ? (data['timestamp'] as Timestamp).toDate()
                            : null);
                    final statusColor = _getStatusColor(vehicleStatus);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.1),
                        child: Icon(Icons.directions_car, color: statusColor),
                      ),
                      title: Text(data['vehiclePlate'] ?? 'Araç'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${_getServiceDisplayName(data['serviceId'])} • ${_getDriverDisplayName(data['driverId'])}'),
                          Text(
                            _getStatusText(vehicleStatus),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _focusOnMarker(marker);
                        },
                        icon: const Icon(Icons.center_focus_strong),
                        tooltip: 'Haritada Göster',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Map<String, dynamic>? _getMarkerData(String markerId) {
    try {
      final docId = markerId.replaceFirst('vehicle_', '');
      return _vehicleData[docId];
    } catch (e) {
      return null;
    }
  }
  void _focusOnMarker(Marker marker) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(marker.position, 16),
      );
    }
  }
  void _loadStops() {
    if (!_showStops) {
      setState(() {
        _markers
            .removeWhere((marker) => marker.markerId.value.startsWith('stop_'));
        _circles.clear();
      });
      return;
    }
    Query stopsQuery = FirebaseFirestore.instance
        .collection('enhanced_stops')
        .where('isActive', isEqualTo: true);
    if (_selectedRegionId != null) {
      stopsQuery = stopsQuery.where('regionId', isEqualTo: _selectedRegionId);
    }
    _stopsSub?.cancel();
    _stopsSub = stopsQuery.snapshots().listen((snapshot) {
      final stopMarkers = <Marker>{};
      final stopCircles = <Circle>{};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final markerColor = MarkerColorHelper.getMarkerColor(data);
          final hue = MarkerColorHelper.getMarkerHue(markerColor);
          final circleColor = MarkerColorHelper.getCircleColor(markerColor);
          stopMarkers.add(
            Marker(
              markerId: MarkerId('stop_${doc.id}'),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(hue),
              infoWindow: InfoWindow(
                title: data['name'] ?? 'Durak',
                snippet: 'Adres: ${data['address'] ?? 'Belirtilmemiş'}',
              ),
              onTap: () => _showStopTrackingDetails(doc.id, data),
            ),
          );
          stopCircles.add(
            Circle(
              circleId: CircleId('stop_circle_${doc.id}'),
              center: LatLng(lat, lng),
              radius: 100,
              fillColor: circleColor.withOpacity(0.2),
              strokeColor: circleColor,
              strokeWidth: 2,
            ),
          );
        }
      }
      if (mounted) {
        setState(() {
          _markers.removeWhere(
              (marker) => marker.markerId.value.startsWith('stop_'));
          _markers.addAll(stopMarkers);
          _circles.clear();
          _circles.addAll(stopCircles);
        });
      }
    });
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
      _centerMapToRegionMarkers();
    }
  }
  void _centerMapToRegionMarkers() {
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
  void _showDriverDetails(String driverId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Şoför Detayları',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Plaka', data['vehiclePlate'] ?? 'Belirtilmemiş'),
            _buildDetailRow('Servis ID', data['serviceId'] ?? 'Belirtilmemiş'),
            _buildDetailRow('Bölge ID', data['regionId'] ?? 'Belirtilmemiş'),
            _buildDetailRow('Hız', '${data['speed'] ?? 0} km/h'),
            _buildDetailRow('Yön', '${data['bearing'] ?? 0}°'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _trackDriver(driverId);
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Takip Et'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showRouteHistory(driverId);
                    },
                    icon: const Icon(Icons.route),
                    label: const Text('Rota Geçmişi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  void _showStopTrackingDetails(String stopId, Map<String, dynamic> stopData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Durak Takip Detayları',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              _buildDetailRow(
                  'Durak Adı', stopData['name'] ?? 'Bilinmeyen Durak'),
              _buildDetailRow('Adres', stopData['address'] ?? 'Belirtilmemiş'),
              _buildDetailRow('Yolcu Sayısı',
                  '${(stopData['passengerIds'] as List?)?.length ?? 0}'),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: StopTrackingService.getStopStatistics(
                    driverId: 'admin',
                    stopId: stopId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Hata: ${snapshot.error}',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      );
                    }
                    final stats = snapshot.data ?? {};
                    return SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bugünkü İstatistikler',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                          ),
                          const SizedBox(height: 12),
                          _buildStatsCard(
                            'Toplam Ziyaret',
                            '${stats['totalVisits'] ?? 0}',
                            Icons.location_on,
                            Colors.blue,
                          ),
                          _buildStatsCard(
                            'Tamamlanan Ziyaret',
                            '${stats['completedVisits'] ?? 0}',
                            Icons.check_circle,
                            Colors.green,
                          ),
                          _buildStatsCard(
                            'Ortalama Bekleme',
                            '${(stats['averageWaitTime'] ?? 0).toStringAsFixed(1)} dk',
                            Icons.timer,
                            Colors.orange,
                          ),
                          _buildStatsCard(
                            'Toplam Yolcu',
                            '${stats['totalPassengers'] ?? 0}',
                            Icons.people,
                            Color(0xFF6366F1),
                          ),
                          _buildStatsCard(
                            'Erken Varışlar',
                            '${stats['earlyArrivals'] ?? 0}',
                            Icons.schedule,
                            Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Son Ziyaretler',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: StopTrackingService.getDailyStopReport(
                              driverId:
                                  'admin',
                            ),
                            builder: (context, visitSnapshot) {
                              if (visitSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final visits = visitSnapshot.data ?? [];
                              if (visits.isEmpty) {
                                return const Center(
                                  child: Text('Bugün henüz ziyaret kaydı yok'),
                                );
                              }
                              return Column(
                                children: visits
                                    .map((visit) => _buildVisitCard(visit))
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildStatsCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  Widget _buildVisitCard(Map<String, dynamic> visit) {
    final arrivalTime = (visit['arrivalTime'] as Timestamp?)?.toDate();
    final departureTime = (visit['departureTime'] as Timestamp?)?.toDate();
    final waitTime = visit['waitTimeMinutes'] ?? 0;
    final passengerCount = visit['passengerCount'] ?? 0;
    final isEarly = visit['isEarlyArrival'] ?? false;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isEarly
              ? Colors.red.withOpacity(0.1)
              : Colors.green.withOpacity(0.1),
          child: Icon(
            isEarly ? Icons.schedule : Icons.check_circle,
            color: isEarly ? Colors.red : Colors.green,
          ),
        ),
        title: Text(
          arrivalTime != null
              ? 'Varış: ${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}'
              : 'Varış zamanı bilinmiyor',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (departureTime != null)
              Text(
                  'Ayrılış: ${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}'),
            Text('Bekleme: $waitTime dk • Yolcu: $passengerCount'),
            if (isEarly)
              Text(
                'Erken varış',
                style: TextStyle(
                    color: Colors.red.shade700, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  void _trackDriver(String driverId) {
    setState(() {
      _selectedDriverId = driverId;
      _isTrackingDriver = true;
    });
    FirebaseFirestore.instance
        .collection('live_locations')
        .doc(driverId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && _mapController != null) {
        final data = doc.data()!;
        final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (data['lng'] as num?)?.toDouble() ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
          );
        }
      }
    });
  }
  void _showRouteHistory(String driverId) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    FirebaseFirestore.instance
        .collection('location_history')
        .where('driverId', isEqualTo: driverId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(yesterday))
        .orderBy('timestamp')
        .get()
        .then((snapshot) {
      final points = <LatLng>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
      if (points.isNotEmpty) {
        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: PolylineId('route_$driverId'),
              points: points,
              color: Colors.red,
              width: 3,
            ),
          );
        });
        _fitPolylineInView(points);
      }
    });
  }
  void _fitPolylineInView(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }
  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
  Widget _buildAdvancedFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRegionFilter(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildServiceFilter(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDriverFilter(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildVehicleTypeFilter(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildShiftFilter(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          title: const Text('Sadece Çevrimiçi Araçlar'),
          subtitle: const Text('Çevrimdışı araçları gizle'),
          value: _onlyOnline,
          onChanged: (value) {
            setState(() {
              _onlyOnline = value;
            });
            _listenServiceLocations();
          },
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.update, color: Colors.green.shade700, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Son Güncelleme: $_lastUpdateTime',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildRegionFilter() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('regions')
          .orderBy('name')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          showSnackBar(
            text: 'Bölgeler yüklenirken hata: ${snap.error}',
            backgroundColor: Colors.red.shade700,
          );
          return const SizedBox.shrink();
        }
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Bölge',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          value: _selectedRegionId,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Tüm Bölgeler'),
            ),
            ...snap.data!.docs.map((doc) {
              final data = doc.data()! as Map<String, dynamic>;
              return DropdownMenuItem(
                value: doc.id,
                child: Text(data['name'] ?? '—'),
              );
            }),
          ],
          onChanged: (val) {
            setState(() {
              _selectedRegionId = val;
            });
            _listenServiceLocations();
            if (_showStops) _loadStops();
            if (val != null) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _centerMapToRegion();
              });
            }
          },
        );
      },
    );
  }
  Widget _buildServiceFilter() {
    if (_services.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Servis',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _selectedServiceId,
      isExpanded: true,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Tüm Servisler'),
        ),
        ..._services.entries.map((entry) {
          final serviceName = entry.value['name'] ??
              entry.value['serviceName'] ??
              entry.value['title'] ??
              entry.key;
          return DropdownMenuItem(
            value: entry.key,
            child: Text(serviceName),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          _selectedServiceId = val;
        });
        _listenServiceLocations();
      },
    );
  }
  Widget _buildDriverFilter() {
    if (_drivers.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Şoför',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _selectedDriverId,
      isExpanded: true,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Tüm Şoförler'),
        ),
        ..._drivers.entries.map((entry) {
          final driverName = entry.value['name'] ??
              entry.value['driverName'] ??
              entry.value['fullName'] ??
              entry.value['firstName'] ??
              entry.key;
          return DropdownMenuItem(
            value: entry.key,
            child: Text(driverName),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          _selectedDriverId = val;
        });
        _listenServiceLocations();
      },
    );
  }
  Widget _buildVehicleTypeFilter() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Araç Tipi',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _selectedVehicleType,
      isExpanded: true,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Tüm Araç Tipleri'),
        ),
        ..._vehicleTypes.entries.map((entry) {
          return DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          _selectedVehicleType = val;
        });
        _listenServiceLocations();
      },
    );
  }
  Widget _buildShiftFilter() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Vardiya',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _selectedShift,
      isExpanded: true,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Tüm Vardiyalar'),
        ),
        ..._shifts.entries.map((entry) {
          return DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          _selectedShift = val;
        });
        _listenServiceLocations();
      },
    );
  }
  void _clearAllFilters() {
    setState(() {
      _selectedRegionId = null;
      _selectedServiceId = null;
      _selectedDriverId = null;
      _selectedVehicleType = null;
      _selectedShift = null;
      _onlyOnline = false;
    });
    _listenServiceLocations();
    if (_showStops) _loadStops();
  }
  void _showMapOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Harita Seçenekleri',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Durakları Göster'),
                        subtitle: const Text('Aktif durakları haritada göster'),
                        value: _showStops,
                        onChanged: (value) {
                          setState(() {
                            _showStops = value;
                          });
                          _loadStops();
                          Navigator.pop(context);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Rotaları Göster'),
                        subtitle: const Text('Planlanan rotaları göster'),
                        value: _showRoutes,
                        onChanged: (value) {
                          setState(() {
                            _showRoutes = value;
                          });
                          Navigator.pop(context);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Sadece Çevrimiçi Araçlar'),
                        subtitle: const Text('Çevrimdışı araçları gizle'),
                        value: _onlyOnline,
                        onChanged: (value) {
                          setState(() {
                            _onlyOnline = value;
                          });
                          _listenServiceLocations();
                          Navigator.pop(context);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Marker Clustering'),
                        subtitle: const Text(
                            '100+ araçta performans için clustering'),
                        value: _enableClustering,
                        onChanged: (value) {
                          setState(() {
                            _enableClustering = value;
                          });
                          if (value) {
                            _applyMarkerClustering();
                          } else {
                            _listenServiceLocations();
                          }
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _clearTrackingAndRoutes();
                              },
                              icon: const Icon(Icons.clear),
                              label: const Text('Temizle'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _centerMapToCurrentLocation();
                              },
                              icon: const Icon(Icons.my_location),
                              label: const Text('Konumum'),
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
      ),
    );
  }
  void _clearTrackingAndRoutes() {
    setState(() {
      _polylines.clear();
      _isTrackingDriver = false;
      _selectedDriverId = null;
    });
  }
  void _centerMapToCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      showSnackBar(
        text: 'Konum alınamadı: $e',
        backgroundColor: Colors.red.shade700,
      );
    }
  }
  Widget _buildTopControlPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Canlı Harita',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            IconButton(
              onPressed: () => _showMapOptions(),
              icon: const Icon(Icons.settings),
              tooltip: 'Ayarlar',
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildBottomStatsPanel() {
    final vehicleMarkers = _markers
        .where((m) =>
            !m.markerId.value.startsWith('stop_') &&
            !m.markerId.value.startsWith('cluster_'))
        .length;
    final clusterMarkers =
        _markers.where((m) => m.markerId.value.startsWith('cluster_')).length;
    final stopMarkers =
        _markers.where((m) => m.markerId.value.startsWith('stop_')).length;
    final totalRegisteredVehicles = _drivers.length;
    final activeVehicles = vehicleMarkers;
    print(
        '📊 BottomStatsPanel - Toplam araç: $totalRegisteredVehicles, Aktif: $activeVehicles');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalRegisteredVehicles',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Toplam Araç',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$activeVehicles',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Aktif Araç',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$stopMarkers',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Durak',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_polylines.length}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Rota',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Clustering: ${_enableClustering ? "Açık" : "Kapalı"}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildRightControlPanel() {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: 'location',
          onPressed: _centerMapToCurrentLocation,
          backgroundColor: Colors.blue.shade600,
          child: const Icon(Icons.my_location, color: Colors.white),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'refresh',
          onPressed: () {
            _listenServiceLocations();
            if (_showStops) _loadStops();
            setState(() {
              _lastRefreshTime = DateTime.now();
            });
          },
          backgroundColor: Colors.green.shade600,
          child: const Icon(Icons.refresh, color: Colors.white),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'clustering',
          onPressed: () {
            setState(() {
              _enableClustering = !_enableClustering;
            });
            if (_enableClustering) {
              _applyMarkerClustering();
            } else {
              _listenServiceLocations();
            }
            showSnackBar(
              text:
                  'Marker Clustering ${_enableClustering ? "açıldı" : "kapatıldı"}',
              backgroundColor: _enableClustering
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
            );
          },
          backgroundColor:
              _enableClustering ? Colors.purple.shade600 : Colors.grey.shade600,
          child: Icon(
            _enableClustering ? Icons.group_work : Icons.group_work_outlined,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'filters',
          onPressed: () => _showAdvancedFiltersDialog(),
          backgroundColor: Colors.orange.shade600,
          child: const Icon(Icons.filter_list, color: Colors.white),
        ),
      ],
    );
  }
  void _showAdvancedFiltersDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_list,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtreler',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 4),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildAdvancedFilters(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _clearAllFilters();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Tüm Filtreleri Temizle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Uygula'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
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
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canlı Harita'),
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
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              setState(() {
                _isLoading = false;
              });
            },
            onCameraMove: (CameraPosition position) {
              if ((position.zoom - _currentZoom).abs() > 0.5) {
                _currentZoom = position.zoom;
                if (_enableClustering && _markers.length >= 100) {
                  _applyMarkerClustering();
                }
              }
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.9334, 32.8597),
              zoom: 11,
            ),
            markers: _markers,
            polylines: _polylines,
            circles: _circles,
            mapType: MapType.normal,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Canlı Harita Yükleniyor...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildTopControlPanel(),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildBottomStatsPanel(),
          ),
          Positioned(
            top: 76,
            right: 16,
            child: _buildRightControlPanel(),
          ),
        ],
      ),
    );
  }
}
