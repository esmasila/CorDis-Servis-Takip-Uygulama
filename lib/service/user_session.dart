import 'package:shared_preferences/shared_preferences.dart';
class UserSession {
  static final UserSession _instance = UserSession._internal();
  static UserSession get instance => _instance;
  UserSession._internal();
  static String? userId;
  static String? userEmail;
  static String? userName;
  static String? userRole;
  static String? photoUrl;
  static String? regionId;
  static String? regionName;
  static String? driverId;
  static String? driverName;
  static String? vehiclePlate;
  static String? passengerId;
  static String? passengerName;
  static double? currentLatitude;
  static double? currentLongitude;
  static double? distance;
  static bool _isLocationSharing = false;
  static bool _isOnline = false;
  static DateTime? _lastActiveTime;
  static String? _fcmToken;
  static bool _notificationsEnabled = true;
  static bool _locationTrackingEnabled = true;
  static String _language = 'tr';
  static String _theme = 'light';
  static bool get isLocationSharing => _isLocationSharing;
  static bool get isOnline => _isOnline;
  static DateTime? get lastActiveTime => _lastActiveTime;
  static String? get fcmToken => _fcmToken;
  static bool get notificationsEnabled => _notificationsEnabled;
  static bool get locationTrackingEnabled => _locationTrackingEnabled;
  static String get language => _language;
  static String get theme => _theme;
  static set isLocationSharing(bool value) {
    print(
        '🔄 UserSession: Konum paylaşımı durumu güncellendi: $_isLocationSharing -> $value');
    _isLocationSharing = value;
    _saveToPreferences();
  }
  static set isOnline(bool value) {
    _isOnline = value;
    _lastActiveTime = DateTime.now();
    _saveToPreferences();
  }
  static set fcmToken(String? value) {
    _fcmToken = value;
    _saveToPreferences();
  }
  static set notificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _saveToPreferences();
  }
  static set locationTrackingEnabled(bool value) {
    _locationTrackingEnabled = value;
    _saveToPreferences();
  }
  static set language(String value) {
    _language = value;
    _saveToPreferences();
  }
  static set theme(String value) {
    _theme = value;
    _saveToPreferences();
  }
  static void updateUserInfo({
    String? id,
    String? email,
    String? name,
    String? role,
    String? photo,
  }) {
    if (id != null) userId = id;
    if (email != null) userEmail = email;
    if (name != null) userName = name;
    if (role != null) userRole = role;
    if (photo != null) photoUrl = photo;
    _saveToPreferences();
  }
  static void updateRegionInfo({
    String? id,
    String? name,
  }) {
    if (id != null) regionId = id;
    if (name != null) regionName = name;
    _saveToPreferences();
  }
  static void updateDriverInfo({
    String? id,
    String? name,
    String? plate,
  }) {
    if (id != null) driverId = id;
    if (name != null) driverName = name;
    if (plate != null) vehiclePlate = plate;
    _saveToPreferences();
  }
  static void updateLocation({
    double? latitude,
    double? longitude,
    double? dist,
  }) {
    if (latitude != null) currentLatitude = latitude;
    if (longitude != null) currentLongitude = longitude;
    if (dist != null) distance = dist;
    _saveToPreferences();
  }
  static bool get isAdmin => userRole == 'Admin';
  static bool get isDriver => userRole == 'Şoför';
  static bool get isPassenger => userRole == 'Yolcu';
  static bool get isLoggedIn => userId != null && userId!.isNotEmpty;
  static bool get hasLocation =>
      currentLatitude != null && currentLongitude != null;
  static bool get hasCompleteProfile =>
      userId != null &&
      userName != null &&
      userEmail != null &&
      userRole != null;
  static void updateLastActiveTime() {
    _lastActiveTime = DateTime.now();
    _saveToPreferences();
  }
  static Future<void> saveToPreferences() async {
    await _saveToPreferences();
  }
  static Future<void> _saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (userId != null) await prefs.setString('userId', userId!);
      if (userEmail != null) await prefs.setString('userEmail', userEmail!);
      if (userName != null) await prefs.setString('userName', userName!);
      if (userRole != null) await prefs.setString('userRole', userRole!);
      if (photoUrl != null) await prefs.setString('photoUrl', photoUrl!);
      if (regionId != null) await prefs.setString('regionId', regionId!);
      if (regionName != null) await prefs.setString('regionName', regionName!);
      if (driverId != null) await prefs.setString('driverId', driverId!);
      if (driverName != null) await prefs.setString('driverName', driverName!);
      if (vehiclePlate != null)
        await prefs.setString('vehiclePlate', vehiclePlate!);
      if (currentLatitude != null)
        await prefs.setDouble('currentLatitude', currentLatitude!);
      if (currentLongitude != null)
        await prefs.setDouble('currentLongitude', currentLongitude!);
      if (distance != null) await prefs.setDouble('distance', distance!);
      await prefs.setBool('isLocationSharing', _isLocationSharing);
      await prefs.setBool('isOnline', _isOnline);
      if (_lastActiveTime != null) {
        await prefs.setString(
            'lastActiveTime', _lastActiveTime!.toIso8601String());
      }
      if (_fcmToken != null) await prefs.setString('fcmToken', _fcmToken!);
      await prefs.setBool('notificationsEnabled', _notificationsEnabled);
      await prefs.setBool('locationTrackingEnabled', _locationTrackingEnabled);
      await prefs.setString('language', _language);
      await prefs.setString('theme', _theme);
    } catch (e) {
    }
  }
  static Future<void> loadFromPreferences() async {
    try {
      print('📱 UserSession: Preferences\'tan veriler yükleniyor...');
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString('userId');
      userEmail = prefs.getString('userEmail');
      userName = prefs.getString('userName');
      userRole = prefs.getString('userRole');
      photoUrl = prefs.getString('photoUrl');
      regionId = prefs.getString('regionId');
      regionName = prefs.getString('regionName');
      driverId = prefs.getString('driverId');
      driverName = prefs.getString('driverName');
      vehiclePlate = prefs.getString('vehiclePlate');
      currentLatitude = prefs.getDouble('currentLatitude');
      currentLongitude = prefs.getDouble('currentLongitude');
      distance = prefs.getDouble('distance');
      final previousLocationSharing = _isLocationSharing;
      _isLocationSharing = prefs.getBool('isLocationSharing') ?? false;
      _isOnline = prefs.getBool('isOnline') ?? false;
      final lastActiveString = prefs.getString('lastActiveTime');
      if (lastActiveString != null) {
        _lastActiveTime = DateTime.parse(lastActiveString);
      }
      _fcmToken = prefs.getString('fcmToken');
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _locationTrackingEnabled =
          prefs.getBool('locationTrackingEnabled') ?? true;
      _language = prefs.getString('language') ?? 'tr';
      _theme = prefs.getString('theme') ?? 'light';
      print('✅ UserSession verileri yüklendi:');
      print('   - Kullanıcı: $userName ($userRole)');
      print(
          '   - Konum paylaşımı: $previousLocationSharing -> $_isLocationSharing');
      print('   - Şoför ID: $driverId');
      print('   - Araç: $vehiclePlate');
    } catch (e) {
      print('❌ UserSession yükleme hatası: $e');
    }
  }
  static Future<void> clear() async {
    userId = null;
    userEmail = null;
    userName = null;
    userRole = null;
    photoUrl = null;
    regionId = null;
    regionName = null;
    driverId = null;
    driverName = null;
    vehiclePlate = null;
    currentLatitude = null;
    currentLongitude = null;
    distance = null;
    _isLocationSharing = false;
    _isOnline = false;
    _lastActiveTime = null;
    _fcmToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = [
        'userId',
        'userEmail',
        'userName',
        'userRole',
        'photoUrl',
        'regionId',
        'regionName',
        'driverId',
        'driverName',
        'vehiclePlate',
        'currentLatitude',
        'currentLongitude',
        'distance',
        'isLocationSharing',
        'isOnline',
        'lastActiveTime',
        'fcmToken',
      ];
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (e) {
    }
  }
  static void printSessionInfo() {
  }
}

// Updated


// Updated Again


