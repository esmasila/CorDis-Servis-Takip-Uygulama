import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/permission_service.dart';
import '../service/background_location_service.dart';
import '../service/user_session.dart';
import '../models/permission_model.dart';
import 'stops_screen.dart';
import '../widget/top_notification.dart';
import '../utils/app_colors.dart';
class HomeScreen extends StatefulWidget {
  final String driverId;
  final String vehiclePlate;
  final String region;
  const HomeScreen({
    super.key,
    required this.driverId,
    required this.vehiclePlate,
    required this.region,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  bool _isOnDuty = false;
  bool _isLocationSharing = false;
  String? _regionName;
  @override
  void initState() {
    super.initState();
    _loadDriverStatus();
    _loadRegionName();
    _checkLocationSharingStatus();
    _setupLocationSharingListener();
  }
  String _getCleanRegionName(String? regionName) {
    if (regionName == null || regionName.isEmpty) return 'Atanmamış';
    if (!regionName.contains('{') && !regionName.contains('"')) {
      return regionName;
    }
    try {
      final nameMatch =
          RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(regionName);
      if (nameMatch != null) {
        return nameMatch.group(1) ?? regionName;
      }
      final dataMatch =
          RegExp(r'"data"\s*:\s*"([^"]+)"').firstMatch(regionName);
      if (dataMatch != null) {
        return dataMatch.group(1) ?? regionName;
      }
      final valueMatch = RegExp(r'^"([^"]+)"$').firstMatch(regionName.trim());
      if (valueMatch != null) {
        return valueMatch.group(1) ?? regionName;
      }
      final cleanedText = regionName
          .replaceAll(RegExp(r'[{}"]'), '')
          .replaceAll(RegExp(r'[a-zA-Z0-9_]+\s*:\s*'), '')
          .replaceAll(RegExp(r',.*'), '')
          .replaceAll(RegExp(r'timestamp.*'), '')
          .replaceAll(RegExp(r'timeout.*'), '')
          .trim();
      if (cleanedText.isNotEmpty && cleanedText.length < 50) {
        return cleanedText;
      }
    } catch (_) {}
    return 'Bölge Bilgisi';
  }
  void _setupLocationSharingListener() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentStatus = UserSession.isLocationSharing;
      if (_isLocationSharing != currentStatus) {
        setState(() {
          _isLocationSharing = currentStatus;
        });
        print('[HomeScreen] Konum paylaşım durumu güncellendi: $currentStatus');
      }
    });
  }
  Future<void> _checkLocationSharingStatus() async {
    try {
      final isSharing = UserSession.isLocationSharing;
      final driverId = widget.driverId;
      final locationDoc = await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .get();
      bool firestoreStatus = false;
      if (locationDoc.exists) {
        firestoreStatus = locationDoc.data()?['isActive'] ?? false;
      }
      final actualStatus = isSharing || firestoreStatus;
      setState(() {
        _isLocationSharing = actualStatus;
      });
      print(
          'Ana sayfa konum durumu - UserSession: $isSharing, Firestore: $firestoreStatus, Final: $actualStatus');
    } catch (e) {
      print('Konum paylaşım durumu kontrol hatası: $e');
    }
  }
  Future<void> _toggleLocationSharing() async {
    try {
      if (_isLocationSharing) {
        print('🛑 Konum paylaşımı durduruluyor...');
        await _stopLocationSharing();
      } else {
        print('▶️ Konum paylaşımı başlatılıyor...');
        await _startLocationSharing();
      }
      await _checkLocationSharingStatus();
    } catch (e) {
      print('❌ Konum paylaşımı değiştirme hatası: $e');
      await _checkLocationSharingStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konum paylaşımı değiştirilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _stopLocationSharing() async {
    try {
      print('🛑 Ana sayfadan manuel konum paylaşımı durdurma başlatıldı...');
      await BackgroundLocationService.forceStopLocationSharing();
      final actualStatus = UserSession.isLocationSharing;
      if (mounted) {
        setState(() {
          _isLocationSharing = actualStatus;
        });
      }
      print(
          '✅ Ana sayfa manuel konum paylaşımı durduruldu - Durum: ${UserSession.isLocationSharing}');
      if (mounted) {
        TopNotificationService.showLocationStopped(context);
      }
    } catch (e) {
      print('❌ Konum paylaşımı durdurma hatası: $e');
      if (mounted) {
        TopNotificationService.showError(
          context: context,
          message: 'Konum paylaşımı durdurulamadı',
        );
      }
      rethrow;
    }
  }
  Future<void> _startLocationSharing() async {
    try {
      print('Ana sayfadan konum paylaşımı başlatılıyor...');
      await BackgroundLocationService.startLocationTracking();
      final actualStatus = UserSession.isLocationSharing;
      if (mounted) {
        setState(() {
          _isLocationSharing = actualStatus;
        });
      }
      if (mounted) {
        TopNotificationService.showLocationStarted(context);
      }
    } catch (e) {
      print('Konum paylaşımı başlatma hatası: $e');
      if (mounted) {
        TopNotificationService.showError(
          context: context,
          message: 'Konum paylaşımı başlatılamadı',
        );
      }
      rethrow;
    }
  }
  Future<void> _loadRegionName() async {
    try {
      final regionDoc = await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.region)
          .get();
      if (regionDoc.exists && mounted) {
        setState(() {
          _regionName =
              _getCleanRegionName(regionDoc.data()?['name'] ?? widget.region);
        });
      }
    } catch (e) {
      print('Bölge adı yüklenirken hata: $e');
      setState(() {
        _regionName = _getCleanRegionName(widget.region);
      });
    }
  }
  Future<void> _loadDriverStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.driverId)
          .get();
      if (doc.exists) {
        setState(() {
          _isOnDuty = doc.data()?['isOnDuty'] ?? false;
        });
      }
    } catch (e) {
      print('Şoför durumu yüklenirken hata: $e');
    }
  }
  Future<void> _toggleDutyStatus() async {
    try {
      final newStatus = !_isOnDuty;
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.driverId)
          .update({
        'isOnDuty': newStatus,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      setState(() {
        _isOnDuty = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? 'Görevde' : 'Görev dışı'),
          backgroundColor: newStatus ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Durum güncellenirken hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  Future<Map<String, dynamic>?> _getDriverInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driverId)
        .get();
    return doc.data();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Harita'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _getDriverInfo(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("Sürücü bilgileri bulunamadı."));
          }
          final driverData = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: driverData['photoUrl'] != null
                              ? NetworkImage(driverData['photoUrl'])
                              : null,
                          child: driverData['photoUrl'] == null
                              ? const Icon(Icons.person, size: 40)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          driverData['name'] ?? 'İsim Yok',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isOnDuty ? Icons.work : Icons.work_off,
                              color: _isOnDuty ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOnDuty ? 'Görevde' : 'Görev Dışı',
                              style: TextStyle(
                                fontSize: 16,
                                color: _isOnDuty ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow('Telefon', driverData['phone'] ?? 'Yok'),
                        _buildInfoRow('Plaka', widget.vehiclePlate),
                        _buildInfoRow(
                            'Bölge',
                            _regionName ??
                                'Yükleniyor...'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        elevation: 8,
                        shadowColor: _isOnDuty
                            ? Colors.green.withOpacity(0.3)
                            : Colors.orange.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _toggleDutyStatus,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _isOnDuty
                                    ? [
                                        Colors.orange.shade400,
                                        Colors.orange.shade600
                                      ]
                                    : [
                                        Colors.green.shade400,
                                        Colors.green.shade600
                                      ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _isOnDuty ? Icons.work_off : Icons.work,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _isOnDuty
                                      ? 'Görev\nDışına Çık'
                                      : 'Göreve\nBaşla',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _isLocationSharing
                                  ? Colors.red.withOpacity(0.2)
                                  : Colors.green.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _toggleLocationSharing,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              decoration: BoxDecoration(
                                color: _isLocationSharing
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _isLocationSharing
                                      ? Colors.red.shade200
                                      : Colors.green.shade200,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _isLocationSharing
                                          ? Colors.red.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _isLocationSharing
                                          ? Icons.location_off_rounded
                                          : Icons.location_on_rounded,
                                      color: _isLocationSharing
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _isLocationSharing
                                              ? 'Konum Paylaşımı Aktif'
                                              : 'Konum Paylaşımı Pasif',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _isLocationSharing
                                                ? Colors.red.shade800
                                                : Colors.green.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _isLocationSharing
                                              ? 'Konumunuz yolcularla paylaşılıyor'
                                              : 'Konum paylaşımını başlatmak için dokunun',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _isLocationSharing
                                                ? Colors.red.shade600
                                                : Colors.green.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isLocationSharing
                                          ? Colors.red.shade600
                                          : Colors.green.shade600,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _isLocationSharing ? 'DURDUR' : 'BAŞLAT',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 8,
                  shadowColor: AppColors.primary.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StopsScreen()),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.map,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Bugünkü Duraklar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bugünkü İzinler',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<PermissionModel>>(
                          stream: PermissionService.getTodayActivePermissions(
                              widget.driverId),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text(
                                'Bugün için aktif izin bulunmuyor.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            }
                            return Column(
                              children: snapshot.data!.map((permission) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: Icon(
                                      _getPermissionIcon(permission.type),
                                      color:
                                          _getPermissionColor(permission.type),
                                    ),
                                    title: Text(permission.userName),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_getPermissionTypeText(
                                            permission.type)),
                                        if (permission.reason != null &&
                                            permission.reason!.isNotEmpty)
                                          Text(
                                            'Sebep: ${permission.reason}',
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                      ],
                                    ),
                                    trailing: Text(
                                      _formatPermissionDate(permission),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }
  IconData _getPermissionIcon(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.morningTomorrow:
        return Icons.wb_sunny;
      case PermissionType.eveningToday:
        return Icons.nights_stay;
      case PermissionType.allToday:
      case PermissionType.allTomorrow:
        return Icons.event_busy;
      case PermissionType.vacation:
        return Icons.beach_access;
    }
  }
  Color _getPermissionColor(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.morningTomorrow:
        return Colors.orange;
      case PermissionType.eveningToday:
        return Colors.indigo;
      case PermissionType.allToday:
      case PermissionType.allTomorrow:
        return Colors.red;
      case PermissionType.vacation:
        return Colors.green;
    }
  }
  String _getPermissionTypeText(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
        return 'Bugün Sabah Yok';
      case PermissionType.morningTomorrow:
        return 'Yarın Sabah Yok';
      case PermissionType.eveningToday:
        return 'Bugün Akşam Yok';
      case PermissionType.allToday:
        return 'Bugün Gelmeyecek';
      case PermissionType.allTomorrow:
        return 'Yarın Gelmeyecek';
      case PermissionType.vacation:
        return 'Tatil';
    }
  }
  String _formatPermissionDate(PermissionModel permission) {
    if (permission.type == PermissionType.vacation) {
      return '${permission.startDate.day}/${permission.startDate.month} - ${permission.endDate!.day}/${permission.endDate!.month}';
    } else {
      return '${permission.startDate.day}/${permission.startDate.month}/${permission.startDate.year}';
    }
  }
}
