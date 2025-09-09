import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'notification_service.dart';
import 'geocoding_service.dart';

class EnhancedStopManagementService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<String?> createEnhancedStop({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required String regionId,
    required List<String> passengerIds,
    String? driverId,
    int order = 0,
    bool isMainRoad = false,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final validatedCoordinates =
          await GeocodingService.validateAndFixCoordinates(
        address: address,
        latitude: latitude,
        longitude: longitude,
      );
      if (validatedCoordinates == null) {
        print('❌ Durak koordinatları doğrulanamadı: $address');
        return null;
      }
      final stopData = {
        'name': name,
        'address': address,
        'latitude': validatedCoordinates['latitude']!,
        'longitude': validatedCoordinates['longitude']!,
        'regionId': regionId,
        'passengerIds': passengerIds,
        'driverId': driverId,
        'order': order,
        'isActive': true,
        'isMainRoad': isMainRoad,
        'isCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'passengerCount': passengerIds.length,
        'estimatedArrivalTime': null,
        'actualArrivalTime': null,
        'status': 'pending',
        'coordinatesValidated': true,
        ...?additionalData,
      };
      final docRef =
          await _firestore.collection('enhanced_stops').add(stopData);
      await NotificationService.instance.sendRegionNotification(
        regionId: regionId,
        title: 'Yeni Durak Eklendi',
        message: '$name durağı rotaya eklendi.',
      );
      print(
          '✅ Gelişmiş durak oluşturuldu (koordinatlar doğrulandı): ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ Gelişmiş durak oluşturma hatası: $e');
      return null;
    }
  }

  static Future<bool> updateEnhancedStop(
    String stopId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        ...updates,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Durak güncellendi: $stopId');
      return true;
    } catch (e) {
      print('❌ Durak güncelleme hatası: $e');
      return false;
    }
  }

  static Future<String?> createStopFromMapSelection({
    required double latitude,
    required double longitude,
    required String address,
    required String passengerId,
  }) async {
    try {
      print('🚀 === DURAK OLUŞTURMA BAŞLADI ===');
      print('📍 Konum: ($latitude, $longitude)');
      print('📋 Adres: $address');
      print('👤 Yolcu ID: $passengerId');
      print('🔍 Kullanıcı bilgileri getiriliyor...');
      final userDoc =
          await _firestore.collection('users').doc(passengerId).get();
      if (!userDoc.exists) {
        print('❌ Kullanıcı bulunamadı: $passengerId');
        return null;
      }
      print('✅ Kullanıcı bulundu');
      final userData = userDoc.data()!;
      final passengerName = userData['name'] ?? 'Bilinmeyen Yolcu';
      String? regionId = userData['regionId'];
      print('👤 Yolcu Adı: $passengerName');
      print('🏢 Bölge ID (users): $regionId');
      if (regionId == null || regionId.isEmpty) {
        try {
          final pdoc =
              await _firestore.collection('passengers').doc(passengerId).get();
          if (pdoc.exists) {
            regionId = (pdoc.data()?['regionId'] as String?) ?? regionId;
            print('🔎 Bölge (passengers) bulundu: $regionId');
          }
        } catch (_) {}
      }
      if (regionId == null || regionId.isEmpty) {
        try {
          final dQuery = await _firestore
              .collection('drivers')
              .where('isActive', isEqualTo: true)
              .limit(1)
              .get();
          if (dQuery.docs.isNotEmpty) {
            regionId = dQuery.docs.first.data()['regionId'] as String?;
            print('🔎 Bölge (aktif şoför) bulundu: $regionId');
          }
        } catch (_) {}
      }
      if (regionId == null || regionId.isEmpty) {
        try {
          final r = await _firestore.collection('regions').limit(2).get();
          if (r.docs.length == 1) {
            regionId = r.docs.first.id;
            print('🔎 Bölge (tek kayıt) kullanıldı: $regionId');
          }
        } catch (_) {}
      }
      if (regionId == null || regionId.isEmpty) {
        print('❌ Bölge çözümlenemedi, durak oluşturulamadı: $passengerId');
        return null;
      }
      try {
        await _firestore.collection('users').doc(passengerId).set({
          'regionId': regionId,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
      String? driverId = userData['driverId'];
      if (driverId == null || driverId.isEmpty) {
        print('🔍 Kullanıcının driverId\'si yok, bölgeden şoför aranıyor...');
        final driversQuery = await _firestore
            .collection('drivers')
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (driversQuery.docs.isNotEmpty) {
          driverId = driversQuery.docs.first.id;
          print('✅ Bölge şoförü bulundu: $driverId');
          await _firestore.collection('users').doc(passengerId).update({
            'driverId': driverId,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('✅ Kullanıcının driverId\'si güncellendi');
        } else {
          print('⚠️ Bu bölgede aktif şoför bulunamadı: $regionId');
        }
      }
      const double proximityThreshold = 100.0;

      final nearbyStops = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();

      DocumentReference<Map<String, dynamic>>? existingRef;
      double? minDistance;

      for (final doc in nearbyStops.docs) {
        final data = doc.data();
        final stopLat = (data['latitude'] ?? data['lat']) as num?;
        final stopLng = (data['longitude'] ?? data['lng']) as num?;

        if (stopLat != null && stopLng != null) {
          final distance = Geolocator.distanceBetween(
            latitude,
            longitude,
            stopLat.toDouble(),
            stopLng.toDouble(),
          );

          if (distance <= proximityThreshold) {
            if (minDistance == null || distance < minDistance) {
              minDistance = distance;
              existingRef = doc.reference;
            }
          }
        }
      }

      if (existingRef != null) {
        print(
            '♻️ Yakın durak bulundu (${minDistance?.toStringAsFixed(1)}m), yolcu ekleniyor: ${existingRef.id}');
      }

      if (existingRef != null) {
        print(
            '♻️ Yakın durak bulundu (${minDistance?.toStringAsFixed(1)}m), yolcu ekleniyor: ${existingRef.id}');

        final existingStopDoc = await existingRef.get();
        final existingData = existingStopDoc.data();
        if (existingData != null) {
          final existingPassengerIds =
              List<String>.from(existingData['passengerIds'] ?? []);
          final existingPassengerNames =
              List<String>.from(existingData['passengerNames'] ?? []);
          final existingAddresses =
              List<String>.from(existingData['addresses'] ?? []);

          if (!existingPassengerIds.contains(passengerId)) {
            existingPassengerIds.add(passengerId);
            existingPassengerNames.add(passengerName);
            existingAddresses.add(address);

            await existingRef.update({
              'passengerIds': existingPassengerIds,
              'passengerNames': existingPassengerNames,
              'addresses': existingAddresses,
              'passengerCount': existingPassengerIds.length,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
            print('✅ Yolcu mevcut durağa eklendi: ${existingRef.id}');
          } else {
            final passengerIndex = existingPassengerIds.indexOf(passengerId);
            if (passengerIndex != -1 &&
                passengerIndex < existingAddresses.length) {
              existingAddresses[passengerIndex] = address;
              await existingRef.update({
                'addresses': existingAddresses,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
              print('✅ Yolcu adresi güncellendi: ${existingRef.id}');
            }
          }
        }

        return existingRef.id;
      }

      final existingByArray = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('passengerIds', arrayContains: passengerId)
          .limit(1)
          .get();

      if (existingByArray.docs.isNotEmpty) {
        existingRef = existingByArray.docs.first.reference;
        print(
            '♻️ Yolcunun mevcut durağı bulundu, güncelleniyor: ${existingRef.id}');
        await existingRef.update({
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'lat': latitude,
          'lng': longitude,
          'driverId': driverId,
          'passengerName': passengerName,
          'phoneNumber': userData['phone'],
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ Mevcut durak güncellendi: ${existingRef.id}');
        return existingRef.id;
      }
      final stopData = {
        'name': '$passengerName Durağı',
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'lat': latitude,
        'lng': longitude,
        'regionId': regionId,
        'passengerIds': [passengerId],
        'passengerId': passengerId,
        'driverId': driverId,
        'order': 0,
        'isActive': true,
        'isMainRoad': false,
        'isCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'passengerCount': 1,
        'estimatedArrivalTime': null,
        'actualArrivalTime': null,
        'status': 'pending',
        'coordinatesValidated': true,
        'createdFromMap': true,
        'source': 'map_selection',
        'passengerName': passengerName,
        'phoneNumber': userData['phone'],
      };
      print('💾 Firestore\'a durak yazılıyor...');
      print('📄 Durak verisi: $stopData');
      final docRef =
          await _firestore.collection('enhanced_stops').add(stopData);
      print('✅ Firestore\'a yazıldı: ${docRef.id}');
      final newStopId = docRef.id;
      await _deactivateExistingPassengerStops(
        passengerId: passengerId,
        regionId: regionId,
        latitude: latitude,
        longitude: longitude,
        address: address,
        excludeStopId: newStopId,
      );
      try {
        await NotificationService.instance.sendRegionNotification(
          regionId: regionId,
          title: 'Yeni Durak Eklendi',
          message: '$passengerName haritadan yeni durak oluşturdu.',
        );
        print('📢 Bildirim gönderildi');
      } catch (e) {
        print('⚠️ Bildirim gönderme hatası: $e');
      }
      print('🎉 === DURAK OLUŞTURMA TAMAMLANDI ===');
      print('✅ Harita seçiminden durak oluşturuldu: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ Harita seçiminden durak oluşturma hatası: $e');
      return null;
    }
  }

  static Future<void> _deactivateExistingPassengerStops({
    required String passengerId,
    required String regionId,
    required double latitude,
    required double longitude,
    required String address,
    String? excludeStopId,
  }) async {
    try {
      final byArray = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .get();
      final bySingular = await _firestore
          .collection('enhanced_stops')
          .where('passengerId', isEqualTo: passengerId)
          .where('isActive', isEqualTo: true)
          .get();
      final List<DocumentSnapshot<Map<String, dynamic>>> toDeactivate = [
        ...byArray.docs,
        ...bySingular.docs,
      ];

      final byAddress = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('address', isEqualTo: address)
          .get();

      for (final doc in byAddress.docs) {
        final data = doc.data();
        final docPassengerIds = List<String>.from(data['passengerIds'] ?? []);

        if (docPassengerIds.length == 1 &&
            docPassengerIds.contains(passengerId)) {
          toDeactivate.add(doc);
        }
      }
      if (toDeactivate.isEmpty) return;
      final batch = _firestore.batch();
      final uniqueRefs = <String, DocumentReference>{};
      for (final doc in toDeactivate) {
        if (excludeStopId != null && doc.id == excludeStopId) {
          print('🛡️ Yeni oluşturulan durak korunuyor: ${doc.id}');
          continue;
        }
        uniqueRefs[doc.id] = doc.reference;
      }
      if (uniqueRefs.isNotEmpty) {
        uniqueRefs.forEach((_, ref) {
          batch.update(ref, {
            'isActive': false,
            'lastUpdated': FieldValue.serverTimestamp(),
            'deactivatedBySystem': true,
          });
        });
        await batch.commit();
      }
      print(
          '🧹 Eski/duplikat aktif duraklar pasifleştirildi: ${uniqueRefs.length} adet');
    } catch (e) {
      print('❌ Mevcut durakları pasifleştirme hatası: $e');
    }
  }

  static Future<bool> removePassengerFromMapStop(String passengerId) async {
    try {
      final byArray = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .get();
      final bySingular = await _firestore
          .collection('enhanced_stops')
          .where('passengerId', isEqualTo: passengerId)
          .where('isActive', isEqualTo: true)
          .get();
      final allDocs = <DocumentSnapshot<Map<String, dynamic>>>[
        ...byArray.docs,
        ...bySingular.docs,
      ];
      for (final doc in allDocs) {
        final stopData = doc.data();
        if (stopData == null) {
          continue;
        }
        final passengerIds =
            List<String>.from((stopData['passengerIds'] ?? []) as List);
        final hasOnlySingular = passengerIds.isEmpty &&
            ((stopData['passengerId'] as String?) == passengerId);
        if (hasOnlySingular ||
            (passengerIds.length == 1 && passengerIds.contains(passengerId))) {
          await doc.reference.update({
            'isActive': false,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('✅ Tek yolculu durak silindi: ${doc.id}');
        } else {
          passengerIds.remove(passengerId);
          await doc.reference.update({
            'passengerIds': passengerIds,
            'passengerCount': passengerIds.length,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('✅ Yolcu duraktan kaldırıldı: ${doc.id}');
        }
      }
      return true;
    } catch (e) {
      print('❌ Yolcu duraktan kaldırma hatası: $e');
      return false;
    }
  }

  static Future<bool> addPassengerToStop(
      String stopId, String passengerId) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'passengerIds': FieldValue.arrayUnion([passengerId]),
        'passengerCount': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Yolcu durağa eklendi: $passengerId -> $stopId');
      return true;
    } catch (e) {
      print('❌ Yolcu ekleme hatası: $e');
      return false;
    }
  }

  static Future<bool> removePassengerFromStop(
      String stopId, String passengerId) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'passengerIds': FieldValue.arrayRemove([passengerId]),
        'passengerCount': FieldValue.increment(-1),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Yolcu duraktan çıkarıldı: $passengerId -> $stopId');
      return true;
    } catch (e) {
      print('❌ Yolcu çıkarma hatası: $e');
      return false;
    }
  }

  static Future<bool> updateStopStatus(String stopId, String status) async {
    try {
      final updateData = {
        'status': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (status == 'completed') {
        updateData['isCompleted'] = true;
        updateData['actualArrivalTime'] = FieldValue.serverTimestamp();
      } else if (status == 'in_progress') {
        updateData['estimatedArrivalTime'] = FieldValue.serverTimestamp();
      }
      await _firestore
          .collection('enhanced_stops')
          .doc(stopId)
          .update(updateData);
      print('✅ Durak durumu güncellendi: $stopId -> $status');
      return true;
    } catch (e) {
      print('❌ Durak durumu güncelleme hatası: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsForRegion(
      String regionId) async {
    try {
      print('🔍 Bölge harita durakları alınıyor - RegionId: $regionId');
      final col = _firestore.collection('enhanced_stops');
      QuerySnapshot<Map<String, dynamic>> snapCreated;
      try {
        snapCreated = await col
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .where('createdFromMap', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .get();
      } catch (_) {
        snapCreated = await col
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .where('createdFromMap', isEqualTo: true)
            .get();
      }
      QuerySnapshot<Map<String, dynamic>> snapSource;
      try {
        snapSource = await col
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .where('source', isEqualTo: 'map_selection')
            .orderBy('createdAt', descending: true)
            .get();
      } catch (_) {
        snapSource = await col
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: true)
            .where('source', isEqualTo: 'map_selection')
            .get();
      }
      final Map<String, Map<String, dynamic>> byId = {};
      for (final d in [...snapCreated.docs, ...snapSource.docs]) {
        final data = d.data();
        data['id'] = d.id;
        data['source'] = data['source'] ??
            (data['createdFromMap'] == true ? 'map_selection' : null);
        byId[d.id] = data;
      }
      final Map<String, Map<String, dynamic>> latestByPassenger = {};
      for (final m in byId.values) {
        final List<dynamic> pids = (m['passengerIds'] as List<dynamic>?) ?? [];
        if (pids.isEmpty) continue;
        final pid = pids.first.toString();
        final createdAt = m['createdAt'];
        if (!latestByPassenger.containsKey(pid)) {
          latestByPassenger[pid] = m;
        } else {
          final prev = latestByPassenger[pid]!;
          final prevCreated = prev['createdAt'];
          final bool isNewer =
              (createdAt is Timestamp && prevCreated is Timestamp)
                  ? createdAt.compareTo(prevCreated) > 0
                  : true;
          if (isNewer) latestByPassenger[pid] = m;
        }
      }
      final List<Map<String, dynamic>> stops =
          latestByPassenger.values.toList();
      print('✅ Bulunan durak sayısı: ${stops.length}');
      if (stops.isEmpty) {
        print('❌ Bu bölgede hiç aktif durak bulunamadı!');
        print(
            '🔍 Pasif duraklar kontrol ediliyor ve yanlış bölge durakları temizleniyor...');
        final inactiveStops = await _firestore
            .collection('enhanced_stops')
            .where('regionId', isEqualTo: regionId)
            .where('isActive', isEqualTo: false)
            .get();
        if (inactiveStops.docs.isNotEmpty) {
          print(
              '⚠️ Bu bölgede ${inactiveStops.docs.length} adet PASİF durak var!');
          print('🔧 Pasif durakları aktif hale getiriliyor...');
          final batch = _firestore.batch();
          for (final doc in inactiveStops.docs) {
            final data = doc.data();
            print(
                '  ✅ Aktifleştiriliyor: ${data['address']} - ${data['passengerName']}');
            batch.update(doc.reference, {
              'isActive': true,
              'lastUpdated': FieldValue.serverTimestamp(),
              'reactivatedBySystem': true,
            });
          }
          await batch.commit();
          print('🎉 ${inactiveStops.docs.length} durak aktif hale getirildi!');
          final reactivatedStops = await _firestore
              .collection('enhanced_stops')
              .where('regionId', isEqualTo: regionId)
              .where('isActive', isEqualTo: true)
              .get();
          final reactivatedList = reactivatedStops.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
          print(
              '✅ Aktifleştirme sonrası durak sayısı: ${reactivatedList.length}');
          return reactivatedList;
        }
        print('🔍 TÜM DURAKLAR KONTROL EDİLİYOR...');
        final allStops = await _firestore.collection('enhanced_stops').get();
        print('📊 Toplam enhanced_stops sayısı: ${allStops.docs.length}');
        if (allStops.docs.isNotEmpty) {
          print('📋 TÜM DURAKLAR:');
          for (final doc in allStops.docs.take(10)) {
            final data = doc.data();
            print('  - ID: ${doc.id}');
            print('    RegionId: ${data['regionId']}');
            print('    İsActive: ${data['isActive']}');
            print('    Adres: ${data['address']}');
            print('    Yolcu: ${data['passengerName']}');
            print('    CreatedAt: ${data['createdAt']}');
            print('    ---');
          }
        }
      }
      final Map<String, Map<String, dynamic>> uniqueByPassengerId = {};
      final List<Map<String, dynamic>> unknownPassengerStops = [];
      for (final stop in stops) {
        final String? pid = (stop['passengerId'] as String?)?.trim();
        final List<dynamic> pids =
            (stop['passengerIds'] as List<dynamic>?) ?? [];
        final String? effectivePid = (pid != null && pid.isNotEmpty)
            ? pid
            : (pids.isNotEmpty ? pids.first.toString() : null);
        if (effectivePid == null) {
          unknownPassengerStops.add(stop);
          continue;
        }
        final Timestamp? createdAt = stop['createdAt'] as Timestamp?;
        if (!uniqueByPassengerId.containsKey(effectivePid)) {
          uniqueByPassengerId[effectivePid] = stop;
        } else {
          final existing = uniqueByPassengerId[effectivePid]!;
          final Timestamp? existingCreated =
              existing['createdAt'] as Timestamp?;
          final bool isNewer = (createdAt != null && existingCreated != null)
              ? createdAt.compareTo(existingCreated) > 0
              : false;
          if (isNewer) {
            uniqueByPassengerId[effectivePid] = stop;
          }
        }
      }
      final List<Map<String, dynamic>> deduped =
          uniqueByPassengerId.values.toList();
      final Set<String> keepIds = deduped.map((s) => s['id'] as String).toSet();
      final List<String> toDeactivate = [];
      for (final stop in stops) {
        final id = stop['id'] as String;
        if (!keepIds.contains(id)) {
          toDeactivate.add(id);
        }
      }
      if (toDeactivate.isNotEmpty) {
        final batch = _firestore.batch();
        for (final id in toDeactivate) {
          batch.update(
            _firestore.collection('enhanced_stops').doc(id),
            {
              'isActive': false,
              'lastUpdated': FieldValue.serverTimestamp(),
              'deactivatedBySystem': true,
            },
          );
        }
        await batch.commit();
        print(
            '🧹 Tekilleştirme: ${toDeactivate.length} eski kopya pasifleştirildi');
      }
      if (unknownPassengerStops.isNotEmpty) {
        final batch = _firestore.batch();
        for (final s in unknownPassengerStops) {
          final id = s['id'] as String?;
          if (id != null && id.isNotEmpty) {
            batch.update(
              _firestore.collection('enhanced_stops').doc(id),
              {
                'isActive': false,
                'lastUpdated': FieldValue.serverTimestamp(),
                'deactivatedBySystem': true,
              },
            );
          }
        }
        await batch.commit();
        print(
            '⚠️ ${unknownPassengerStops.length} yolcu ID\'siz durak pasifleştirildi');
      }
      return deduped;
    } catch (e) {
      print('❌ Bölge durakları alma hatası: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsForDriver(
      String driverId) async {
    try {
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Şoför durakları alma hatası: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getStopForPassenger(
      String passengerId) async {
    try {
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }
      return null;
    } catch (e) {
      print('❌ Yolcu durağı alma hatası: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> findNearbyStops({
    required double latitude,
    required double longitude,
    required String regionId,
    double radiusMeters = 500.0,
  }) async {
    try {
      final stopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      List<Map<String, dynamic>> nearbyStops = [];
      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();
        final stopLat = data['latitude'] as double?;
        final stopLng = data['longitude'] as double?;
        if (stopLat != null && stopLng != null) {
          final distance = Geolocator.distanceBetween(
            latitude,
            longitude,
            stopLat,
            stopLng,
          );
          if (distance <= radiusMeters) {
            data['id'] = doc.id;
            data['distance'] = distance;
            nearbyStops.add(data);
          }
        }
      }
      nearbyStops.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));
      return nearbyStops;
    } catch (e) {
      print('❌ Yakın durak arama hatası: $e');
      return [];
    }
  }

  static Future<bool> deleteStop(String stopId) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'isActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Durak silindi: $stopId');
      return true;
    } catch (e) {
      print('❌ Durak silme hatası: $e');
      return false;
    }
  }

  static Future<bool> updateStopOrder(String stopId, int newOrder) async {
    try {
      await _firestore.collection('enhanced_stops').doc(stopId).update({
        'order': newOrder,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Durak sırası güncellendi: $stopId -> $newOrder');
      return true;
    } catch (e) {
      print('❌ Durak sırası güncelleme hatası: $e');
      return false;
    }
  }

  static Future<bool> consolidateStops(
      List<String> stopIds, String newStopName) async {
    try {
      final batch = _firestore.batch();
      List<Map<String, dynamic>> stopsData = [];
      List<String> allPassengerIds = [];
      double avgLat = 0, avgLng = 0;
      String regionId = '';
      for (final stopId in stopIds) {
        final doc =
            await _firestore.collection('enhanced_stops').doc(stopId).get();
        if (doc.exists) {
          final data = doc.data()!;
          stopsData.add(data);
          final passengerIds = List<String>.from(data['passengerIds'] ?? []);
          allPassengerIds.addAll(passengerIds);
          avgLat += data['latitude'] as double;
          avgLng += data['longitude'] as double;
          regionId = data['regionId'] as String;
          batch.update(doc.reference, {
            'isActive': false,
            'consolidatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (stopsData.isNotEmpty) {
        avgLat /= stopsData.length;
        avgLng /= stopsData.length;
        final newStopRef = _firestore.collection('enhanced_stops').doc();
        batch.set(newStopRef, {
          'name': newStopName,
          'address': 'Birleştirilmiş Durak',
          'latitude': avgLat,
          'longitude': avgLng,
          'regionId': regionId,
          'passengerIds': allPassengerIds.toSet().toList(),
          'passengerCount': allPassengerIds.toSet().length,
          'isActive': true,
          'isMainRoad': true,
          'isConsolidated': true,
          'originalStopIds': stopIds,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        await batch.commit();
        print(
            '✅ Duraklar birleştirildi: ${stopIds.join(", ")} -> ${newStopRef.id}');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Durak birleştirme hatası: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getStopStatistics(String stopId) async {
    try {
      final doc =
          await _firestore.collection('enhanced_stops').doc(stopId).get();
      if (!doc.exists) {
        return {};
      }
      final data = doc.data()!;
      final historySnapshot = await _firestore
          .collection('stop_history')
          .where('stopId', isEqualTo: stopId)
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      int totalVisits = historySnapshot.docs.length;
      double avgWaitTime = 0;
      if (totalVisits > 0) {
        for (final historyDoc in historySnapshot.docs) {
          final historyData = historyDoc.data();
          final waitTime = historyData['waitTime'] as double? ?? 0;
          avgWaitTime += waitTime;
        }
        avgWaitTime /= totalVisits;
      }
      return {
        'stopId': stopId,
        'name': data['name'],
        'passengerCount': data['passengerCount'] ?? 0,
        'totalVisits': totalVisits,
        'averageWaitTime': avgWaitTime,
        'isMainRoad': data['isMainRoad'] ?? false,
        'status': data['status'] ?? 'pending',
        'lastUpdated': data['lastUpdated'],
      };
    } catch (e) {
      print('❌ Durak istatistikleri alma hatası: $e');
      return {};
    }
  }

  static Future<void> recordStopVisit({
    required String stopId,
    required String driverId,
    required DateTime arrivalTime,
    required DateTime departureTime,
    required List<String> boardedPassengerIds,
  }) async {
    try {
      final waitTime =
          departureTime.difference(arrivalTime).inMinutes.toDouble();
      await _firestore.collection('stop_history').add({
        'stopId': stopId,
        'driverId': driverId,
        'arrivalTime': Timestamp.fromDate(arrivalTime),
        'departureTime': Timestamp.fromDate(departureTime),
        'waitTime': waitTime,
        'boardedPassengerIds': boardedPassengerIds,
        'passengerCount': boardedPassengerIds.length,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('✅ Durak ziyareti kaydedildi: $stopId');
    } catch (e) {
      print('❌ Durak ziyareti kaydetme hatası: $e');
    }
  }

  static Future<void> _updatePassengerStopInfo(
    String passengerId,
    String stopId,
    String stopName,
  ) async {
    try {
      await _firestore.collection('users').doc(passengerId).update({
        'stopId': stopId,
        'stopName': stopName,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Yolcu durak bilgisi güncellendi: $passengerId');
    } catch (e) {
      print('❌ Yolcu durak bilgisi güncelleme hatası: $e');
    }
  }

  static Future<String> _generateStopName(
    double latitude,
    double longitude,
    String address,
  ) async {
    try {
      final addressParts = address.split(',');
      if (addressParts.isNotEmpty) {
        final streetName = addressParts.first.trim();
        if (streetName.isNotEmpty) {
          return '$streetName Durağı';
        }
      }
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final street = placemark.street ?? placemark.thoroughfare ?? '';
        final subLocality = placemark.subLocality ?? '';
        if (street.isNotEmpty) {
          return '$street Durağı';
        } else if (subLocality.isNotEmpty) {
          return '$subLocality Durağı';
        }
      }
      return 'Durak (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})';
    } catch (e) {
      print('❌ Durak adı oluşturma hatası: $e');
      return 'Yeni Durak';
    }
  }

  static Future<List<Map<String, dynamic>>> getMapSelectionStops(
      String regionId) async {
    try {
      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('source', isEqualTo: 'map_selection')
          .orderBy('createdAt', descending: true)
          .get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Harita seçimi durakları alma hatası: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsBySource({
    required String regionId,
    String? source,
  }) async {
    try {
      Query query = _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('temporarilyInactive', isEqualTo: false);
      if (source != null) {
        query = query.where('source', isEqualTo: source);
      }
      final querySnapshot =
          await query.orderBy('createdAt', descending: true).get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Kaynak tipine göre durak alma hatası: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getActiveStopsByRegionForTracking(
    String regionId,
  ) async {
    try {
      print('🔍 Bölge $regionId için aktif duraklar getiriliyor...');

      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('isDeleted', isEqualTo: false)
          .orderBy('order', descending: false)
          .get();

      final stops = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      print('✅ Bölge $regionId için ${stops.length} aktif durak bulundu');

      stops.sort((a, b) {
        final orderA = a['order'] ?? a['stopOrder'] ?? 0;
        final orderB = b['order'] ?? b['stopOrder'] ?? 0;
        return orderA.compareTo(orderB);
      });

      return stops;
    } catch (e) {
      print('❌ Bölge bazlı durak alma hatası: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>>
      getActiveStopsByRegionNameForTracking(
    String regionName,
  ) async {
    try {
      print('🔍 Bölge adı "$regionName" için aktif durakları getiriliyor...');

      final querySnapshot = await _firestore
          .collection('enhanced_stops')
          .where('isActive', isEqualTo: true)
          .get();

      final stops = querySnapshot.docs.where((doc) {
        final data = doc.data();
        final stopRegion = data['region'] ?? data['regionId'];
        return stopRegion == regionName;
      }).map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      print('✅ Bölge "$regionName" için ${stops.length} aktif durak bulundu');

      stops.sort((a, b) {
        final orderA = a['order'] ?? a['stopOrder'] ?? 0;
        final orderB = b['order'] ?? b['stopOrder'] ?? 0;
        return orderA.compareTo(orderB);
      });

      return stops;
    } catch (e) {
      print('❌ Bölge adına göre durak alma hatası: $e');
      return [];
    }
  }
}

// Updated

