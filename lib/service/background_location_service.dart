import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'location_service.dart';
import 'user_session.dart';
import 'proximity_notification_service.dart';
class BackgroundLocationService {
  static const String _backgroundLocationTask = 'backgroundLocationTask';
  static const String _driverLocationTask = 'driverLocationTask';
  static const String _stopProximityTask = 'stopProximityTask';
  static bool _isInitialized = false;
  static Future<void> initializeService() async {
    if (_isInitialized) return;
    try {
      if (kIsWeb) {
        _isInitialized = true;
        print('ℹ️ Background Location Service web\'de desteklenmiyor (no-op)');
        return;
      }
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      _isInitialized = true;
      print('✅ Background Location Service başlatıldı');
    } catch (e) {
      print('❌ Background Location Service başlatma hatası: $e');
    }
  }
  static Future<void> startBackgroundLocationUpdates() async {
    try {
      if (kIsWeb) {
        print('ℹ️ Web\'de background konum güncelleme desteklenmiyor');
        return;
      }
      if (!_isInitialized) {
        await initializeService();
      }
      await Workmanager().registerPeriodicTask(
        _backgroundLocationTask,
        _backgroundLocationTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      print('✅ Background konum güncelleme başlatıldı');
    } catch (e) {
      print('❌ Background konum güncelleme başlatma hatası: $e');
    }
  }
  static Future<void> startDriverLocationTracking() async {
    try {
      if (kIsWeb) {
        print('ℹ️ Web\'de şoför konum takibi (background) desteklenmiyor');
        return;
      }
      if (!_isInitialized) {
        await initializeService();
      }
      await Workmanager().registerPeriodicTask(
        _driverLocationTask,
        _driverLocationTask,
        frequency: const Duration(minutes: 5),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      UserSession.isLocationSharing = true;
      await UserSession.saveToPreferences();
      print('✅ Şoför konum takibi başlatıldı ve durum kaydedildi');
    } catch (e) {
      print('❌ Şoför konum takibi başlatma hatası: $e');
    }
  }
  static Future<void> startStopProximityCheck() async {
    try {
      if (kIsWeb) {
        print('ℹ️ Web\'de durak yakınlık kontrolü (background) desteklenmiyor');
        return;
      }
      if (!_isInitialized) {
        await initializeService();
      }
      await Workmanager().registerPeriodicTask(
        _stopProximityTask,
        _stopProximityTask,
        frequency: const Duration(minutes: 2),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      print('✅ Durak yakınlık kontrolü başlatıldı');
    } catch (e) {
      print('❌ Durak yakınlık kontrolü başlatma hatası: $e');
    }
  }
  static Future<void> stopAllBackgroundTasks() async {
    try {
      if (kIsWeb) return;
      await Workmanager().cancelAll();
      print('✅ Tüm background görevler durduruldu');
    } catch (e) {
      print('❌ Background görevler durdurma hatası: $e');
    }
  }
  static Future<void> stopBackgroundLocationUpdates() async {
    try {
      if (kIsWeb) return;
      await Workmanager().cancelByUniqueName(_backgroundLocationTask);
      print('✅ Background konum güncelleme durduruldu');
    } catch (e) {
      print('❌ Background konum güncelleme durdurma hatası: $e');
    }
  }
  static Future<void> stopDriverLocationTracking() async {
    try {
      if (kIsWeb) return;
      await Workmanager().cancelByUniqueName(_driverLocationTask);
      print('✅ Şoför konum takibi durduruldu (UserSession korundu)');
      print('🔄 Konum paylaşımı durumu: ${UserSession.isLocationSharing}');
    } catch (e) {
      print('❌ Şoför konum takibi durdurma hatası: $e');
    }
  }
  static Future<void> stopStopProximityCheck() async {
    try {
      if (kIsWeb) return;
      await Workmanager().cancelByUniqueName(_stopProximityTask);
      print('✅ Durak yakınlık kontrolü durduruldu');
    } catch (e) {
      print('❌ Durak yakınlık kontrolü durdurma hatası: $e');
    }
  }
  static Future<void> startLocationTracking() async {
    await startDriverLocationTracking();
  }
  static Future<void> stopLocationTracking() async {
    print('🛑 stopLocationTracking çağrıldı - sadece task durduruluyor');
    await stopDriverLocationTracking();
  }
  static Future<void> forceStopLocationSharing() async {
    try {
      if (kIsWeb) {
        UserSession.isLocationSharing = false;
        await UserSession.saveToPreferences();
        print('🔴 (Web) Konum paylaşımı durumu false olarak kaydedildi');
        return;
      }
      await Workmanager().cancelByUniqueName(_driverLocationTask);
      UserSession.isLocationSharing = false;
      await UserSession.saveToPreferences();
      print('🔴 Konum paylaşımı tamamen durduruldu ve durum kaydedildi');
    } catch (e) {
      print('❌ Konum paylaşımı durdurma hatası: $e');
    }
  }
  static Future<bool> checkLocationPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      print('❌ Konum izni kontrolü hatası: $e');
      return false;
    }
  }
  static Future<Position?> getCurrentLocationForBackground() async {
    try {
      final hasPermission = await checkLocationPermissions();
      if (!hasPermission) {
        print('❌ Background konum için izin yok');
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 30),
      );
    } catch (e) {
      print('❌ Background konum alma hatası: $e');
      return null;
    }
  }
}
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      print('📱 Background task çalışıyor: $taskName');
      switch (taskName) {
        case 'backgroundLocationTask':
        case 'driverLocationTask':
          await _handleLocationUpdate();
          break;
        case 'stopProximityTask':
          await _handleStopProximityCheck();
          break;
        case 'passengerProximityTask':
          await _handlePassengerProximityCheck();
          break;
        case 'permissionExpiryTask':
          await _handlePermissionExpiryCheck();
          break;
        default:
          print('❓ Bilinmeyen task: $taskName');
          break;
      }
      return Future.value(true);
    } catch (e) {
      print('❌ Background task hatası: $e');
      return Future.value(false);
    }
  });
}
Future<void> _handleLocationUpdate() async {
  try {
    final position =
        await BackgroundLocationService.getCurrentLocationForBackground();
    if (position != null) {
      await LocationService.instance.updateLocationInBackground();
      print('✅ Background konum güncellendi');
    }
  } catch (e) {
    print('❌ Background konum güncelleme hatası: $e');
  }
}
Future<void> _handleStopProximityCheck() async {
  try {
    final position =
        await BackgroundLocationService.getCurrentLocationForBackground();
    if (position != null) {
      await LocationService.instance.checkProximityAndMarkStops();
      print('✅ Background durak kontrolü tamamlandı');
    }
  } catch (e) {
    print('❌ Background durak kontrolü hatası: $e');
  }
}
Future<void> _handlePassengerProximityCheck() async {
  try {
    print('📍 Yolcu yakınlık kontrolü başlatılıyor...');
    await _checkPassengerDriverProximity();
    print('✅ Yolcu yakınlık kontrolü tamamlandı');
  } catch (e) {
    print('❌ Yolcu yakınlık kontrolü hatası: $e');
  }
}
Future<void> _checkPassengerDriverProximity() async {
  try {
    await ProximityNotificationService.checkProximityInBackground();
  } catch (e) {
    print('❌ Background proximity kontrolü hatası: $e');
  }
}
Future<void> _handlePermissionExpiryCheck() async {
  try {
    print('⏰ İzin süresi kontrolü başlatılıyor...');
    await _checkExpiredPermissions();
    print('✅ İzin süresi kontrolü tamamlandı');
  } catch (e) {
    print('❌ İzin süresi kontrolü hatası: $e');
  }
}
Future<void> _checkExpiredPermissions() async {
  print('🔍 Süresi dolmuş izinler kontrol ediliyor...');
}





