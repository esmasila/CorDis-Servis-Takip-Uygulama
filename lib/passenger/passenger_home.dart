import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/user_session.dart';
import '../utils/app_colors.dart';
import '../view/login_screen.dart';
import 'profile_screen.dart';
import 'permission_screen.dart';
import 'distance_alert.dart';
import 'enhanced_service_tracking.dart';
import 'chat_screen.dart';
import 'notification_debug_screen.dart';
import '../service/cache_service.dart';
import '../widget/common_loading_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../service/geocoding_service.dart';
import '../service/arrival_time_service.dart';
import '../service/proximity_notification_service.dart';
import '../service/eta_calculation_service.dart';
import '../service/chat_service.dart';

class PassengerHome extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String? regionId;
  final String? regionName;
  final String? driverId;
  const PassengerHome({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.regionId,
    this.regionName,
    this.driverId,
  });
  @override
  State<PassengerHome> createState() => _PassengerHomeState();
}

class _PassengerHomeState extends State<PassengerHome> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _driverName;
  String? _vehiclePlate;
  String? _driverPhotoUrl;
  String? _userAddress;
  String? _shortRegionName;
  Map<String, dynamic>? _arrivalTimeData;
  bool _isDriverActive = false;
  StreamSubscription? _arrivalTimeSubscription;
  double _notificationDistance = 1.0;
  bool _isProximityTrackingActive = false;
  ETACalculationService? _etaCalculationService;
  StreamSubscription? _etaSubscription;
  ETAData? _enhancedETAData;
  bool _isTestModeEnabled = false;
  int _unreadMessageCount = 0;
  StreamSubscription? _messageCountSubscription;
  @override
  void initState() {
    super.initState();
    _syncFromUserSession();
    _loadPassengerData();
    _startArrivalTimeTracking();
    _initializeProximityNotifications();
    _initializeETACalculationService();
    _initializeMessageCountTracking();
    Future.microtask(() {
      try {
        final flag =
            CacheService.getCache<bool>('passenger_test_mode') ?? false;
        if (mounted) {
          setState(() => _isTestModeEnabled = flag);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _arrivalTimeSubscription?.cancel();
    _etaSubscription?.cancel();
    _messageCountSubscription?.cancel();
    ETACalculationService.dispose();
    ProximityNotificationService.dispose();
    super.dispose();
  }

  void _initializeProximityNotifications() async {
    await ProximityNotificationService.initialize();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _notificationDistance =
          await ProximityNotificationService.getNotificationDistance(user.uid);
      final String? driverId = widget.driverId ?? UserSession.driverId;
      if (driverId != null && driverId.isNotEmpty) {
        await ProximityNotificationService.startProximityTracking(
          passengerId: user.uid,
          driverId: driverId,
        );
        _isProximityTrackingActive = true;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _updateNotificationDistance(double newDistance) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await ProximityNotificationService.updateNotificationDistance(
      newDistance,
      passengerId: user.uid,
    );
    if (widget.driverId != null) {
      await ProximityNotificationService.startProximityTracking(
        passengerId: user.uid,
        driverId: widget.driverId!,
      );
    }
    setState(() {
      _notificationDistance = newDistance;
    });
  }

  void _startArrivalTimeTracking() async {
    final String? driverId = widget.driverId ?? UserSession.driverId;
    print('🔍 PassengerHome: _startArrivalTimeTracking başladı');
    print('   - DriverId: $driverId');
    print('   - Widget DriverId: ${widget.driverId}');
    print('   - UserSession DriverId: ${UserSession.driverId}');

    if (driverId == null || driverId.isEmpty) {
      print('❌ PassengerHome: DriverId bulunamadı, tracking başlatılamadı');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ PassengerHome: Kullanıcı bulunamadı');
      return;
    }

    print('👤 PassengerHome: Kullanıcı ID: ${user.uid}');

    _isDriverActive = await ArrivalTimeService.isDriverActive(driverId);
    print('🚗 PassengerHome: Şoför aktif mi: $_isDriverActive');

    if (_isDriverActive) {
      print('✅ PassengerHome: ArrivalTimeService stream başlatılıyor');
      _arrivalTimeSubscription = ArrivalTimeService.getArrivalTimeStream(
        passengerId: user.uid,
        driverId: driverId,
      ).listen((data) {
        print('📡 PassengerHome: ArrivalTimeService verisi alındı: $data');
        if (mounted) {
          setState(() {
            _arrivalTimeData = data;
          });
          print('✅ PassengerHome: _arrivalTimeData güncellendi');

          _loadStopInformation();
        }
      }, onError: (error) {
        print('❌ PassengerHome: ArrivalTimeService stream hatası: $error');
      });
    } else {
      print('⚠️ PassengerHome: Şoför aktif değil, manuel veri çekme deneniyor');
      try {
        final data = await ArrivalTimeService.calculateArrivalTime(
          passengerId: user.uid,
          driverId: driverId,
        );
        print('📡 PassengerHome: Manuel veri çekildi: $data');
        if (mounted && data != null) {
          setState(() {
            _arrivalTimeData = data;
          });
          print('✅ PassengerHome: Manuel _arrivalTimeData güncellendi');

          _loadStopInformation();
        }
      } catch (e) {
        print('❌ PassengerHome: Manuel veri çekme hatası: $e');
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _initializeMessageCountTracking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final String? regionId = widget.regionId ?? UserSession.regionId;
      if (regionId == null || regionId.isEmpty) return;
      _messageCountSubscription =
          ChatService.getUnreadMessageCount(user.uid, regionId)
              .listen((newCount) {
        if (!mounted) return;
        if (newCount != _unreadMessageCount) {
          setState(() {
            _unreadMessageCount = newCount;
          });
          print('📱 Okunmamış mesaj sayısı güncellendi: $_unreadMessageCount');
        }
      });
    } catch (e) {
      print('Mesaj sayısı takip hatası: $e');
    }
  }

  void _markMessagesAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _unreadMessageCount == 0) return;
    try {
      final String? regionId = widget.regionId ?? UserSession.regionId;
      if (regionId == null || regionId.isEmpty) return;
      final query = await FirebaseFirestore.instance
          .collection('messages')
          .where('regionId', isEqualTo: regionId)
          .where('senderId', isNotEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .get();
      if (query.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in query.docs) {
          batch.update(d.reference, {'isRead': true});
        }
        await batch.commit();
        print('✅ ${query.docs.length} mesaj okundu olarak işaretlendi');
      }
      if (mounted) {
        setState(() {
          _unreadMessageCount = 0;
        });
        _messageCountSubscription?.cancel();
        _initializeMessageCountTracking();
      }
    } catch (e) {
      print('Mesajları okundu olarak işaretleme hatası: $e');
    }
  }

  void _initializeETACalculationService() async {
    final user = FirebaseAuth.instance.currentUser;
    final String? driverId = widget.driverId ?? UserSession.driverId;
    if (user == null || driverId == null || driverId.isEmpty) return;
    try {
      _etaCalculationService = ETACalculationService();
      await ETACalculationService.initialize(
        passengerId: user.uid,
        driverId: driverId,
      );
      _etaSubscription = ETACalculationService.getPassengerETAStream(user.uid)
          .listen((etaData) {
        if (mounted) {
          setState(() {
            _enhancedETAData = etaData;
          });
        }
      });
    } catch (e) {
      print('ETA Calculation Service başlatma hatası: $e');
    }
  }

  Future<void> _loadStopInformation() async {
    try {
      print('🔍 PassengerHome: Durak bilgileri yükleniyor...');

      final String? driverId = widget.driverId ?? UserSession.driverId;
      if (driverId == null || driverId.isEmpty) {
        print('⚠️ PassengerHome: DriverId bulunamadı');
        return;
      }

      final stopsQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();

      print('📊 PassengerHome: ${stopsQuery.docs.length} durak bulundu');

      if (stopsQuery.docs.isNotEmpty) {
        final totalStops = stopsQuery.docs.length;
        final completedStops = stopsQuery.docs
            .where((doc) => doc.data()['isCompleted'] == true)
            .length;

        print(
            '📊 PassengerHome: Toplam: $totalStops, Tamamlanan: $completedStops');

        if (_arrivalTimeData != null) {
          setState(() {
            _arrivalTimeData = {
              ..._arrivalTimeData!,
              'totalStopsCount': totalStops,
              'currentStopIndex': _arrivalTimeData!['currentStopIndex'] ?? 1,
            };
          });
          print(
              '✅ PassengerHome: ETA verileri güncellendi - totalStops: $totalStops');
        }
      }
    } catch (e) {
      print('❌ PassengerHome: Durak bilgileri yükleme hatası: $e');
    }
  }

  void _syncFromUserSession() {
    try {
      if (UserSession.driverId != null && UserSession.driverId!.isNotEmpty) {
        _isDriverActive = false;
      }
      setState(() {});
    } catch (_) {}
  }

  Future<void> _loadPassengerData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        setState(() {
          _userAddress = userData['address'];
        });
        final String? userDriverId = userData['driverId'] as String?;
        final String? userRegionId =
            widget.regionId ?? userData['regionId'] as String?;
        String? effectiveDriverId = UserSession.driverId ?? userDriverId;
        if ((effectiveDriverId == null || effectiveDriverId.isEmpty) &&
            userRegionId != null &&
            userRegionId.isNotEmpty) {
          try {
            final driverQuery = await FirebaseFirestore.instance
                .collection('drivers')
                .where('regionId', isEqualTo: userRegionId)
                .where('isActive', isEqualTo: true)
                .limit(1)
                .get();
            if (driverQuery.docs.isNotEmpty) {
              effectiveDriverId = driverQuery.docs.first.id;
              final driverData = driverQuery.docs.first.data();
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.userId)
                  .update({'driverId': effectiveDriverId});
              UserSession.driverId = effectiveDriverId;
              try {
                final userDriverDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(effectiveDriverId)
                    .get();
                if (!userDriverDoc.exists) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(effectiveDriverId)
                      .set({
                    'name': driverData['name'] ?? 'Bilinmeyen Şoför',
                    'role': 'Şoför',
                    'regionId': userRegionId,
                    'vehiclePlate': driverData['vehiclePlate'] ?? 'Plaka Yok',
                    'isActive': true,
                  }, SetOptions(merge: true));
                  print(
                      '✅ PassengerHome: Şoför users koleksiyonuna da eklendi: $effectiveDriverId');
                }
              } catch (e) {
                print(
                    '⚠️ PassengerHome: Şoför users koleksiyonuna eklenemedi: $e');
              }
              print(
                  '✅ PassengerHome: DriverId otomatik olarak bulundu ve set edildi: $effectiveDriverId');
              print('- RegionId: $userRegionId');
              print('- DriverId: $effectiveDriverId');
            } else {
              print(
                  '⚠️ PassengerHome: Bölgede aktif şoför bulunamadı: $userRegionId');
            }
          } catch (e) {
            print('❌ PassengerHome: Şoför bulma hatası: $e');
          }
        }
        if (effectiveDriverId != null && effectiveDriverId.isNotEmpty) {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(effectiveDriverId)
                .get();
            if (driverDoc.exists) {
              final driver = driverDoc.data()!;
              setState(() {
                _driverName = driver['name'] ?? 'Bilinmeyen Şoför';
                _vehiclePlate = driver['vehiclePlate'] ?? 'Plaka Yok';
                _driverPhotoUrl = driver['photoUrl'];
              });
              UserSession.driverName = _driverName;
              UserSession.vehiclePlate = _vehiclePlate;
            }
          } catch (_) {}
        }
      }
      if (widget.regionName != null) {
        _shortRegionName = _shortenRegionName(widget.regionName!);
      }
    } catch (e) {
      print('Yolcu verisi yükleme hatası: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _shortenRegionName(String regionName) {
    if (regionName.contains(' ')) {
      return regionName.split(' ')[0];
    }
    return regionName;
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Hoşgeldin, ${widget.userName.split(' ')[0]}';
      case 1:
        return 'Takip';
      case 2:
        return 'Mesajlar';
      case 3:
        return 'İzinler';
      case 4:
        return 'Mesafe Ayarları';
      case 5:
        return 'Profil';
      default:
        return 'CORDİS';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: SimpleLoadingIndicator(
            message: 'Yükleniyor...',
            size: 48,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _selectedIndex == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hoşgeldin, ${widget.userName.split(' ')[0]}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Günün güzel geçsin!',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Text(
                _getAppBarTitle(),
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w600),
              ),
        backgroundColor: AppColors.background,
        foregroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
        actionsIconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
        centerTitle: _selectedIndex != 0,
        surfaceTintColor: Colors.transparent,
        leading: _selectedIndex != 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  setState(() {
                    _selectedIndex = 0;
                  });
                },
                tooltip: 'Ana Sayfaya Dön',
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _signOut,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeScreen(),
          _buildTrackingScreen(),
          _buildMessagesScreen(),
          _buildPermissionsScreen(),
          _buildDistanceScreen(),
          _buildProfileScreen(),
        ],
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
                selectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.home_rounded, size: 22),
                    activeIcon: _buildNavActiveIcon(Icons.home_rounded),
                    label: 'Ana Sayfa',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.directions_bus_rounded, size: 22),
                    activeIcon:
                        _buildNavActiveIcon(Icons.directions_bus_rounded),
                    label: 'Takip',
                  ),
                  BottomNavigationBarItem(
                    icon: _buildMessageIcon(),
                    activeIcon: _buildNavActiveIcon(Icons.chat_rounded),
                    label: 'Mesajlar',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.assignment_rounded, size: 22),
                    activeIcon: _buildNavActiveIcon(Icons.assignment_rounded),
                    label: 'İzinler',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.notifications_rounded, size: 22),
                    activeIcon:
                        _buildNavActiveIcon(Icons.notifications_rounded),
                    label: 'Mesafe',
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

  Widget _buildMessageIcon() {
    return Stack(
      children: [
        const Icon(Icons.chat_rounded, size: 22),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  AppColors.primaryDark,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryLight,
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Servis Bilgileri',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Güncel durum ve bilgiler',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildInfoRow('Bölge', _getCleanRegionName(),
                    Icons.location_on_rounded, true),
                const SizedBox(height: 16),
                _buildInfoRow('Şoför', _driverName ?? 'Atanmamış',
                    Icons.person_rounded, true),
                const SizedBox(height: 16),
                _buildInfoRow('Araç Plakası', _getCleanVehiclePlate(),
                    Icons.directions_car_rounded, true),
              ],
            ),
          ),
          const SizedBox(height: 24),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('enhanced_stops')
                .where('passengerIds', arrayContains: widget.userId)
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final stop =
                    snapshot.data!.docs.first.data() as Map<String, dynamic>;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade500,
                        Colors.green.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade200,
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aktif Durağım',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Mevcut durak konumunuz',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          stop['address'] ?? 'Adres bilgisi yok',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.orange.shade400,
                        Colors.orange.shade500,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.shade200,
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_off_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Durak Bulunamadı',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Henüz aktif bir durağınız yok',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Profil > Düzenle > Haritadan Seç ile durağınızı belirleyebilirsiniz.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 24),
          _buildEnhancedETACard(),
          const SizedBox(height: 24),
          const Text(
            'Hızlı İşlemler',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  'Servis Takip',
                  Icons.directions_bus_rounded,
                  Colors.blue,
                  () => setState(() => _selectedIndex = 1),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildQuickActionCard(
                  'Mesaj Gönder',
                  Icons.chat_rounded,
                  Colors.green,
                  () => setState(() => _selectedIndex = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  'İzin Bildirimi',
                  Icons.assignment_rounded,
                  Colors.orange,
                  () => setState(() => _selectedIndex = 3),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildQuickActionCard(
                  'Mesafe Uyarısı',
                  Icons.notifications_rounded,
                  Color(0xFF6366F1),
                  () => setState(() => _selectedIndex = 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  'Test Modu',
                  Icons.science_rounded,
                  Colors.deepPurple,
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NotificationDebugScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedETACard() {
    final estimatedMinutes = _enhancedETAData?.remainingMinutes ??
        (_arrivalTimeData?['eta'] as int? ?? 0);
    final stopName =
        _arrivalTimeData?['nextStopName'] as String? ?? 'Bilinmeyen Durak';
    final stopOrder = _arrivalTimeData?['currentStopIndex'] as int? ?? 0;
    final totalStops = _enhancedETAData?.remainingStopsCount ??
        (_arrivalTimeData?['totalStopsCount'] as int? ?? 0);
    final driverDistance =
        _arrivalTimeData?['distanceToStop'] as double? ?? 0.0;
    final averageSpeed = 0.0;
    final trafficFactor = 1.0;
    final isRealTime = _enhancedETAData?.isDriverActive ?? _isDriverActive;
    final lastUpdate = _enhancedETAData?.lastUpdated ?? DateTime.now();

    print('🔍 PassengerHome: ETA Card verileri:');
    print('   - estimatedMinutes: $estimatedMinutes');
    print('   - stopName: $stopName');
    print('   - stopOrder: $stopOrder');
    print('   - totalStops: $totalStops');
    print('   - driverDistance: $driverDistance');
    print('   - _arrivalTimeData: $_arrivalTimeData');
    print('   - _enhancedETAData: $_enhancedETAData');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF6366F1),
            Color(0xFF4F46E5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    if (estimatedMinutes > 0 || _enhancedETAData != null)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Icon(
                          Icons.bolt_rounded,
                          color: Colors.yellow.shade300,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Tahmini Varış Süresi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (estimatedMinutes > 0 || _enhancedETAData != null)
                      ? 'CANLI'
                      : 'TAHMİNİ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                estimatedMinutes > 0 ? '$estimatedMinutes' : '--',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  estimatedMinutes > 0 ? 'dakika' : 'bilinmiyor',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          _isDriverActive &&
                                  (estimatedMinutes > 0 ||
                                      _enhancedETAData != null)
                              ? Icons.directions_bus
                              : _isDriverActive
                                  ? Icons.pause_circle
                                  : Icons.stop_circle,
                          color: Colors.white,
                          size: 16,
                        ),
                        if (estimatedMinutes > 0 || _enhancedETAData != null)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Icon(
                              Icons.wifi_tethering_rounded,
                              color: Colors.lightGreenAccent,
                              size: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isDriverActive &&
                              (estimatedMinutes > 0 || _enhancedETAData != null)
                          ? 'Aktif'
                          : _isDriverActive
                              ? 'Bekliyor'
                              : 'Pasif',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stopName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sıra: ${stopOrder > 0 ? stopOrder : 1}/${totalStops > 0 ? totalStops : 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      'Mesafe: ${driverDistance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                if (averageSpeed > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ort. Hız: ${averageSpeed.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      if (trafficFactor != 1.0)
                        Text(
                          'Trafik: ${trafficFactor > 1.0 ? 'Yoğun' : 'Akıcı'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: trafficFactor > 1.0
                                ? Colors.orange.shade200
                                : Colors.lightGreenAccent,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage:
                    _driverPhotoUrl != null && _driverPhotoUrl!.isNotEmpty
                        ? NetworkImage(_driverPhotoUrl!)
                        : null,
                child: (_driverPhotoUrl == null || _driverPhotoUrl!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white, size: 18)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _driverName != null ? _driverName! : 'Şoför',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      _getCleanVehiclePlate(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _isDriverActive &&
                              (estimatedMinutes > 0 || _enhancedETAData != null)
                          ? Icons.gps_fixed
                          : _isDriverActive
                              ? Icons.gps_not_fixed
                              : Icons.gps_off,
                      color: _isDriverActive &&
                              (estimatedMinutes > 0 || _enhancedETAData != null)
                          ? Colors.lightGreenAccent
                          : _isDriverActive
                              ? Colors.yellow.shade300
                              : Colors.orange.shade200,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isDriverActive &&
                                (estimatedMinutes > 0 ||
                                    _enhancedETAData != null)
                            ? 'Şoför konum paylaşımı aktif • Gerçek zamanlı takip'
                            : _isDriverActive
                                ? 'Şoför aktif ama veri bekleniyor...'
                                : 'Şoför konum paylaşımını başlatmadı',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isDriverActive
                              ? Colors.white
                              : Colors.orange.shade200,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isDriverActive) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Son güncelleme: ${lastUpdate.hour.toString().padLeft(2, '0')}:${lastUpdate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              estimatedMinutes > 0 || _enhancedETAData != null
                                  ? Colors.lightGreenAccent
                                  : Colors.orange.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCleanRegionName() {
    if (widget.regionName == null) return 'Atanmamış';
    String regionName = widget.regionName!;
    if (regionName.contains('{') && regionName.contains('}')) {
      try {
        if (regionName.contains('"data"')) {
          RegExp dataRegex = RegExp(r'"data"\s*:\s*"([^"]+)"');
          Match? match = dataRegex.firstMatch(regionName);
          if (match != null) {
            return match.group(1) ?? 'Bölge Bilgisi';
          }
        }
        return 'Bölge Bilgisi';
      } catch (e) {
        return 'Bölge Bilgisi';
      }
    }
    return regionName;
  }

  String _getCleanVehiclePlate() {
    if (_vehiclePlate == null) return 'Bilinmiyor';
    String plate = _vehiclePlate!;
    if (plate.contains('{') && plate.contains('}')) {
      try {
        if (plate.contains('"data"')) {
          RegExp dataRegex = RegExp(r'"data"\s*:\s*"([^"]+)"');
          Match? match = dataRegex.firstMatch(plate);
          if (match != null) {
            return match.group(1) ?? 'Bilinmiyor';
          }
        }
        RegExp plateRegex = RegExp(r'[0-9]{2}[A-Z]{1,3}[0-9]{1,4}');
        Match? match = plateRegex.firstMatch(plate);
        if (match != null) {
          return match.group(0) ?? 'Bilinmiyor';
        }
        return 'Bilinmiyor';
      } catch (e) {
        return 'Bilinmiyor';
      }
    }
    return plate;
  }

  Widget _buildInfoRow(String label, String value, IconData icon,
      [bool isWhiteTheme = false]) {
    return Row(
      children: [
        Icon(icon,
            color: isWhiteTheme ? Colors.white70 : Colors.grey.shade600,
            size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 15,
            color: isWhiteTheme ? Colors.white70 : Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isWhiteTheme ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
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
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileScreen() {
    return const ProfileScreen();
  }

  Widget _buildPermissionsScreen() {
    return const PermissionScreen();
  }

  Widget _buildTrackingScreen() {
    return EnhancedServiceTracking(
      passengerId: widget.userId,
      regionId: widget.regionId ?? '',
      hideAppBar: true,
    );
  }

  Widget _buildDistanceScreen() {
    return const DistanceAlertScreen();
  }

  Widget _buildMessagesScreen() {
    return ChatScreen(
      onScreenOpen: () {
        _markMessagesAsRead();
      },
    );
  }

  Future<void> _showAddressDialog() async {
    final TextEditingController addressController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.add_location_rounded, color: Color(0xFF4338CA)),
            const SizedBox(width: 8),
            const Text('Ev Adresi Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addressController,
              decoration: InputDecoration(
                labelText: 'Adres',
                hintText: 'Ev adresinizi yazın',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Color(0xFF4338CA)),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _selectLocationFromMap(addressController),
                    icon: const Icon(Icons.map_rounded, color: Colors.white),
                    label: const Text(
                      'Haritadan Seç',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF4338CA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'İptal',
              style: TextStyle(color: Color(0xFF4338CA)),
            ),
          ),
          ElevatedButton(
            onPressed: () => _saveAddress(addressController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF4338CA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Kaydet',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectLocationFromMap(
      TextEditingController addressController) async {
    Navigator.pop(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapSelectionScreen(),
      ),
    );
    if (result != null && result is Map<String, dynamic>) {
      final String address = (result['address'] as String?)?.trim() ?? '';
      final double? lat = (result['latitude'] as num?)?.toDouble();
      final double? lng = (result['longitude'] as num?)?.toDouble();
      addressController.text = address;
      await _persistSelectedLocation(
          address: address, latitude: lat, longitude: lng);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Adres güncellendi'),
              backgroundColor: AppColors.primary),
        );
      }
    }
  }

  Future<void> _persistSelectedLocation({
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final String userId = widget.userId;
      if (address.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'address': address,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        setState(() => _userAddress = address);
      }
      try {
        final snap = await FirebaseFirestore.instance
            .collection('enhanced_stops')
            .where('passengerIds', arrayContains: userId)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final ref = snap.docs.first.reference;
          final update = <String, dynamic>{
            'address': address.isNotEmpty ? address : FieldValue.delete(),
            'lastUpdated': FieldValue.serverTimestamp(),
          };
          if (latitude != null && longitude != null) {
            update['latitude'] = latitude;
            update['longitude'] = longitude;
          }
          await ref.update(update);
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Adres kaydetme hatası: $e'),
              backgroundColor: Colors.red.shade600),
        );
      }
    }
  }

  Future<void> _saveAddress(String address) async {
    if (address.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lütfen bir adres girin'),
          backgroundColor: Color(0xFF4338CA),
        ),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'address': address.trim()});
      setState(() {
        _userAddress = address.trim();
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Adres başarıyla kaydedildi'),
          backgroundColor: Color(0xFF4338CA),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await UserSession.clear();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çıkış hatası: $e')),
        );
      }
    }
  }
}

class MapSelectionScreen extends StatefulWidget {
  const MapSelectionScreen({super.key});
  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String _selectedAddress = '';
  bool _isLoading = false;
  LatLng _initialPosition = const LatLng(41.0082, 28.9784);
  static const double _initialZoom = 15.0;
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _fallbackToActiveStop();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _fallbackToActiveStop();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await _fallbackToActiveStop();
        return;
      }
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
      });
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_initialPosition, _initialZoom),
        );
      }
    } catch (e) {
      print('Konum alma hatası: $e');
      await _fallbackToActiveStop();
    }
  }

  Future<void> _fallbackToActiveStop() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: uid)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data() as Map<String, dynamic>;
        final num? latN = (d['latitude'] ?? d['lat']) as num?;
        final num? lngN = (d['longitude'] ?? d['lng']) as num?;
        if (latN != null && lngN != null) {
          _initialPosition = LatLng(latN.toDouble(), lngN.toDouble());
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(_initialPosition, _initialZoom),
            );
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Konum Seç',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context, {
                  'latitude': _selectedLocation!.latitude,
                  'longitude': _selectedLocation!.longitude,
                  'address': _selectedAddress,
                });
              },
              child: const Text(
                'Seç',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_mapController != null) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialPosition, _initialZoom),
                  );
                }
              });
            },
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: _initialZoom,
            ),
            onTap: _onMapTap,
            markers: _selectedLocation != null
                ? {
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedLocation!,
                      infoWindow: InfoWindow(
                        title: 'Seçilen Konum',
                        snippet: _selectedAddress,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueViolet),
                    ),
                  }
                : {},
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: SimpleLoadingIndicator(
                  message: 'Yükleniyor...',
                  size: 32,
                ),
              ),
            ),
          if (_selectedAddress.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE0E7FF),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seçilen Adres:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4338CA),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onMapTap(LatLng location) async {
    setState(() {
      _selectedLocation = location;
      _isLoading = true;
    });
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = [
          placemark.street,
          placemark.subLocality,
          placemark.locality,
          placemark.administrativeArea,
        ].where((element) => element != null && element.isNotEmpty).join(', ');
        setState(() {
          _selectedAddress = address.isNotEmpty ? address : 'Adres bulunamadı';
        });
      } else {
        final alt = await GeocodingService.getAddressFromCoordinates(
          location.latitude,
          location.longitude,
        );
        setState(() {
          _selectedAddress = alt ??
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      try {
        final alt = await GeocodingService.getAddressFromCoordinates(
          location.latitude,
          location.longitude,
        );
        setState(() {
          _selectedAddress = alt ??
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      } catch (_) {
        setState(() {
          _selectedAddress =
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
