import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/proximity_notification_service.dart';
import '../service/distance_notification_service.dart';
import 'dart:async';
class DistanceAlertScreen extends StatefulWidget {
  const DistanceAlertScreen({super.key});
  @override
  State<DistanceAlertScreen> createState() => _DistanceAlertScreenState();
}
class _DistanceAlertScreenState extends State<DistanceAlertScreen> {
  double _selectedDistance = 500.0;
  bool _loading = true;
  bool _isProximityTrackingActive = false;
  List<Map<String, dynamic>> _notificationHistory = [];
  String? _driverId;
  String? _driverName;
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }
  @override
  void dispose() {
    super.dispose();
  }
  Future<void> _initializeScreen() async {
    await ProximityNotificationService.initialize();
    await _loadDistance();
    await _loadDriverInfo();
    await _loadNotificationHistory();
    await _startProximityTracking();
  }
  Future<void> _loadDistance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final current =
          await ProximityNotificationService.getNotificationDistance(user.uid);
      setState(() {
        _selectedDistance = current;
      });
    } catch (e) {
      print('Mesafe yükleme hatası: $e');
      setState(() {
        _selectedDistance = 500.0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Mesafe bilgisi yüklenemedi, varsayılan değer kullanılıyor.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  Future<void> _loadDriverInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _driverId = userData['driverId'] as String?;
        final driverRef = _driverId;
        if (driverRef != null && driverRef.isNotEmpty) {
          final driverDoc = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverRef)
              .get();
          if (driverDoc.exists) {
            _driverName = driverDoc.data()?['name'] as String?;
          }
        }
      }
    } catch (e) {
      print('Şoför bilgisi yükleme hatası: $e');
    }
  }
  Future<void> _loadNotificationHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      setState(() {
        _notificationHistory = [];
      });
    } catch (e) {
      print('Bildirim geçmişi yükleme hatası: $e');
    }
  }
  Future<void> _startProximityTracking() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _driverId == null) {
        setState(() {
          _loading = false;
        });
        return;
      }
      await ProximityNotificationService.startProximityTracking();
      setState(() {
        _isProximityTrackingActive = true;
        _loading = false;
      });
    } catch (e) {
      print('Proximity tracking başlatma hatası: $e');
      setState(() {
        _loading = false;
      });
    }
  }
  Future<void> _saveDistance() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await ProximityNotificationService.updateNotificationDistance(
        _selectedDistance,
        passengerId: user.uid,
      );
      try {
        await DistanceNotificationService().enableDistanceAlert(
          user.uid,
          _selectedDistance,
        );
      } catch (_) {}
      if (_driverId != null) {
        await ProximityNotificationService.startProximityTracking(
          passengerId: user.uid,
          driverId: _driverId,
        );
      }
      await _loadNotificationHistory();
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedDistance.toInt()} metre mesafe ayarı kaydedildi.\n'
              '🔔 Uygulama kapalı olsa bile bildirim gelecek!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Yükleniyor...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blue.shade600,
                          Colors.blue.shade800,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Mesafe Uyarı Sistemi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Servis aracı belirlediğiniz mesafeye girdiğinde bildirim alacaksınız.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.straighten,
                                color: Colors.green.shade600),
                            const SizedBox(width: 8),
                            const Text(
                              'Uyarı Mesafesi',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_selectedDistance.toInt()} metre',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.green.shade600,
                            inactiveTrackColor: Colors.green.shade100,
                            thumbColor: Colors.green.shade600,
                            overlayColor: Colors.green.shade100,
                            valueIndicatorColor: Colors.green.shade600,
                          ),
                          child: Slider(
                            min: 100,
                            max: 5000,
                            divisions: 49,
                            value: _selectedDistance,
                            label: '${_selectedDistance.toInt()} m',
                            onChanged: (val) {
                              setState(() {
                                _selectedDistance = val;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '100m',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '5000m',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saveDistance,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text(
                              "Kaydet ve Şoföre Bildir",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.blue.shade600),
                            const SizedBox(width: 8),
                            const Text(
                              'Sistem Durumu',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildStatusItem(
                          'Kaydedilen Mesafe',
                          '${_selectedDistance.toInt()} metre',
                          Colors.green,
                          Icons.check_circle,
                        ),
                        _buildStatusItem(
                          'Takip Durumu',
                          _isProximityTrackingActive ? 'Aktif' : 'Pasif',
                          _isProximityTrackingActive
                              ? Colors.green
                              : Colors.red,
                          _isProximityTrackingActive
                              ? Icons.location_on
                              : Icons.location_off,
                        ),
                        if (_driverId != null)
                          _buildStatusItem(
                            'Şoför Bilgisi',
                            _driverName != null && _driverName!.isNotEmpty
                                ? 'Şoför: $_driverName'
                                : 'Bağlı: $_driverId',
                            Colors.green,
                            Icons.person,
                          ),
                        if (_notificationHistory.isNotEmpty)
                          _buildStatusItem(
                            'Son Bildirim',
                            '${_notificationHistory.length} bildirim gönderildi',
                            Colors.orange,
                            Icons.notifications_active,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline,
                                color: Colors.amber.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'İpuçları',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildTipItem(
                            '• Mesafe ne kadar küçükse, bildirim o kadar erken gelir'),
                        _buildTipItem(
                            '• Sistem otomatik olarak şoförün konumunu takip eder'),
                        _buildTipItem(
                            '• Bildirimler hem size hem şoföre gönderilir'),
                        _buildTipItem(
                            '• Uygulama kapalı olsa bile bildirim alırsınız'),
                        _buildTipItem(
                            '• Şoför konum paylaşımını açık tutmalıdır'),
                      ],
                    ),
                  ),
                  if (_notificationHistory.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade200,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history, color: Color(0xFF6366F1)),
                              const SizedBox(width: 8),
                              const Text(
                                'Bildirim Geçmişi',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ..._notificationHistory.take(5).map(
                                (notification) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Color(0xFFE0E7FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.notifications,
                                          color: Color(0xFF6366F1), size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notification['message'] ??
                                              'Bildirim gönderildi',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        notification['timestamp'] ?? '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
  Widget _buildStatusItem(
      String title, String value, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.amber.shade700,
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }
}

// Updated


// Updated Again

