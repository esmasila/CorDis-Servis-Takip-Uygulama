import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../service/location_service.dart';
import '../service/notification_service.dart';
import '../service/user_session.dart';
import '../service/firestore_service.dart';

class DistanceNotificationBar extends StatefulWidget {
  final String? driverId;
  final double alertDistance;
  final VoidCallback? onDriverApproaching;
  const DistanceNotificationBar({
    super.key,
    this.driverId,
    this.alertDistance = 500.0,
    this.onDriverApproaching,
  });
  @override
  State<DistanceNotificationBar> createState() =>
      _DistanceNotificationBarState();
}

class _DistanceNotificationBarState extends State<DistanceNotificationBar>
    with TickerProviderStateMixin {
  final LocationService _locationService = LocationService();
  final NotificationService _notificationService = NotificationService();
  Timer? _distanceCheckTimer;
  double? _currentDistance;
  Position? _driverPosition;
  Position? _passengerPosition;
  bool _isDriverApproaching = false;
  bool _hasNotifiedApproaching = false;
  String? _driverName;
  int? _estimatedArrivalMinutes;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startDistanceMonitoring();
    _loadDriverInfo();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _distanceCheckTimer?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadDriverInfo() async {
    if (widget.driverId == null) return;
    try {
      final driverDoc = await FirestoreService.getDriverById(widget.driverId!);
      if (driverDoc != null) {
        setState(() {
          _driverName = driverDoc.name ?? 'Şoför';
        });
      }
    } catch (e) {
      print('Şoför bilgisi yükleme hatası: $e');
    }
  }

  void _startDistanceMonitoring() {
    _distanceCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkDriverDistance(),
    );
  }

  Future<void> _checkDriverDistance() async {
    if (widget.driverId == null) return;
    try {
      _passengerPosition = await _locationService.getCurrentPosition();
      if (_passengerPosition == null) return;
      final driverData =
          await FirestoreService.getDriverLocation(widget.driverId!);
      if (driverData == null) return;
      final driverLat = driverData['latitude']?.toDouble();
      final driverLng = driverData['longitude']?.toDouble();
      if (driverLat == null || driverLng == null) return;
      _driverPosition = Position(
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
      final distance = Geolocator.distanceBetween(
        _passengerPosition!.latitude,
        _passengerPosition!.longitude,
        driverLat,
        driverLng,
      );
      setState(() {
        _currentDistance = distance;
        _estimatedArrivalMinutes = _calculateEstimatedArrival(distance);
      });
      if (distance <= widget.alertDistance && !_hasNotifiedApproaching) {
        _handleDriverApproaching();
      } else if (distance > widget.alertDistance && _isDriverApproaching) {
        _handleDriverMovingAway();
      }
    } catch (e) {
      print('Mesafe kontrolü hatası: $e');
    }
  }

  int _calculateEstimatedArrival(double distance) {
    const averageSpeed = 8.33;
    final timeInSeconds = distance / averageSpeed;
    return (timeInSeconds / 60).ceil();
  }

  void _handleDriverApproaching() {
    setState(() {
      _isDriverApproaching = true;
      _hasNotifiedApproaching = true;
    });
    _slideController.forward();
    widget.onDriverApproaching?.call();
    _notificationService.showLocalNotification(
      title: 'Servis Yaklaştı!',
      body:
          'Şoförünüz ${_currentDistance?.toInt() ?? 0}m mesafede. Hazır olun!',
    );
  }

  void _handleDriverMovingAway() {
    setState(() {
      _isDriverApproaching = false;
    });
    _slideController.reverse();
  }

  void _dismissNotification() {
    _slideController.reverse();
    setState(() {
      _isDriverApproaching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDriverApproaching || _currentDistance == null) {
      return const SizedBox.shrink();
    }
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade600,
              Colors.green.shade700,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🚍 Servisiniz Yaklaştı!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_driverName ?? 'Şoför'} ${_currentDistance!.toInt()}m mesafede',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (_estimatedArrivalMinutes != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Tahmini varış: ${_estimatedArrivalMinutes!} dakika',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_currentDistance!.toInt()}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _dismissNotification,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
