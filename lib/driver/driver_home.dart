import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import '../service/user_session.dart';
import '../service/background_location_service.dart';
import '../service/firestore_service.dart';
import '../utils/app_colors.dart';
import '../service/permission_service.dart';
import '../service/simple_stop_service.dart';
import '../models/permission_model.dart';
import '../view/login_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'enhanced_map_screen.dart';
import '../widget/top_notification.dart';
import '../service/chat_service.dart';
import '../models/message_model.dart';
import '../widget/common_loading_screen.dart';

class DriverHome extends StatefulWidget {
  final String driverId;
  final String vehiclePlate;
  final String region;
  const DriverHome({
    super.key,
    required this.driverId,
    required this.vehiclePlate,
    required this.region,
  });
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  int _selectedIndex = 0;
  String? _regionName;
  bool _isLocationSharing = false;
  Map<String, dynamic>? _activeRoute;
  List<Map<String, dynamic>> _todayStops = [];
  int _completedStops = 0;
  int _absentStops = 0;
  String? _activeRouteId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _routeSubscription;
  int _unreadMessageCount = 0;
  StreamSubscription? _messageCountSubscription;
  late final List<Widget> _screens;
  final List<String> _titles = [
    "Ana Sayfa",
    "Harita",
    "Mesajlar",
    "Profil",
  ];
  @override
  void initState() {
    super.initState();
    _loadRegionName();
    _checkLocationSharingStatus();
    _loadRouteInfo();
    _initializeMessageCountTracking();
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _checkLocationSharingStatus();
      } else {
        timer.cancel();
      }
    });
    _screens = [
      _buildHomeScreen(),
      EnhancedMapScreen(
        driverId: widget.driverId,
        vehiclePlate: widget.vehiclePlate,
        regionId: widget.region,
      ),
      _buildMessagesScreen(),
      const ProfileScreen(),
    ];
  }

  void _initializeMessageCountTracking() async {
    try {
      _messageCountSubscription =
          ChatService.getUnreadMessageCount(widget.driverId, widget.region)
              .listen((newCount) {
        if (!mounted) return;
        if (newCount != _unreadMessageCount) {
          setState(() {
            _unreadMessageCount = newCount;
          });
          print(
              '📱 Şoför - Okunmamış mesaj sayısı güncellendi: $_unreadMessageCount');
        }
      });
    } catch (e) {
      print('Şoför - Mesaj sayısı takip hatası: $e');
    }
  }

  void _markMessagesAsRead() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('messages')
          .where('regionId', isEqualTo: widget.region)
          .where('senderId', isNotEqualTo: widget.driverId)
          .where('isRead', isEqualTo: false)
          .get();
      if (query.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in query.docs) {
          batch.update(d.reference, {'isRead': true});
        }
        await batch.commit();
        print('✅ Şoför - ${query.docs.length} mesaj okundu olarak işaretlendi');
      }
      if (mounted) {
        setState(() {
          _unreadMessageCount = 0;
        });
        _messageCountSubscription?.cancel();
        _initializeMessageCountTracking();
      }
    } catch (e) {
      print('Şoför - Mesajları okundu olarak işaretleme hatası: $e');
    }
  }

  @override
  void dispose() {
    print(
        '🔄 DriverHome dispose - Konum paylaşımı background\'da devam ediyor');
    _routeSubscription?.cancel();
    _messageCountSubscription?.cancel();
    super.dispose();
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

  Future<void> _checkLocationSharingStatus() async {
    try {
      final previousStatus = _isLocationSharing;
      final currentStatus = UserSession.isLocationSharing;
      setState(() {
        _isLocationSharing = currentStatus;
      });
      if (previousStatus != currentStatus) {
        print(
            '🔄 DriverHome konum durumu değişti: $previousStatus -> $currentStatus');
        print(
            '📍 UserSession.isLocationSharing: ${UserSession.isLocationSharing}');
        print('🕐 Zaman: ${DateTime.now()}');
      } else {
        print('✅ DriverHome konum durumu sabit: $currentStatus');
      }
    } catch (e) {
      print('❌ Konum paylaşım durumu kontrol hatası: $e');
    }
  }

  Future<void> _restoreLocationSharingIfNeeded() async {
    try {
      print('🔄 Konum paylaşımı restore kontrolü başlatıldı');
      print(
          '📍 UserSession.isLocationSharing: ${UserSession.isLocationSharing}');
      print('🕐 Restore zamanı: ${DateTime.now()}');
      if (UserSession.isLocationSharing) {
        print(
            '✅ Önceki konum paylaşımı durumu tespit edildi, otomatik başlatılıyor...');
        print(
            '🚀 BackgroundLocationService.startLocationTracking() çağrılıyor...');
        await BackgroundLocationService.startLocationTracking();
        print('✅ BackgroundLocationService başlatıldı');
        print('📝 WorkManager görevleri kaydediliyor...');
        await _registerWorkManagerTasks();
        print('✅ WorkManager görevleri kaydedildi');
        if (mounted) {
          setState(() {
            _isLocationSharing = true;
          });
          print('🎨 UI güncellendi - _isLocationSharing: true');
        }
        print('🚀 Konum paylaşımı otomatik olarak restore edildi');
        print(
            '📍 Final UserSession.isLocationSharing: ${UserSession.isLocationSharing}');
      } else {
        print(
            'ℹ️ Önceki konum paylaşımı durumu bulunamadı - restore gerekmiyor');
      }
    } catch (e) {
      print('❌ Konum paylaşımı restore hatası: $e');
    }
  }

  Future<void> _shareLocationAndOpenMap(BuildContext context) async {
    try {
      print('🚀 Konum paylaşımı başlatılıyor ve harita açılıyor...');
      await BackgroundLocationService.startLocationTracking();
      await _registerWorkManagerTasks();
      await Future.delayed(Duration(milliseconds: 500));
      setState(() {
        _isLocationSharing = UserSession.isLocationSharing;
        _selectedIndex = 1;
      });
      print(
          '✅ Konum paylaşım durumu güncellendi: ${UserSession.isLocationSharing}');
      TopNotificationService.showSuccess(
        context: context,
        message: 'Konum paylaşımı başlatıldı - Harita açıldı',
      );
    } catch (e) {
      print('❌ Konum paylaşımı başlatma hatası: $e');
      TopNotificationService.showError(
        context: context,
        message: 'Konum paylaşımı başlatılamadı',
      );
    }
  }

  Future<void> _registerWorkManagerTasks() async {
    try {
      await Workmanager().registerPeriodicTask(
        "driver_location_update",
        "driverLocationTask",
        frequency: const Duration(minutes: 15),
        inputData: {
          'driverId': widget.driverId,
          'vehiclePlate': widget.vehiclePlate,
          'regionId': widget.region,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      await Workmanager().registerPeriodicTask(
        "stop_proximity_check",
        "stopProximityTask",
        frequency: const Duration(minutes: 5),
        inputData: {
          'driverId': widget.driverId,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      print('✅ WorkManager görevleri kaydedildi');
    } catch (e) {
      print('❌ WorkManager görev kaydetme hatası: $e');
    }
  }

  Future<void> _stopLocationSharing(BuildContext context) async {
    try {
      print('🛑 Manuel konum paylaşımı durdurma başlatıldı...');
      await BackgroundLocationService.forceStopLocationSharing();
      await _cancelWorkManagerTasks();
      setState(() {
        _isLocationSharing = UserSession.isLocationSharing;
      });
      print(
          '✅ Manuel konum paylaşımı durduruldu - Durum: ${UserSession.isLocationSharing}');
      TopNotificationService.showLocationStopped(context);
    } catch (e) {
      print('❌ Konum paylaşımı durdurma hatası: $e');
      TopNotificationService.showError(
        context: context,
        message: 'Konum paylaşımı durdurulamadı',
      );
    }
  }

  Future<void> _cancelWorkManagerTasks() async {
    try {
      await Workmanager().cancelByUniqueName("driver_location_update");
      await Workmanager().cancelByUniqueName("stop_proximity_check");
      print('✅ WorkManager görevleri iptal edildi');
    } catch (e) {
      print('❌ WorkManager görev iptal etme hatası: $e');
    }
  }

  Future<void> _loadRegionName() async {
    try {
      print('🔍 Bölge bilgisi yükleniyor - RegionId: ${widget.region}');
      if (mounted) {
        setState(() {
          _regionName = _getCleanRegionName(
              (UserSession.regionName?.isNotEmpty == true)
                  ? UserSession.regionName
                  : widget.region);
        });
      }
      final regionDoc = await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.region)
          .get();
      if (regionDoc.exists && mounted) {
        final regionData = regionDoc.data()!;
        print('✅ Bölge verisi bulundu: $regionData');
        setState(() {
          final dynamicName = regionData['name'] ??
              regionData['displayName'] ??
              regionData['title'] ??
              regionData['data'] ??
              UserSession.regionName ??
              widget.region;
          _regionName = _getCleanRegionName(dynamicName?.toString());
        });
      } else {
        print('⚠️ Bölge dokümanı bulunamadı, widget.region kullanılıyor');
      }
    } catch (e) {
      print('❌ Bölge adı yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _regionName =
              _getCleanRegionName(UserSession.regionName ?? widget.region);
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    if (_isLocationSharing) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Konum Paylaşımı Aktif'),
          content: const Text(
            'Konum paylaşımınız hala aktif. Çıkış yapmak istediğinizden emin misiniz?\n\n'
            'Not: Konum paylaşımı devam edecektir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Çıkış Yap'),
            ),
          ],
        ),
      );
      if (shouldContinue != true) return;
    }
    try {
      await FirebaseAuth.instance.signOut();
      UserSession.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Çıkış yapılırken hata: $e')));
      }
    }
  }

  PreferredSizeWidget _buildModernAppBar() {
    if (_selectedIndex == 0) {
      return AppBar(
          toolbarHeight: 0, elevation: 0, backgroundColor: Colors.transparent);
    }
    return AppBar(
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 56,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white.withOpacity(0.96),
              Colors.white.withOpacity(0.92),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedIndex = 0),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _titles[_selectedIndex],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isLocationSharing
                        ? AppColors.success.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: _isLocationSharing
                            ? AppColors.success
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isLocationSharing ? 'Aktif' : 'Pasif',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _isLocationSharing
                              ? AppColors.success
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      extendBodyBehindAppBar: false,
      appBar: _buildModernAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _selectedIndex,
                onTap: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white70,
                backgroundColor: AppColors.primary,
                elevation: 2,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.home_rounded, size: 22),
                    activeIcon: _buildNavActiveIcon(Icons.home_rounded),
                    label: 'Ana Sayfa',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.map_rounded, size: 22),
                    activeIcon: _buildNavActiveIcon(Icons.map_rounded),
                    label: 'Harita',
                  ),
                  BottomNavigationBarItem(
                    icon: _buildMessageIcon(),
                    activeIcon: _buildNavActiveIcon(Icons.chat_bubble_rounded),
                    label: 'Mesajlar',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.person_rounded, size: 22),
                    activeIcon: _buildNavActiveIcon(Icons.person_rounded),
                    label: 'Profil',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesScreen() {
    return MessagesScreen(
      driverId: widget.driverId,
      onScreenOpen: () {
        _markMessagesAsRead();
      },
    );
  }

  Widget _buildMessageIcon() {
    return Stack(
      children: [
        const Icon(Icons.chat_bubble_rounded, size: 22),
        if (_unreadMessageCount > 0)
          Positioned(
            right: -0.5,
            top: -0.5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.red.shade500,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.shade200.withOpacity(0.6),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNavActiveIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 22),
    );
  }

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withOpacity(0.85),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Merhaba 👋',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              UserSession.userName ?? 'Şoför',
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => _logout(context),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildDriverInfoCard(),
                  ],
                ),
              ),
            ),
          ),
          Container(
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withOpacity(0.3),
                  Colors.grey.shade50,
                ],
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade50,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  _buildRouteInfoCard(),
                  const SizedBox(height: 16),
                  _buildSmartRouteCard(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildAlertsCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Acil Mesajlar ve Notlar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<MessageModel>>(
            stream: ChatService.getUrgentMessagesForDriver(widget.driverId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: SimpleLoadingIndicator(
                  message: 'Mesajlar yükleniyor...',
                  size: 24,
                ));
              }
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                return Row(
                  children: [
                    Icon(Icons.inbox_rounded, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Text(
                      'Şu anda acil mesaj yok',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  for (final m in messages)
                    _buildAlertItem(
                      title: m.type == 'missed_alert'
                          ? 'Acil Uyarı'
                          : (m.senderRole == 'Yolcu'
                              ? 'Yolcudan Acil Mesaj'
                              : 'Acil Mesaj'),
                      message: m.content,
                      time: m.timestamp,
                      priority: 'high',
                      isRead: m.isRead,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem({
    required String title,
    required String message,
    DateTime? time,
    String priority = 'medium',
    bool isRead = false,
  }) {
    final Color stripeColor = priority == 'high'
        ? Colors.redAccent
        : priority == 'low'
            ? AppColors.success
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isRead ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 52,
            decoration: BoxDecoration(
              color: stripeColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Merhaba 👋',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          UserSession.userName ?? 'Şoför',
          style: const TextStyle(
            fontSize: 28,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfoCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.drive_eta_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Şoför Bilgileri',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildCleanInfoRow('🚗', 'Araç Plakası', widget.vehiclePlate),
            const SizedBox(height: 16),
            _buildCleanInfoRow('📍', 'Bölge', _getCleanRegionName(_regionName)),
            const SizedBox(height: 16),
            _buildCleanInfoRow(
              _isLocationSharing ? '🟢' : '🔴',
              'Konum Durumu',
              _isLocationSharing ? 'Aktif' : 'Pasif',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanInfoRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernInfoRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hızlı İşlemler',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildModernActionCard(
                Icons.map_rounded,
                'Haritayı Aç',
                '',
                AppColors.info,
                () => setState(() => _selectedIndex = 1),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernActionCard(
                Icons.chat_rounded,
                'Mesaj Gönder',
                '',
                AppColors.success,
                () => setState(() => _selectedIndex = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildModernActionCard(
                Icons.share_location_rounded,
                'Konum Paylaş',
                '',
                AppColors.secondary,
                () => _shareLocationAndOpenMap(context),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernActionCard(
                Icons.person_rounded,
                'Profil',
                '',
                AppColors.warningAccent,
                () => setState(() => _selectedIndex = 3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModernActionCard(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: color.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withOpacity(0.8),
                    color,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(String emoji, String title, String subtitle,
      LinearGradient gradient, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Günlük Özet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard('🕐', 'Çalışma', '8 saat', AppColors.info),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                  '🎯', 'Duraklar', '12 nokta', AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  _buildStatCard('⭐', 'Puan', '4.8/5', AppColors.warningAccent),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String emoji, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isLocationSharing
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.textLight.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isLocationSharing ? Icons.location_on : Icons.location_off,
              color: _isLocationSharing
                  ? AppColors.success
                  : AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLocationSharing
                      ? 'Konum Paylaşımı Aktif'
                      : 'Konum Paylaşımı Pasif',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLocationSharing
                      ? 'Konumunuz yolcularla paylaşılıyor'
                      : 'Konum paylaşımını başlatın',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRouteInfo() async {
    try {
      final activeRoute =
          await FirestoreService.getActiveRouteForDriver(widget.driverId);
      if (activeRoute != null) {
        final stops =
            List<Map<String, dynamic>>.from(activeRoute['stops'] ?? []);
        final completedCount =
            stops.where((stop) => stop['completed'] == true).length;
        final absentCount = stops.where((stop) {
          final status = stop['status'];
          final temporarilyInactive = stop['temporarilyInactive'] == true;
          return status == 'skipped' || temporarilyInactive == true;
        }).length;
        setState(() {
          _activeRoute = activeRoute;
          _todayStops = stops;
          _completedStops = completedCount;
          _absentStops = absentCount;
          _activeRouteId = activeRoute['id'] as String?;
        });
        if (_activeRouteId != null) {
          _listenActiveRoute(_activeRouteId!);
        }
      }
    } catch (e) {
      print('Rota bilgileri yüklenirken hata: $e');
    }
  }

  void _listenActiveRoute(String routeId) {
    _routeSubscription?.cancel();
    _routeSubscription = FirebaseFirestore.instance
        .collection('routes')
        .doc(routeId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final stops = List<Map<String, dynamic>>.from(data['stops'] ?? []);
      final completedCount =
          stops.where((stop) => stop['completed'] == true).length;
      final absentCount = stops.where((stop) {
        final status = stop['status'];
        final temporarilyInactive = stop['temporarilyInactive'] == true;
        return status == 'skipped' || temporarilyInactive == true;
      }).length;
      if (mounted) {
        setState(() {
          _activeRoute = {'id': routeId, ...data};
          _todayStops = stops;
          _completedStops = completedCount;
          _absentStops = absentCount;
        });
      }
    });
  }

  Widget _buildRouteInfoCard() {
    if (_activeRoute == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.route_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            FutureBuilder<Map<String, dynamic>?>(
              future: FirestoreService.getActiveRouteForDriver(widget.driverId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Text('Aktif rota kontrol ediliyor...');
                }
                if (snap.data == null) {
                  return Text(
                    'Henüz Aktif Rota Yok',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  );
                }
                return Text(
                  'Aktif rota bulundu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Rota oluşturmak için harita bölümünden\nyeni bir rota başlatabilirsiniz',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }
    final routeName = _activeRoute!['routeName'] ?? 'Rota';
    final totalStops = _todayStops.length;
    final remainingStops = totalStops - _completedStops;
    final progress = totalStops > 0 ? _completedStops / totalStops : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Günlük Rota',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      routeName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'İlerleme Durumu',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      '$_completedStops/$totalStops',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 1.0 ? AppColors.success : AppColors.primary,
                  ),
                  minHeight: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildRouteStatItem(
                  '🎯',
                  'Toplam Durak',
                  totalStops.toString(),
                  AppColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRouteStatItem(
                  '✅',
                  'Tamamlanan',
                  _completedStops.toString(),
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRouteStatItem(
                  '⏳',
                  'Kalan',
                  remainingStops.toString(),
                  AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRouteStatItem(
                  '🚫',
                  'Gelmeyen',
                  _absentStops.toString(),
                  AppColors.error,
                ),
              ),
            ],
          ),
          if (_todayStops.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildNextStopInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildSmartRouteCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            SimpleStopService.getStopsForDriver(widget.driverId),
            PermissionService.getTodayActivePermissionsFuture(widget.driverId),
          ]),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: SimpleLoadingIndicator(
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Akıllı Rota hazırlanıyor...',
                      style: TextStyle(color: Colors.white)),
                ],
              );
            }
            final List<Map<String, dynamic>> stops =
                List<Map<String, dynamic>>.from(snap.data![0] as List);
            final List<PermissionModel> todaysPermissions =
                List<PermissionModel>.from(snap.data![1] as List);
            final Set<String> fullDayAbsentPassengers = todaysPermissions
                .where((p) =>
                    p.type == PermissionType.allToday ||
                    (p.type == PermissionType.vacation &&
                        p.isValidForDate(DateTime.now())))
                .map((p) => p.userId)
                .toSet();
            final List<Map<String, dynamic>> smartStops = [];
            int totalComing = 0;
            for (final stop in stops) {
              final List<String> ids =
                  List<String>.from(stop['assignedPassengerIds'] ?? []);
              final List<String> names =
                  List<String>.from(stop['assignedPassengerNames'] ?? []);
              final List<String> addrs =
                  List<String>.from(stop['assignedAddresses'] ?? []);
              final double? lat = (stop['latitude'] ?? stop['lat'])?.toDouble();
              final double? lng =
                  (stop['longitude'] ?? stop['lng'])?.toDouble();
              final List<Map<String, String>> comingPassengers = [];
              for (int i = 0; i < ids.length; i++) {
                final pid = ids[i];
                if (!fullDayAbsentPassengers.contains(pid)) {
                  final n = i < names.length ? names[i] : 'Yolcu';
                  final a = i < addrs.length ? addrs[i] : '';
                  comingPassengers.add({'name': n, 'address': a});
                }
              }
              if (comingPassengers.isNotEmpty) {
                totalComing += comingPassengers.length;
                smartStops.add({
                  'id': stop['id'] ?? '',
                  'name': stop['name'] ??
                      (comingPassengers.first['address'] ?? 'Durak'),
                  'address': stop['address'] ??
                      (comingPassengers.first['address'] ?? ''),
                  'comingCount': comingPassengers.length,
                  'passengers': comingPassengers,
                  'latitude': lat,
                  'longitude': lng,
                });
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Akıllı Rota',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Toplam $totalComing kişi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (smartStops.isEmpty)
                  Text(
                    'Bugün işe gelecek yolcu bulunmuyor',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final s in smartStops.take(6))
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                                width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.place_rounded,
                                    color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (s['name'] as String?)?.isNotEmpty == true
                                          ? s['name']
                                          : 'Durak',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if ((s['address'] as String?)?.isNotEmpty ==
                                        true)
                                      Text(
                                        s['address'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.85),
                                          fontSize: 12,
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: -6,
                                      children: [
                                        for (final p in (s['passengers']
                                                as List<Map<String, String>>? ??
                                            []))
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.white
                                                      .withOpacity(0.2)),
                                            ),
                                            child: Text(
                                              p['name'] ?? 'Yolcu',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${s['comingCount']} kişi',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedIndex = 1);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Haritayı Aç'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedIndex = 1);
                              TopNotificationService.showInfo(
                                context: context,
                                message:
                                    'Akıllı rota için haritaya geçildi. Rota otomatik hesaplanacak.',
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Rotayı Oluştur'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRouteStatItem(
      String emoji, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNextStopInfo() {
    final nextStop = _todayStops.firstWhere(
      (stop) => stop['completed'] != true,
      orElse: () => {},
    );
    if (nextStop.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'Tüm duraklar tamamlandı! 🎉',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }
    final stopName = nextStop['name'] ?? 'Bilinmeyen Durak';
    final stopAddress = nextStop['address'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_on_rounded,
              color: AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            const Text(
              'Sonraki Durak',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stopName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (stopAddress.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  stopAddress,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon,
      [bool isWhite = false]) {
    return Row(
      children: [
        Icon(icon,
            color: isWhite ? Colors.white70 : AppColors.textSecondary,
            size: 20),
        const SizedBox(width: 12),
        Text('$label: ',
            style: TextStyle(
                fontSize: 15,
                color: isWhite ? Colors.white70 : AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isWhite ? Colors.white : AppColors.textPrimary)),
        ),
      ],
    );
  }
}

// Updated

