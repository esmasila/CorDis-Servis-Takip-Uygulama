import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/proximity_notification_service.dart';
import '../service/distance_notification_service.dart';
import '../service/location_service.dart';
import '../service/user_session.dart';
import '../service/enhanced_tracking_service.dart';
import 'dart:async';
class NotificationDebugScreen extends StatefulWidget {
  const NotificationDebugScreen({super.key});
  @override
  State<NotificationDebugScreen> createState() =>
      _NotificationDebugScreenState();
}
class _NotificationDebugScreenState extends State<NotificationDebugScreen> {
  bool _proximityServiceInitialized = false;
  bool _proximityServiceTracking = false;
  double _proximityDistance = 0.0;
  bool _distanceAlertActive = false;
  Position? _currentPosition;
  double? _distanceToDriver;
  String _driverStatus = 'Bilinmiyor';
  Map<String, dynamic>? _serviceStatus;
  bool _isLoading = true;
  Timer? _updateTimer;
  final LocationService _locationService = LocationService();
  final DistanceNotificationService _distanceService =
      DistanceNotificationService();
  @override
  void initState() {
    super.initState();
    _initializeDebugScreen();
    _startPeriodicUpdates();
  }
  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
  Future<void> _initializeDebugScreen() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _updateAllStatus();
    } catch (e) {
      debugPrint('Debug ekranı başlatma hatası: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  void _startPeriodicUpdates() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateAllStatus();
    });
  }
  Future<void> _updateAllStatus() async {
    try {
      _proximityServiceInitialized = ProximityNotificationService.isInitialized;
      _proximityServiceTracking = ProximityNotificationService.isTracking;
      final userId = UserSession.userId;
      if (userId != null) {
        _proximityDistance =
            await ProximityNotificationService.getNotificationDistance(userId);
        _distanceAlertActive =
            await _distanceService.isDistanceAlertActive(userId);
      }
      _currentPosition = await _locationService.getCurrentLocation();
      final regionId = UserSession.regionId;
      if (regionId != null && userId != null) {
        _serviceStatus =
            await EnhancedTrackingService.getServiceStatusForPassenger(
                userId, regionId);
        if (_serviceStatus != null &&
            _serviceStatus!['driverLocation'] != null) {
          final driverLat = _serviceStatus!['driverLocation']['latitude'];
          final driverLng = _serviceStatus!['driverLocation']['longitude'];
          final _ = Position(
            latitude: driverLat,
            longitude: driverLng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
          if (_currentPosition != null) {
            _distanceToDriver = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              driverLat,
              driverLng,
            );
          }
          _driverStatus = _serviceStatus!['status'] ?? 'Bilinmiyor';
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Durum güncelleme hatası: $e');
    }
  }
  Future<void> _testProximityNotification() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test bildirimi gönderiliyor...')),
      );
      await ProximityNotificationService.startProximityTracking(
        passengerId: UserSession.userId,
        driverId: UserSession.driverId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test bildirimi gönderildi!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test bildirimi hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  Future<void> _toggleProximityTracking() async {
    try {
      if (_proximityServiceTracking) {
        await ProximityNotificationService.stopProximityTracking();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yakınlık takibi durduruldu')),
        );
      } else {
        await ProximityNotificationService.startProximityTracking(
          passengerId: UserSession.userId,
          driverId: UserSession.driverId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yakınlık takibi başlatıldı')),
        );
      }
      await _updateAllStatus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yakınlık takibi hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  Future<void> _toggleDistanceAlert() async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return;
      if (_distanceAlertActive) {
        await _distanceService.disableDistanceAlert(userId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesafe uyarısı kapatıldı')),
        );
      } else {
        await _distanceService.enableDistanceAlert(userId, 1000.0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesafe uyarısı açıldı')),
        );
      }
      await _updateAllStatus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesafe uyarısı hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Debug Ekranı'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _updateAllStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _updateAllStatus,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildServiceStatusCard(),
                    const SizedBox(height: 16),
                    _buildLocationCard(),
                    const SizedBox(height: 16),
                    _buildNotificationServicesCard(),
                    const SizedBox(height: 16),
                    _buildTestButtonsCard(),
                    const SizedBox(height: 16),
                    _buildDebugInfoCard(),
                  ],
                ),
              ),
            ),
    );
  }
  Widget _buildServiceStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bus,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Servis Durumu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
                'Servis Aktif', _serviceStatus?['isActive'] ?? false),
            _buildStatusRow('Şoför Durumu', _driverStatus),
            if (_distanceToDriver != null)
              _buildStatusRow(
                  'Şoför Mesafesi', '${_distanceToDriver!.round()} metre'),
            if (_serviceStatus?['driverLocation'] != null)
              _buildStatusRow(
                  'Şoför Konumu',
                  '${_serviceStatus!['driverLocation']['latitude'].toStringAsFixed(4)}, '
                      '${_serviceStatus!['driverLocation']['longitude'].toStringAsFixed(4)}'),
          ],
        ),
      ),
    );
  }
  Widget _buildLocationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Konum Bilgileri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentPosition != null) ...[
              _buildStatusRow(
                  'Yolcu Konumu',
                  '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                      '${_currentPosition!.longitude.toStringAsFixed(4)}'),
              _buildStatusRow('Konum Doğruluğu',
                  '${_currentPosition!.accuracy.round()} metre'),
            ] else
              _buildStatusRow('Yolcu Konumu', 'Alınamadı'),
          ],
        ),
      ),
    );
  }
  Widget _buildNotificationServicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications,
                  color: Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Bildirim Servisleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
                'Proximity Service Başlatıldı', _proximityServiceInitialized),
            _buildStatusRow(
                'Proximity Service Takip', _proximityServiceTracking),
            _buildStatusRow(
                'Proximity Mesafesi', '${_proximityDistance.round()} metre'),
            _buildStatusRow('Distance Alert Aktif', _distanceAlertActive),
          ],
        ),
      ),
    );
  }
  Widget _buildTestButtonsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Test İşlemleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testProximityNotification,
                icon: const Icon(Icons.send),
                label: const Text('Test Bildirimi Gönder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleProximityTracking,
                icon: Icon(
                    _proximityServiceTracking ? Icons.stop : Icons.play_arrow),
                label: Text(_proximityServiceTracking
                    ? 'Yakınlık Takibini Durdur'
                    : 'Yakınlık Takibini Başlat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _proximityServiceTracking ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleDistanceAlert,
                icon: Icon(_distanceAlertActive
                    ? Icons.notifications_off
                    : Icons.notifications_on),
                label: Text(_distanceAlertActive
                    ? 'Mesafe Uyarısını Kapat'
                    : 'Mesafe Uyarısını Aç'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _distanceAlertActive ? Colors.orange : Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDebugInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Debug Bilgileri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow('User ID', UserSession.userId ?? 'Null'),
            _buildStatusRow('Region ID', UserSession.regionId ?? 'Null'),
            _buildStatusRow('Firebase User',
                FirebaseAuth.instance.currentUser?.uid ?? 'Null'),
            _buildStatusRow(
                'Son Güncelleme', DateTime.now().toString().substring(11, 19)),
          ],
        ),
      ),
    );
  }
  Widget _buildStatusRow(String label, dynamic value) {
    Color valueColor = Colors.black87;
    String displayValue = value.toString();
    if (value is bool) {
      valueColor = value ? Colors.green : Colors.red;
      displayValue = value ? 'Aktif' : 'Pasif';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



 Again


