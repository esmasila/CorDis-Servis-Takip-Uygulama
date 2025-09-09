import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../service/user_session.dart';
import 'dart:async';
class DistanceNotificationBar extends StatefulWidget {
  const DistanceNotificationBar({super.key});
  @override
  State<DistanceNotificationBar> createState() => _DistanceNotificationBarState();
}
class _DistanceNotificationBarState extends State<DistanceNotificationBar> {
  Timer? _checkTimer;
  bool _isVisible = false;
  double? _currentDistance;
  String? _stopName;
  bool _isChecking = false;
  double? _savedDistance;
  @override
  void initState() {
    super.initState();
    _loadSavedDistance();
    _startProximityCheck();
  }
  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
  Future<void> _loadSavedDistance() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId)
          .get();
      if (userDoc.exists && userDoc.data()?['distance'] != null) {
        setState(() {
          _savedDistance = (userDoc.data()!['distance']).toDouble();
        });
      } else {
        setState(() {
          _savedDistance = 1000;
        });
      }
    } catch (e) {
      setState(() {
        _savedDistance = 1000;
      });
    }
  }
  void _startProximityCheck() {
    _checkTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_isChecking || _savedDistance == null) return;
      await _checkProximity();
    });
  }
  Future<void> _checkProximity() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      Map<String, dynamic>? passengerData;
      try {
        final passengerDoc = await FirebaseFirestore.instance
            .collection('passengers')
            .doc(UserSession.userId)
            .get();
        if (passengerDoc.exists) {
          passengerData = passengerDoc.data()!;
        }
      } catch (e) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(UserSession.userId)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          passengerData = {
            'regionId': userData['regionId'],
            'stopLat': userData['stopLat'],
            'stopLng': userData['stopLng'],
            'stopName': userData['stopName'],
          };
        }
      }
      if (passengerData == null || 
          passengerData['stopLat'] == null || 
          passengerData['stopLng'] == null) {
        setState(() => _isChecking = false);
        return;
      }
      final stopLat = passengerData['stopLat'];
      final stopLng = passengerData['stopLng'];
      final stopName = passengerData['stopName'] ?? 'Durak';
      if (UserSession.regionId == null) {
        setState(() => _isChecking = false);
        return;
      }
      final driverQuery = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: UserSession.regionId)
          .where('isOnline', isEqualTo: true)
          .limit(1)
          .get();
      if (driverQuery.docs.isEmpty) {
        setState(() => _isChecking = false);
        return;
      }
      final driverData = driverQuery.docs.first.data();
      final driverLat = driverData['currentLat'];
      final driverLng = driverData['currentLng'];
      if (driverLat == null || driverLng == null) {
        setState(() => _isChecking = false);
        return;
      }
      final distance = Geolocator.distanceBetween(
        driverLat,
        driverLng,
        stopLat,
        stopLng,
      );
      if (distance <= _savedDistance!) {
        setState(() {
          _isVisible = true;
          _currentDistance = distance;
          _stopName = stopName;
        });
      } else {
        setState(() {
          _isVisible = false;
          _currentDistance = null;
          _stopName = null;
        });
      }
    } catch (e) {
    } finally {
      setState(() => _isChecking = false);
    }
  }
  void _dismissNotification() {
    setState(() {
      _isVisible = false;
      _currentDistance = null;
      _stopName = null;
    });
  }
  @override
  Widget build(BuildContext context) {
    if (!_isVisible || _currentDistance == null) {
      return const SizedBox.shrink();
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isVisible ? 60 : 0,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade600, Colors.green.shade700],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(context, '/distance_alert');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.directions_bus,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '🚍 Servisiniz yaklaştı!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '$_stopName durağına ${_currentDistance!.toInt()}m kaldı',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_currentDistance!.toInt()}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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



 Again


