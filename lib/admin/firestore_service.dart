import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/region_model.dart';
import '../models/user_model.dart';

class AdminFirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Map<String, List<RegionModel>>? _regionsCache;
  static DateTime? _regionsCacheTime;
  static const Duration _cacheTimeout = Duration(minutes: 5);
  static void clearCache() {
    _regionsCache = null;
    _regionsCacheTime = null;
  }

  static bool _isCacheValid() {
    if (_regionsCacheTime == null) return false;
    return DateTime.now().difference(_regionsCacheTime!) < _cacheTimeout;
  }

  static Future<List<RegionModel>> getRegions() async {
    try {
      if (_regionsCache != null && _isCacheValid()) {
        print('[FirestoreService] Returning cached regions');
        return _regionsCache!['regions'] ?? [];
      }
      print('[FirestoreService] Fetching regions from Firestore');
      final snapshot = await _firestore
          .collection('regions')
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));
      final regions = snapshot.docs
          .map((doc) => RegionModel.fromMap(doc.id, doc.data()))
          .toList();
      _regionsCache = {'regions': regions};
      _regionsCacheTime = DateTime.now();
      return regions;
    } catch (e) {
      print('[FirestoreService] Error fetching regions: $e');
      throw Exception('Bölgeler alınırken hata oluştu: $e');
    }
  }

  static Future<void> addRegion(RegionModel region) async {
    try {
      await _firestore.collection('regions').add(region.toMap());
    } catch (e) {
      throw Exception('Bölge eklenirken hata oluştu: $e');
    }
  }

  static Future<void> updateRegion(String regionId, RegionModel region) async {
    try {
      await _firestore
          .collection('regions')
          .doc(regionId)
          .update(region.toMap());
    } catch (e) {
      throw Exception('Bölge güncellenirken hata oluştu: $e');
    }
  }

  static Future<void> deleteRegion(String regionId) async {
    try {
      await _firestore.collection('regions').doc(regionId).delete();
    } catch (e) {
      throw Exception('Bölge silinirken hata oluştu: $e');
    }
  }

  static Future<List<UserModel>> getUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Kullanıcılar alınırken hata oluştu: $e');
    }
  }

  static Future<List<UserModel>> getUsersByRole(String role) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: role)
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('$role kullanıcıları alınırken hata oluştu: $e');
    }
  }

  static Future<List<UserModel>> getUsersByRegion(String regionId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('regionId', isEqualTo: regionId)
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Bölge kullanıcıları alınırken hata oluştu: $e');
    }
  }

  static Future<void> updateUserRole(String userId, String newRole) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Kullanıcı rolü güncellenirken hata oluştu: $e');
    }
  }

  static Future<void> assignUserToRegion(String userId, String regionId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'regionId': regionId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Kullanıcı bölgeye atanırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getDrivers() async {
    try {
      final snapshot = await _firestore
          .collection('drivers')
          .where('isActive', isEqualTo: true)
          .where('status', isNotEqualTo: 'deleted')
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));

      final activeDrivers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] == true;
        final isNotDeleted = data['isDeleted'] != true;
        final hasValidStatus =
            data['status'] != 'deleted' && data['status'] != 'inactive';

        final finalIsActive = data['isActive'] == null ? true : isActive;
        final finalIsNotDeleted =
            data['isDeleted'] == null ? true : isNotDeleted;
        final finalHasValidStatus =
            data['status'] == null ? true : hasValidStatus;

        if (finalIsActive && finalIsNotDeleted && finalHasValidStatus) {
          data['id'] = doc.id;
          activeDrivers.add(data);
        }
      }

      return activeDrivers;
    } catch (e) {
      print('[FirestoreService] Error fetching drivers: $e');
      throw Exception('Şoförler alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getDriversByRegion(
      String regionId) async {
    try {
      final snapshot = await _firestore
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('status', isNotEqualTo: 'deleted')
          .get();

      final activeDrivers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['isActive'] == true;
        final isNotDeleted = data['isDeleted'] != true;
        final hasValidStatus =
            data['status'] != 'deleted' && data['status'] != 'inactive';

        final finalIsActive = data['isActive'] == null ? true : isActive;
        final finalIsNotDeleted =
            data['isDeleted'] == null ? true : isNotDeleted;
        final finalHasValidStatus =
            data['status'] == null ? true : hasValidStatus;

        if (finalIsActive && finalIsNotDeleted && finalHasValidStatus) {
          data['id'] = doc.id;
          activeDrivers.add(data);
        }
      }

      return activeDrivers;
    } catch (e) {
      throw Exception('Bölge şoförleri alınırken hata oluştu: $e');
    }
  }

  static Future<void> updateDriverStatus(String driverId, bool isActive) async {
    try {
      await _firestore.collection('drivers').doc(driverId).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Şoför durumu güncellenirken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getServices() async {
    try {
      final snapshot = await _firestore.collection('services').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Servisler alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getServicesByRegion(
      String regionId) async {
    try {
      final snapshot = await _firestore
          .collection('services')
          .where('regionId', isEqualTo: regionId)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Bölge servisleri alınırken hata oluştu: $e');
    }
  }

  static Future<void> createService({
    required String driverId,
    required String regionId,
    required String vehiclePlate,
    required DateTime scheduledTime,
    required String serviceType,
  }) async {
    try {
      await _firestore.collection('services').add({
        'driverId': driverId,
        'regionId': regionId,
        'vehiclePlate': vehiclePlate,
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'serviceType': serviceType,
        'status': 'planned',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Servis oluşturulurken hata oluştu: $e');
    }
  }

  static Future<Map<String, int>> getStatistics() async {
    try {
      final usersSnapshot = await _firestore.collection('users').get();
      final driversSnapshot = await _firestore.collection('drivers').get();
      final regionsSnapshot = await _firestore.collection('regions').get();
      final servicesSnapshot = await _firestore.collection('services').get();

      final passengers = usersSnapshot.docs
          .where((doc) => doc.data()['role'] == 'Yolcu')
          .length;
      final drivers = usersSnapshot.docs
          .where((doc) => doc.data()['role'] == 'Şoför')
          .length;

      final activeDrivers = driversSnapshot.docs.where((doc) {
        final data = doc.data();
        final isActive = data['isActive'] == true;
        final isNotDeleted = data['isDeleted'] != true;
        final hasValidStatus =
            data['status'] != 'deleted' && data['status'] != 'inactive';

        final finalIsActive = data['isActive'] == null ? true : isActive;
        final finalIsNotDeleted =
            data['isDeleted'] == null ? true : isNotDeleted;
        final finalHasValidStatus =
            data['status'] == null ? true : hasValidStatus;

        return finalIsActive && finalIsNotDeleted && finalHasValidStatus;
      }).length;

      return {
        'totalUsers': usersSnapshot.docs.length,
        'totalPassengers': passengers,
        'totalDrivers': drivers,
        'totalRegions': regionsSnapshot.docs.length,
        'totalServices': servicesSnapshot.docs.length,
        'activeDrivers': activeDrivers,
      };
    } catch (e) {
      throw Exception('İstatistikler alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages() async {
    try {
      final snapshot = await _firestore
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Mesajlar alınırken hata oluştu: $e');
    }
  }

  static Future<void> deleteMessage(String messageId) async {
    try {
      await _firestore.collection('messages').doc(messageId).delete();
    } catch (e) {
      throw Exception('Mesaj silinirken hata oluştu: $e');
    }
  }

  static Stream<QuerySnapshot> getDriverLocations() {
    return _firestore.collection('live_locations').snapshots();
  }

  static Future<Map<String, dynamic>?> getDriverLocation(
      String driverId) async {
    try {
      final driverDoc =
          await _firestore.collection('drivers').doc(driverId).get();
      if (!driverDoc.exists) {
        return null;
      }

      final driverData = driverDoc.data()!;
      final isActive = driverData['isActive'] == true;
      final isNotDeleted = driverData['isDeleted'] != true;
      final hasValidStatus = driverData['status'] != 'deleted' &&
          driverData['status'] != 'inactive';

      if (!isActive || !isNotDeleted || !hasValidStatus) {
        return null;
      }

      final locationDoc =
          await _firestore.collection('live_locations').doc(driverId).get();

      if (locationDoc.exists) {
        final data = locationDoc.data()!;
        data['id'] = locationDoc.id;
        return data;
      }

      return null;
    } catch (e) {
      print('[FirestoreService] Error getting driver location: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getPassengers() async {
    try {
      print('[FirestoreService] Fetching passengers from Firestore');
      final snapshot = await _firestore
          .collection('passengers')
          .orderBy('name')
          .get(const GetOptions(source: Source.serverAndCache));
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('[FirestoreService] Error fetching passengers: $e');
      throw Exception('Yolcular alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getPassengersByRegion(
      String regionId) async {
    try {
      final snapshot = await _firestore
          .collection('passengers')
          .where('regionId', isEqualTo: regionId)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Bölge yolcuları alınırken hata oluştu: $e');
    }
  }

  static Future<void> addPassenger({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String regionId,
    String? driverId,
    double? latitude,
    double? longitude,
    String? stopName,
  }) async {
    try {
      print('[FirestoreService] Yolcu ekleniyor: $name, Bölge: $regionId');
      final passengerData = {
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'regionId': regionId,
        'driverId': driverId,
        'isActive': true,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (latitude != null && longitude != null) {
        passengerData.addAll({
          'stopLat': latitude,
          'stopLng': longitude,
          'latitude': latitude,
          'longitude': longitude,
        });
        if (stopName != null && stopName.isNotEmpty) {
          passengerData['stopName'] = stopName;
        } else {
          passengerData['stopName'] = address;
        }
        print(
            '[FirestoreService] Koordinatlar eklendi: ($latitude, $longitude)');
      } else {
        print(
            '[FirestoreService] Koordinat bilgisi yok, varsayılan değerler kullanılıyor');
        passengerData.addAll({
          'stopLat': 41.0082,
          'stopLng': 28.9784,
          'latitude': 41.0082,
          'longitude': 28.9784,
          'stopName': address,
        });
      }
      await _firestore.collection('passengers').add(passengerData);
      print('[FirestoreService] Yolcu başarıyla eklendi: $name');
    } catch (e) {
      print('[FirestoreService] Yolcu ekleme hatası: $e');
      throw Exception('Yolcu eklenirken hata oluştu: $e');
    }
  }

  static Future<void> updatePassenger(
      String passengerId, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('passengers').doc(passengerId).update(data);
    } catch (e) {
      throw Exception('Yolcu güncellenirken hata oluştu: $e');
    }
  }

  static Future<void> deletePassenger(String passengerId) async {
    try {
      await _firestore.collection('passengers').doc(passengerId).delete();
    } catch (e) {
      throw Exception('Yolcu silinirken hata oluştu: $e');
    }
  }

  static Future<void> assignPassengerToDriver(
      String passengerId, String? driverId) async {
    try {
      await _firestore.collection('passengers').doc(passengerId).update({
        'driverId': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Yolcu şoföre atanırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getRoutes() async {
    try {
      final snapshot = await _firestore
          .collection('routes')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Rotalar alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getRoutesByDriver(
      String driverId) async {
    try {
      final snapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Şoför rotaları alınırken hata oluştu: $e');
    }
  }

  static Future<void> createRoute({
    required String driverId,
    required String regionId,
    required String routeName,
    required List<Map<String, dynamic>> stops,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      await _firestore.collection('routes').add({
        'driverId': driverId,
        'regionId': regionId,
        'routeName': routeName,
        'stops': stops,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Rota oluşturulurken hata oluştu: $e');
    }
  }

  static Future<void> updateRoute(
      String routeId, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('routes').doc(routeId).update(data);
    } catch (e) {
      throw Exception('Rota güncellenirken hata oluştu: $e');
    }
  }

  static Future<void> addStopToRoute(
      String routeId, Map<String, dynamic> newStop) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) {
        throw Exception('Rota bulunamadı');
      }
      final routeData = routeDoc.data() as Map<String, dynamic>;
      List<dynamic> currentStops = List.from(routeData['stops'] ?? []);
      currentStops.add(newStop);
      await _firestore.collection('routes').doc(routeId).update({
        'stops': currentStops,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Rotaya durak eklenirken hata oluştu: $e');
    }
  }

  static Future<void> removeStopFromRoute(String routeId, int stopIndex) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) {
        throw Exception('Rota bulunamadı');
      }
      final routeData = routeDoc.data() as Map<String, dynamic>;
      List<dynamic> currentStops = List.from(routeData['stops'] ?? []);
      if (stopIndex >= 0 && stopIndex < currentStops.length) {
        currentStops.removeAt(stopIndex);
        await _firestore.collection('routes').doc(routeId).update({
          'stops': currentStops,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception('Geçersiz durak indeksi');
      }
    } catch (e) {
      throw Exception('Rotadan durak silinirken hata oluştu: $e');
    }
  }

  static Future<void> updateStopInRoute(
      String routeId, int stopIndex, Map<String, dynamic> updatedStop) async {
    try {
      final routeDoc = await _firestore.collection('routes').doc(routeId).get();
      if (!routeDoc.exists) {
        throw Exception('Rota bulunamadı');
      }
      final routeData = routeDoc.data() as Map<String, dynamic>;
      List<dynamic> currentStops = List.from(routeData['stops'] ?? []);
      if (stopIndex >= 0 && stopIndex < currentStops.length) {
        currentStops[stopIndex] = updatedStop;
        await _firestore.collection('routes').doc(routeId).update({
          'stops': currentStops,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception('Geçersiz durak indeksi');
      }
    } catch (e) {
      throw Exception('Rota durağı güncellenirken hata oluştu: $e');
    }
  }

  static Stream<DocumentSnapshot> getRouteStream(String routeId) {
    return _firestore.collection('routes').doc(routeId).snapshots();
  }

  static Future<Map<String, dynamic>?> getActiveRouteForDriver(
      String driverId) async {
    try {
      final snapshot = await _firestore
          .collection('routes')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        data['id'] = snapshot.docs.first.id;
        return data;
      }
      return null;
    } catch (e) {
      throw Exception('Aktif rota alınırken hata oluştu: $e');
    }
  }

  static Future<void> deleteRoute(String routeId) async {
    try {
      await _firestore.collection('routes').doc(routeId).delete();
    } catch (e) {
      throw Exception('Rota silinirken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStops() async {
    try {
      final snapshot =
          await _firestore.collection('enhanced_stops').orderBy('name').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Duraklar alınırken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsByRegion(
      String regionId) async {
    try {
      final snapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Bölge durakları alınırken hata oluştu: $e');
    }
  }

  static Future<void> addStop({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required String regionId,
    String? description,
  }) async {
    try {
      await _firestore.collection('enhanced_stops').add({
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'regionId': regionId,
        'description': description,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Durak eklenirken hata oluştu: $e');
    }
  }

  static Future<void> updateStop(
      String stopId, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('enhanced_stops').doc(stopId).update(data);
    } catch (e) {
      throw Exception('Durak güncellenirken hata oluştu: $e');
    }
  }

  static Future<void> deleteStop(String stopId) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).delete();
    } catch (e) {
      throw Exception('Durak silinirken hata oluştu: $e');
    }
  }

  static Future<void> sendNotificationToAll({
    required String title,
    required String message,
    String? targetRole,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'title': title,
        'message': message,
        'targetRole': targetRole,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Bildirim gönderilirken hata oluştu: $e');
    }
  }

  static Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String message,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': title,
        'message': message,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Kullanıcıya bildirim gönderilirken hata oluştu: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Bildirimler alınırken hata oluştu: $e');
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      throw Exception('Bildirim silinirken hata oluştu: $e');
    }
  }
}
