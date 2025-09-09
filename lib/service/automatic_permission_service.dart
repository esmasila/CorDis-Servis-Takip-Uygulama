import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/permission_model.dart';
import 'permission_service.dart';
import 'auto_route_service.dart';
class AutomaticPermissionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _permissionCheckTimer;
  static StreamSubscription? _permissionStream;
  static bool _isInitialized = false;
  static Future<void> initialize() async {
    if (_isInitialized) return;
    print('🔄 Otomatik izin yönetimi servisi başlatılıyor...');
    _startPeriodicPermissionCheck();
    _startPermissionChangeListener();
    _isInitialized = true;
    print('✅ Otomatik izin yönetimi servisi başlatıldı');
  }
  static Future<void> dispose() async {
    _permissionCheckTimer?.cancel();
    _permissionStream?.cancel();
    _isInitialized = false;
    print('🛑 Otomatik izin yönetimi servisi durduruldu');
  }
  static void _startPeriodicPermissionCheck() {
    _permissionCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) => _checkExpiredPermissions(),
    );
  }
  static void _startPermissionChangeListener() {
    _permissionStream = _firestore
        .collection('permissions')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          _handlePermissionChange(change.doc);
        }
      }
    });
  }
  static Future<void> _handlePermissionChange(DocumentSnapshot doc) async {
    try {
      final permission = PermissionModel.fromMap(
        doc.id,
        doc.data() as Map<String, dynamic>,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDate = DateTime(
        permission.startDate.year,
        permission.startDate.month,
        permission.startDate.day,
      );
      bool shouldUpdateRoute = false;
      if (startDate.isAtSameMomentAs(today)) {
        shouldUpdateRoute = true;
        print('📅 İzin bugün başlıyor: ${permission.userName}');
      }
      if (permission.endDate != null) {
        final endDate = DateTime(
          permission.endDate!.year,
          permission.endDate!.month,
          permission.endDate!.day,
        );
        if (endDate.isAtSameMomentAs(today)) {
          shouldUpdateRoute = true;
          print('📅 İzin bugün bitiyor: ${permission.userName}');
        }
      }
      if (shouldUpdateRoute && permission.driverId != null) {
        await _triggerAutomaticRouteUpdate(
          permission.driverId!,
          permission.userId,
          'permission_schedule_change',
        );
        try {
          await PermissionService.deactivatePassengerStopForPermission(
              permission.userId);
        } catch (_) {}
      }
    } catch (e) {
      print('❌ İzin değişikliği işleme hatası: $e');
    }
  }
  static Future<void> _checkExpiredPermissions() async {
    try {
      final now = DateTime.now();
      print('🔍 Süresi dolan izinler kontrol ediliyor...');
      final snapshot = await _firestore
          .collection('permissions')
          .where('isActive', isEqualTo: true)
          .get();
      final expiredPermissions = <PermissionModel>[];
      final driversToUpdate = <String>{};
      for (final doc in snapshot.docs) {
        final permission = PermissionModel.fromMap(
          doc.id,
          doc.data(),
        );
        if (permission.endDate != null && permission.endDate!.isBefore(now)) {
          expiredPermissions.add(permission);
          if (permission.driverId != null) {
            driversToUpdate.add(permission.driverId!);
          }
          await doc.reference.update({'isActive': false});
          print('⏰ Süresi dolan izin deaktif edildi: ${permission.userName}');
        }
      }
      for (final driverId in driversToUpdate) {
        await _triggerAutomaticRouteUpdate(
          driverId,
          null,
          'permission_expired',
        );
      }
      if (expiredPermissions.isNotEmpty) {
        print('✅ ${expiredPermissions.length} süresi dolan izin işlendi');
      }
    } catch (e) {
      print('❌ Süresi dolan izin kontrolü hatası: $e');
    }
  }
  static Future<void> _triggerAutomaticRouteUpdate(
    String driverId,
    String? userId,
    String reason,
  ) async {
    try {
      print('🔄 Otomatik rota güncellemesi tetikleniyor: $reason');
      final driverDoc =
          await _firestore.collection('drivers').doc(driverId).get();
      if (!driverDoc.exists) {
        print('❌ Şoför bulunamadı: $driverId');
        return;
      }
      final driverData = driverDoc.data()!;
      final regionId = driverData['regionId'] as String?;
      if (regionId == null) {
        print('❌ Şoförün bölgesi bulunamadı');
        return;
      }
      await AutoRouteService.updateRouteForPermissionChange(
        driverId,
        regionId,
      );
      await _firestore.collection('automatic_route_updates').add({
        'driverId': driverId,
        'userId': userId,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'completed',
        'regionId': regionId,
      });
      await _sendDriverNotification(
        driverId,
        'Otomatik Rota Güncellemesi',
        'İzin değişikliği nedeniyle rotanız otomatik olarak güncellendi.',
        reason,
      );
      print('✅ Otomatik rota güncellemesi tamamlandı');
    } catch (e) {
      print('❌ Otomatik rota güncelleme hatası: $e');
      await _firestore.collection('automatic_route_updates').add({
        'driverId': driverId,
        'userId': userId,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'failed',
        'error': e.toString(),
      });
    }
  }
  static Future<void> _sendDriverNotification(
    String driverId,
    String title,
    String message,
    String type,
  ) async {
    try {
      await _firestore.collection('driver_notifications').add({
        'driverId': driverId,
        'title': title,
        'message': message,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'medium',
        'source': 'automatic_permission_service',
      });
    } catch (e) {
      print('❌ Şoför bildirimi gönderme hatası: $e');
    }
  }
  static Future<void> triggerManualRouteUpdate(String driverId) async {
    final driverDoc =
        await _firestore.collection('drivers').doc(driverId).get();
    if (!driverDoc.exists) {
      throw Exception('Şoför bulunamadı');
    }
    final regionId = driverDoc.data()!['regionId'] as String?;
    if (regionId == null) {
      throw Exception('Şoförün bölgesi bulunamadı');
    }
    await _triggerAutomaticRouteUpdate(
      driverId,
      null,
      'manual_trigger',
    );
  }
  static Future<Map<String, dynamic>> generateDailyPermissionReport(
    String? driverId,
  ) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      Query query = _firestore.collection('permissions');
      if (driverId != null) {
        query = query.where('driverId', isEqualTo: driverId);
      }
      final snapshot = await query
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();
      final permissions = snapshot.docs
          .map((doc) => PermissionModel.fromMap(
              doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      final activePermissions = permissions.where((p) => p.isActive).length;
      final expiredPermissions = permissions.where((p) => !p.isActive).length;
      final sickLeaves = permissions
          .where((p) =>
              p.type == PermissionType.allToday ||
              p.type == PermissionType.allTomorrow)
          .length;
      final vacations =
          permissions.where((p) => p.type == PermissionType.vacation).length;
      final others = permissions
          .where((p) =>
              p.type == PermissionType.morningToday ||
              p.type == PermissionType.eveningToday ||
              p.type == PermissionType.morningTomorrow)
          .length;
      return {
        'date': today.toIso8601String(),
        'totalPermissions': permissions.length,
        'activePermissions': activePermissions,
        'expiredPermissions': expiredPermissions,
        'byType': {
          'sick': sickLeaves,
          'vacation': vacations,
          'other': others,
        },
        'permissions': permissions.map((p) => p.toMap()).toList(),
      };
    } catch (e) {
      print('❌ Günlük izin raporu oluşturma hatası: $e');
      return {
        'error': e.toString(),
        'date': DateTime.now().toIso8601String(),
      };
    }
  }
  static bool get isInitialized => _isInitialized;
  static int get activeTimerCount =>
      _permissionCheckTimer?.isActive == true ? 1 : 0;
  static int get activeStreamCount => _permissionStream != null ? 1 : 0;
}





