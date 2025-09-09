import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/config_service.dart';
import 'widget/snackbar.dart';
import 'widget/common_loading_screen.dart';
import 'view/login_screen.dart';
import 'view/splash_screen.dart';
import 'admin/admin_screen.dart';
import 'driver/driver_home.dart';
import 'passenger/passenger_home.dart';
import 'service/user_session.dart';
import 'service/location_service.dart';
import 'service/notification_service.dart';
import 'service/cache_service.dart';
import 'service/chat_service.dart';
import 'service/background_location_service.dart';
import 'service/theme_service.dart';
import 'service/automatic_permission_service.dart';
import 'service/proximity_notification_service.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ConfigService.initialize();
    print("✅ Konfigürasyon servisi başlatıldı");

    // Firebase'i her platformda başlat
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print("✅ Firebase başlatıldı");
    } catch (e) {
      print("⚠️ Firebase başlatma hatası: $e");
      // Web platformunda Firebase zaten HTML'de başlatıldıysa devam et
      if (kIsWeb) {
        print("✅ Firebase web'de HTML'den başlatıldı");
      } else {
        rethrow;
      }
    }

    await CacheService.initialize();
    await ThemeService.instance.initialize();
    await initializeDateFormatting('tr_TR', null);
    print("✅ Tarih formatı başlatıldı");
    print("🚀 Uygulama başlatılıyor...");
  } catch (e) {
    print("❌ Başlatma hatası: $e");
  }
  runApp(const MyApp());
  Future.microtask(() async {
    try {
      await NotificationService().initialize();
      print("✅ Notification servisi başlatıldı");
    } catch (e) {
      print('Notification init hatası: $e');
    }
    try {
      await BackgroundLocationService.initializeService();
      print("✅ Background location servisi başlatıldı");
    } catch (e) {
      print('Background location init hatası: $e');
    }
    try {
      await AutomaticPermissionService.initialize();
      print("✅ Otomatik izin yönetimi servisi başlatıldı");
    } catch (e) {
      print('AutomaticPermission init hatası: $e');
    }
    try {
      await ProximityNotificationService.initialize();
      print("✅ Yakınlık bildirimi servisi başlatıldı");
    } catch (e) {
      print('ProximityNotification init hatası: $e');
    }
    try {
      await ChatService.initializeExpiryService();
      print("✅ Süreli mesaj servisi başlatıldı");
    } catch (e) {
      print('ChatService expiry init hatası: $e');
    }
    try {
      await UserSession.loadFromPreferences();
      print(
          "✅ UserSession verileri yüklendi - Konum paylaşımı: ${UserSession.isLocationSharing}");
    } catch (e) {
      print('UserSession yükleme hatası: $e');
    }
    if (!kIsWeb) {
      try {
        Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
        print("✅ Workmanager başlatıldı");
      } catch (e) {
        print('Workmanager init hatası: $e');
      }
    }
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      print('📱 Background task çalışıyor: $taskName');
      if (!kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      switch (taskName) {
        case 'backgroundLocationTask':
        case 'driverLocationTask':
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await LocationService().updateLocationInBackground();
            print('✅ Background konum güncellendi');
          } else {
            print('⚠️ Kullanıcı oturum açmamış');
          }
          break;
        case 'stopProximityTask':
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await LocationService().checkProximityAndMarkStops();
            print('✅ Durak yakınlık kontrolü tamamlandı');
          } else {
            print('⚠️ Kullanıcı oturum açmamış - Durak kontrolü');
          }
          break;
        case 'proximityNotificationTask':
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await ProximityNotificationService.checkProximityInBackground();
            print('✅ Yakınlık bildirimi kontrolü tamamlandı');
          } else {
            print('⚠️ Kullanıcı oturum açmamış - Yakınlık kontrolü');
          }
          break;
        default:
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await LocationService().updateLocationInBackground();
            print('✅ Default background konum güncellendi');
          } else {
            print('⚠️ Kullanıcı oturum açmamış - Default');
          }
          break;
      }
      return Future.value(true);
    } catch (e) {
      print('❌ Background task hatası: $e');
      return Future.value(false);
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeService.instance.initialize().then((_) {
      if (mounted) setState(() {});
    });
    ThemeService.instance.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        NotificationService.instance.setAppForeground(true);
        print('📱 Uygulama ön plana geldi');
        break;
      case AppLifecycleState.inactive:
        NotificationService.instance.setAppForeground(false);
        print('📱 Uygulama inaktif');
        break;
      case AppLifecycleState.paused:
        NotificationService.instance.setAppForeground(false);
        print('📱 Uygulama arka plana gitti');
        break;
      case AppLifecycleState.detached:
        NotificationService.instance.setAppForeground(false);
        print('📱 Uygulama kapatıldı');
        break;
      case AppLifecycleState.hidden:
        NotificationService.instance.setAppForeground(false);
        print('📱 Uygulama gizlendi');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            themeMode: themeProvider.themeMode,
            scaffoldMessengerKey: messengerKey,
            debugShowCheckedModeBanner: false,
            title: 'Servis Takip',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6366F1),
                brightness: Brightness.light,
                surface: const Color(0xFFF8FAFC),
                background: const Color(0xFFF8FAFC),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
                surfaceTintColor: Colors.transparent,
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              textTheme: const TextTheme(
                headlineLarge: TextStyle(
                    color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                headlineMedium: TextStyle(
                    color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                titleLarge: TextStyle(
                    color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                bodyLarge: TextStyle(color: Color(0xFF64748B)),
                bodyMedium: TextStyle(color: Color(0xFF64748B)),
              ),
              bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                backgroundColor: Colors.white,
                selectedItemColor: Color(0xFF6366F1),
                unselectedItemColor: Color(0xFF94A3B8),
                elevation: 0,
                type: BottomNavigationBarType.fixed,
              ),
            ),
            home: const SplashScreen(),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/admin': (context) => const AdminScreen(),
              '/auth': (context) => const AuthWrapper(),
            },
            onUnknownRoute: (settings) {
              print('⚠️ Bilinmeyen route: ${settings.name}');
              return MaterialPageRoute(
                  builder: (context) => const LoginScreen());
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    try {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScreen(message: 'Kimlik doğrulanıyor...');
          }
          final user = authSnapshot.data;
          if (user == null) {
            return const LoginScreen();
          }
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(),
            builder: (context, userSnap) {
              if (userSnap.connectionState != ConnectionState.done) {
                return const _LoadingScreen(
                  message: 'Kullanıcı bilgileri yükleniyor...',
                );
              }
              if (!userSnap.hasData || !userSnap.data!.exists) {
                print('⚠️ Kullanıcı verisi bulunamadı, çıkış yapılıyor');
                return _signOutAndReturn();
              }
              final data = userSnap.data!.data() as Map<String, dynamic>;
              final role = data['role'] ?? '';
              UserSession.userId = user.uid;
              UserSession.userEmail = user.email;
              UserSession.userName = data['name'];
              UserSession.userRole = role;
              UserSession.photoUrl = data['photoUrl'];
              return FutureBuilder<Widget>(
                future: _buildRoleScreen(user.uid, role, data),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _LoadingScreen(
                      message: '$role ekranı hazırlanıyor...',
                    );
                  }
                  if (snapshot.hasError) {
                    print('❌ Ekran yükleme hatası: ${snapshot.error}');
                    return _signOutAndReturn();
                  }
                  return snapshot.data ?? _signOutAndReturn();
                },
              );
            },
          );
        },
      );
    } catch (e) {
      print('❌ AuthWrapper Firebase hatası: $e');
      return const LoginScreen();
    }
  }

  Future<Widget> _buildRoleScreen(
    String uid,
    String role,
    Map<String, dynamic> data,
  ) async {
    try {
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
          final valueMatch =
              RegExp(r'^"([^"]+)"$').firstMatch(regionName.trim());
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

      Future<void> setRegionInfo(String? regionId) async {
        if (regionId != null && regionId.isNotEmpty) {
          UserSession.regionId = regionId;
          String? cachedRegionName = CacheService.getCache<String>(
            'region_name_$regionId',
          );
          if (cachedRegionName != null) {
            UserSession.regionName = _getCleanRegionName(cachedRegionName);
          } else {
            try {
              final regionDoc = await FirebaseFirestore.instance
                  .collection('regions')
                  .doc(regionId)
                  .get();
              if (regionDoc.exists) {
                final regionData = regionDoc.data() as Map<String, dynamic>;
                final regionName =
                    _getCleanRegionName(regionData['name'] ?? regionId);
                UserSession.regionName = regionName;
                await CacheService.setCache(
                  'region_name_$regionId',
                  regionName,
                  expiry: const Duration(hours: 24),
                );
              } else {
                UserSession.regionName = _getCleanRegionName(regionId);
              }
            } catch (e) {
              print('❌ Bölge adı alınırken hata: $e');
              UserSession.regionName = _getCleanRegionName(regionId);
            }
          }
        }
      }

      switch (role) {
        case 'Admin':
          print('✅ Admin ekranı yükleniyor');
          return const AdminScreen();
        case 'Şoför':
          print('✅ Şoför ekranı yükleniyor');
          final driverSnap = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(uid)
              .get();
          if (!driverSnap.exists) {
            print('❌ Şoför verisi bulunamadı');
            return _signOutAndReturn();
          }
          final driverData = driverSnap.data()!;
          await setRegionInfo(driverData['regionId']);
          UserSession.vehiclePlate = driverData['vehiclePlate'];
          await NotificationService.instance.refreshMessageNotifications();
          return DriverHome(
            driverId: uid,
            vehiclePlate: driverData['vehiclePlate'] ?? '',
            region: driverData['regionId'] ?? '',
          );
        case 'Yolcu':
          print('✅ Yolcu ekranı yükleniyor');
          await setRegionInfo(data['regionId']);
          if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
            try {
              final stopsSnap = await FirebaseFirestore.instance
                  .collection('enhanced_stops')
                  .where('isActive', isEqualTo: true)
                  .where('passengerIds', arrayContains: uid)
                  .limit(1)
                  .get();
              if (stopsSnap.docs.isNotEmpty) {
                final rid =
                    (stopsSnap.docs.first.data())['regionId'] as String?;
                if (rid != null && rid.isNotEmpty) {
                  UserSession.regionId = rid;
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'regionId': rid});
                  print('✅ Bölge, aktif duraktan çözüldü: $rid');
                }
              }
            } catch (e) {
              print('⚠️ Bölge fallback çözümleme hatası: $e');
            }
          }
          final effectiveRegionId = UserSession.regionId ?? data['regionId'];
          if ((data['driverId'] == null ||
                  (data['driverId'] as String?)?.isEmpty == true) &&
              effectiveRegionId != null) {
            final driverQuery = await FirebaseFirestore.instance
                .collection('drivers')
                .where('regionId', isEqualTo: effectiveRegionId)
                .where('isActive', isEqualTo: true)
                .limit(1)
                .get();
            if (driverQuery.docs.isNotEmpty) {
              final driverId = driverQuery.docs.first.id;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .update({'driverId': driverId});
              data['driverId'] = driverId;
              print('✅ Şoför otomatik atandı: $driverId');
            }
          }
          UserSession.driverId = data['driverId'];
          if (UserSession.driverId != null) {
            try {
              final driverSnap = await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(UserSession.driverId)
                  .get();
              if (driverSnap.exists) {
                final d = driverSnap.data()!;
                UserSession.driverName = d['name'] ?? UserSession.driverName;
                UserSession.vehiclePlate =
                    d['vehiclePlate'] ?? UserSession.vehiclePlate;
              }
            } catch (_) {}
          }
          await NotificationService.instance.refreshMessageNotifications();
          if (UserSession.driverId != null) {
            String? cachedPlate = CacheService.getCache<String>(
              'driver_plate_${UserSession.driverId}',
            );
            if (cachedPlate != null) {
              UserSession.vehiclePlate = cachedPlate;
            } else {
              final driverSnap = await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(UserSession.driverId)
                  .get();
              if (driverSnap.exists) {
                final driverData = driverSnap.data()!;
                final vehiclePlate = driverData['vehiclePlate'] ?? '';
                UserSession.vehiclePlate = vehiclePlate;
                await CacheService.setCache(
                  'driver_plate_${UserSession.driverId}',
                  vehiclePlate,
                  expiry: const Duration(hours: 12),
                );
              }
            }
          }
          return PassengerHome(
            userId: uid,
            userName: data['name'] ?? 'Kullanıcı',
            userEmail: data['email'] ?? '',
            regionId: UserSession.regionId ?? data['regionId'],
            regionName: UserSession.regionName,
            driverId: UserSession.driverId,
          );
        default:
          print('❌ Bilinmeyen rol: $role');
          return _signOutAndReturn();
      }
    } catch (e) {
      print('❌ Rol ekranı oluşturma hatası: $e');
      return _signOutAndReturn();
    }
  }

  Widget _signOutAndReturn() {
    FirebaseAuth.instance.signOut();
    UserSession.clear();
    return const LoginScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  final String message;
  const _LoadingScreen({this.message = 'Yükleniyor...'});
  @override
  Widget build(BuildContext context) {
    return CommonLoadingScreen(
      message: message,
      subtitle: 'Servis Takip Uygulaması',
      showLogo: true,
      showAppName: true,
    );
  }
}

// Updated

