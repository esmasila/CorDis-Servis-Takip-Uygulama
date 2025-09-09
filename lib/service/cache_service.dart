import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
class CacheService {
  static CacheService? _instance;
  static SharedPreferences? _prefs;
  CacheService._();
  static CacheService get instance {
    _instance ??= CacheService._();
    return _instance!;
  }
  static Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      print('✅ Cache Service başlatıldı');
    } catch (e) {
      print('❌ Cache Service başlatma hatası: $e');
    }
  }
  static Future<void> setCache(String key, dynamic value,
      {Duration? expiry}) async {
    try {
      if (_prefs == null) {
        await initialize();
      }
      if (value is String) {
        await _prefs?.setString(key, value);
      } else if (value is int) {
        await _prefs?.setInt(key, value);
      } else if (value is double) {
        await _prefs?.setDouble(key, value);
      } else if (value is bool) {
        await _prefs?.setBool(key, value);
      } else if (value is List<String>) {
        await _prefs?.setStringList(key, value);
      } else if (value is Map<String, dynamic>) {
        final jsonString = jsonEncode(value);
        await _prefs?.setString(key, jsonString);
      } else {
        await _prefs?.setString(key, value.toString());
      }
      if (expiry != null) {
        final expiryTime = DateTime.now().add(expiry).millisecondsSinceEpoch;
        await _prefs?.setInt('${key}_expiry', expiryTime);
      }
      print('💾 Cache kaydedildi: $key = $value');
    } catch (e) {
      print('Cache setCache hatası: $e');
    }
  }
  static T? getCache<T>(String key) {
    try {
      if (_prefs == null) {
        print('⚠️ _prefs null, initialize ediliyor...');
        initialize();
        return null;
      }
      if (isCacheExpired(key)) {
        removeCache(key);
        return null;
      }
      final value = _prefs?.get(key);
      if (value == null) return null;
      print('📱 Cache okundu: $key = $value');
      if (T == String) {
        return value as T?;
      } else if (T == int) {
        return value as T?;
      } else if (T == double) {
        return value as T?;
      } else if (T == bool) {
        return value as T?;
      } else if (T == List<String>) {
        return value as T?;
      } else {
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            return decoded as T?;
          } catch (e) {
            return value as T?;
          }
        }
        return value as T?;
      }
    } catch (e) {
      print('Cache getCache hatası: $e');
      return null;
    }
  }
  static bool isCacheExpired(String key) {
    try {
      final expiryTime = _prefs?.getInt('${key}_expiry');
      if (expiryTime == null) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(expiryTime);
      return DateTime.now().isAfter(expiry);
    } catch (e) {
      print('Cache isCacheExpired hatası: $e');
      return false;
    }
  }
  static Future<void> removeCache(String key) async {
    try {
      await _prefs?.remove(key);
      await _prefs?.remove('${key}_expiry');
    } catch (e) {
      print('Cache removeCache hatası: $e');
    }
  }
  Future<void> setString(String key, String value) async {
    try {
      await _prefs?.setString(key, value);
    } catch (e) {
      print('Cache setString hatası: $e');
    }
  }
  String? getString(String key) {
    try {
      return _prefs?.getString(key);
    } catch (e) {
      print('Cache getString hatası: $e');
      return null;
    }
  }
  Future<void> setInt(String key, int value) async {
    try {
      await _prefs?.setInt(key, value);
    } catch (e) {
      print('Cache setInt hatası: $e');
    }
  }
  int? getInt(String key) {
    try {
      return _prefs?.getInt(key);
    } catch (e) {
      print('Cache getInt hatası: $e');
      return null;
    }
  }
  Future<void> setDouble(String key, double value) async {
    try {
      await _prefs?.setDouble(key, value);
    } catch (e) {
      print('Cache setDouble hatası: $e');
    }
  }
  double? getDouble(String key) {
    try {
      return _prefs?.getDouble(key);
    } catch (e) {
      print('Cache getDouble hatası: $e');
      return null;
    }
  }
  Future<void> setBool(String key, bool value) async {
    try {
      await _prefs?.setBool(key, value);
    } catch (e) {
      print('Cache setBool hatası: $e');
    }
  }
  bool? getBool(String key) {
    try {
      return _prefs?.getBool(key);
    } catch (e) {
      print('Cache getBool hatası: $e');
      return null;
    }
  }
  Future<void> setStringList(String key, List<String> value) async {
    try {
      await _prefs?.setStringList(key, value);
    } catch (e) {
      print('Cache setStringList hatası: $e');
    }
  }
  List<String>? getStringList(String key) {
    try {
      return _prefs?.getStringList(key);
    } catch (e) {
      print('Cache getStringList hatası: $e');
      return null;
    }
  }
  Future<void> setJson(String key, Map<String, dynamic> value) async {
    try {
      final jsonString = jsonEncode(value);
      await _prefs?.setString(key, jsonString);
    } catch (e) {
      print('Cache setJson hatası: $e');
    }
  }
  Map<String, dynamic>? getJson(String key) {
    try {
      final jsonString = _prefs?.getString(key);
      if (jsonString != null) {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Cache getJson hatası: $e');
      return null;
    }
  }
  Future<void> remove(String key) async {
    try {
      await _prefs?.remove(key);
    } catch (e) {
      print('Cache remove hatası: $e');
    }
  }
  Future<void> clear() async {
    try {
      await _prefs?.clear();
      print('✅ Cache temizlendi');
    } catch (e) {
      print('❌ Cache temizleme hatası: $e');
    }
  }
  bool containsKey(String key) {
    try {
      return _prefs?.containsKey(key) ?? false;
    } catch (e) {
      print('Cache containsKey hatası: $e');
      return false;
    }
  }
  Set<String> getKeys() {
    try {
      return _prefs?.getKeys() ?? <String>{};
    } catch (e) {
      print('Cache getKeys hatası: $e');
      return <String>{};
    }
  }
  int getCacheSize() {
    try {
      final keys = getKeys();
      int totalSize = 0;
      for (final key in keys) {
        final value = _prefs?.get(key);
        if (value != null) {
          totalSize += value.toString().length;
        }
      }
      return totalSize;
    } catch (e) {
      print('Cache getCacheSize hatası: $e');
      return 0;
    }
  }
  Future<void> saveUserSession(Map<String, dynamic> sessionData) async {
    await setJson('user_session', sessionData);
  }
  Map<String, dynamic>? getUserSession() {
    return getJson('user_session');
  }
  Future<void> clearUserSession() async {
    await remove('user_session');
  }
  Future<void> saveLastLocation(double lat, double lng) async {
    await setJson('last_location', {
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  Map<String, dynamic>? getLastLocation() {
    return getJson('last_location');
  }
  Future<void> saveAppSettings(Map<String, dynamic> settings) async {
    await setJson('app_settings', settings);
  }
  Map<String, dynamic>? getAppSettings() {
    return getJson('app_settings');
  }
  Future<void> setNotificationsEnabled(bool enabled) async {
    await setBool('notifications_enabled', enabled);
  }
  bool getNotificationsEnabled() {
    return getBool('notifications_enabled') ?? true;
  }
  Future<void> setLocationTrackingEnabled(bool enabled) async {
    await setBool('location_tracking_enabled', enabled);
  }
  bool getLocationTrackingEnabled() {
    return getBool('location_tracking_enabled') ?? false;
  }
  Future<void> setLanguage(String language) async {
    await setString('language', language);
  }
  String getLanguage() {
    return getString('language') ?? 'tr';
  }
  Future<void> setTheme(String theme) async {
    await setString('theme', theme);
  }
  String getTheme() {
    return getString('theme') ?? 'light';
  }
  Future<void> setFCMToken(String token) async {
    await setString('fcm_token', token);
  }
  String? getFCMToken() {
    return getString('fcm_token');
  }
  Future<void> setLastActiveTime(DateTime time) async {
    await setInt('last_active_time', time.millisecondsSinceEpoch);
  }
  DateTime? getLastActiveTime() {
    final timestamp = getInt('last_active_time');
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }
  void printCacheInfo() {
    try {
      final keys = getKeys();
      final size = getCacheSize();
      print('📱 Cache Bilgileri:');
      print('   Toplam anahtar sayısı: ${keys.length}');
      print('   Yaklaşık boyut: ${size} karakter');
      print('   Anahtarlar: ${keys.join(", ")}');
    } catch (e) {
      print('❌ Cache bilgi yazdırma hatası: $e');
    }
  }
}



 Again


