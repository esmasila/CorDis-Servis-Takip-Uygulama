import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'geocoding_service.dart';

class SimpleStopService {
  static const double _proximityThreshold = 100.0;
  static Future<void> createStopFromAddress({
    required String passengerId,
    required String passengerName,
    required String address,
    required String regionId,
  }) async {
    try {
      if (address.trim().isEmpty) return;

      print(
          '[SimpleStopService] Yolcu adresi işleniyor: $passengerName - $address');

      final coordinates = await _getCoordinatesFromAddress(address);
      if (coordinates == null) {
        print('Adres koordinatlara çevrilemedi: $address');
        return;
      }

      final nearbyStop = await _findNearbyStop(
        coordinates['lat']!,
        coordinates['lng']!,
        regionId,
      );

      if (nearbyStop != null) {
        print(
            '[SimpleStopService] Yakın durak bulundu: ${nearbyStop['name']} (${nearbyStop['distance']?.toStringAsFixed(1)}m)');

        final existingPassengerIds =
            List<String>.from(nearbyStop['passengerIds'] ?? []);
        if (!existingPassengerIds.contains(passengerId)) {
          await _addPassengerToExistingStop(
            nearbyStop['id'],
            passengerId,
            passengerName,
            address,
          );
          print(
              '[SimpleStopService] ✅ Yolcu mevcut durağa eklendi: ${nearbyStop['name']}');
        } else {
          print(
              '[SimpleStopService] ℹ️ Yolcu zaten bu durakta: ${nearbyStop['name']}');
        }
      } else {
        final existingPassengerStop =
            await _findExistingPassengerStop(passengerId, regionId);

        if (existingPassengerStop != null) {
          print(
              '[SimpleStopService] Yolcunun mevcut durağı bulundu, güncelleniyor: ${existingPassengerStop['name']}');

          await _updateStopLocation(
            existingPassengerStop['id'],
            coordinates['lat']!,
            coordinates['lng']!,
            address,
          );

          print(
              '[SimpleStopService] ✅ Mevcut durak güncellendi: ${existingPassengerStop['name']}');
        } else {
          await _createNewStop(
            passengerId: passengerId,
            passengerName: passengerName,
            address: address,
            latitude: coordinates['lat']!,
            longitude: coordinates['lng']!,
            regionId: regionId,
          );
          print('[SimpleStopService] ✅ Yeni durak oluşturuldu: $address');
        }
      }
    } catch (e) {
      print('[SimpleStopService] ❌ Durak oluşturma hatası: $e');
    }
  }

  static Future<Map<String, double>?> _getCoordinatesFromAddress(
      String address) async {
    try {
      final googleCoordinates =
          await GeocodingService.getCoordinatesFromAddress(address);
      if (googleCoordinates != null) {
        return {
          'lat': googleCoordinates['latitude']!,
          'lng': googleCoordinates['longitude']!,
        };
      }
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        final coordinates = {
          'lat': location.latitude,
          'lng': location.longitude,
        };
        print(
            '[SimpleStopService] ✅ Flutter geocoding ile koordinat bulundu: $coordinates');
        return coordinates;
      }
    } catch (e) {
      print('[SimpleStopService] ❌ Geocoding hatası: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _findNearbyStop(
    double latitude,
    double longitude,
    String regionId,
  ) async {
    try {
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();

      Map<String, dynamic>? closestStop;
      double? closestDistance;

      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();
        final stopLat = data['latitude'] as double?;
        final stopLng = data['longitude'] as double?;

        if (stopLat != null && stopLng != null) {
          final distance = _calculateDistance(
            latitude,
            longitude,
            stopLat,
            stopLng,
          );

          if (closestDistance == null || distance < closestDistance) {
            closestDistance = distance;
            closestStop = {
              'id': doc.id,
              'name': data['name'],
              'distance': distance,
              ...data,
            };
          }
        }
      }

      if (closestStop != null &&
          closestDistance != null &&
          closestDistance <= _proximityThreshold) {
        print(
            '[SimpleStopService] En yakın durak bulundu: ${closestStop['name']} (${closestDistance.toStringAsFixed(1)}m)');
        return closestStop;
      }
    } catch (e) {
      print('Yakın durak arama hatası: $e');
    }
    return null;
  }

  static Future<void> _createNewStop({
    required String passengerId,
    required String passengerName,
    required String address,
    required double latitude,
    required double longitude,
    required String regionId,
  }) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc();
      await stopRef.set({
        'id': stopRef.id,
        'name': 'Durak - $address',
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'regionId': regionId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'passengerIds': [passengerId],
        'passengerNames': [passengerName],
        'passengerCount': 1,
      });

      print('[SimpleStopService] ✅ Yeni durak oluşturuldu: ${stopRef.id}');
    } catch (e) {
      print('[SimpleStopService] ❌ Yeni durak oluşturma hatası: $e');
    }
  }

  static Future<void> _addPassengerToExistingStop(
    String stopId,
    String passengerId,
    String passengerName,
    String address,
  ) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc(stopId);

      await stopRef.update({
        'passengerIds': FieldValue.arrayUnion([passengerId]),
        'passengerNames': FieldValue.arrayUnion([passengerName]),
        'passengerCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('[SimpleStopService] ✅ Yolcu durağa eklendi: $passengerName');
    } catch (e) {
      print('[SimpleStopService] ❌ Yolcu ekleme hatası: $e');
    }
  }

  static Future<void> _updateStopLocation(
    String stopId,
    double newLatitude,
    double newLongitude,
    String newAddress,
  ) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc(stopId);

      await stopRef.update({
        'latitude': newLatitude,
        'longitude': newLongitude,
        'address': newAddress,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('[SimpleStopService] ✅ Durak konumu güncellendi: $newAddress');
    } catch (e) {
      print('[SimpleStopService] ❌ Durak güncelleme hatası: $e');
    }
  }

  static Future<Map<String, dynamic>?> _findExistingPassengerStop(
    String passengerId,
    String regionId,
  ) async {
    try {
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('passengerIds', arrayContains: passengerId)
          .get();

      if (stopsSnapshot.docs.isNotEmpty) {
        final data = stopsSnapshot.docs.first.data();
        return {
          'id': stopsSnapshot.docs.first.id,
          'name': data['name'],
          ...data,
        };
      }
    } catch (e) {
      print('Mevcut durak arama hatası: $e');
    }
    return null;
  }

  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  static Future<void> removePassengerFromStop(
    String passengerId,
    String regionId,
  ) async {
    try {
      final stopSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('passengerIds', arrayContains: passengerId)
          .get();

      if (stopSnapshot.docs.isNotEmpty) {
        final stopDoc = stopSnapshot.docs.first;
        final stopData = stopDoc.data();
        final passengerIds = List<String>.from(stopData['passengerIds'] ?? []);
        final passengerNames =
            List<String>.from(stopData['passengerNames'] ?? []);

        passengerIds.remove(passengerId);
        final passengerIndex = passengerNames.indexWhere((name) =>
            name ==
            stopData['passengerNames']
                ?.firstWhere((n) => n == passengerId, orElse: () => ''));
        if (passengerIndex != -1) {
          passengerNames.removeAt(passengerIndex);
        }

        if (passengerIds.isEmpty) {
          await stopDoc.reference.update({
            'isActive': false,
            'passengerIds': [],
            'passengerNames': [],
            'passengerCount': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print(
              '[SimpleStopService] ✅ Durak deaktif edildi (yolcu kalmadı): ${stopDoc.id}');
        } else {
          await stopDoc.reference.update({
            'passengerIds': passengerIds,
            'passengerNames': passengerNames,
            'passengerCount': passengerIds.length,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('[SimpleStopService] ✅ Yolcu duraktan çıkarıldı: $passengerId');
        }
      }
    } catch (e) {
      print('[SimpleStopService] ❌ Yolcu çıkarma hatası: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsForRegion(
      String regionId) async {
    try {
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('source', isEqualTo: 'map_selection')
          .orderBy('createdAt', descending: true)
          .get();

      return stopsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('[SimpleStopService] ❌ Bölge durakları getirme hatası: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getStopsForDriver(
      String driverId) async {
    try {
      print('🔍 Şoför durakları getiriliyor. Şoför ID: $driverId');

      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();

      if (!driverDoc.exists) {
        print('❌ Şoför bulunamadı: $driverId');
        return [];
      }

      final driverData = driverDoc.data()!;
      final regionId = driverData['regionId'];
      final vehiclePlate = driverData['vehiclePlate'] ?? driverData['plate'];

      print('📍 Şoför bilgileri - Bölge: $regionId, Plaka: $vehiclePlate');

      if (regionId == null) {
        print('❌ Şoförün bölgesi tanımlı değil: $driverId');
        return [];
      }

      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .where('source', isEqualTo: 'map_selection')
          .orderBy('createdAt', descending: true)
          .get();

      final List<Map<String, dynamic>> driverStops = [];

      for (final doc in stopsSnapshot.docs) {
        final stopData = doc.data();
        final passengerIds = List<String>.from(stopData['passengerIds'] ?? []);

        print(
            '🔍 Durak kontrol ediliyor: ${doc.id}, Yolcu sayısı: ${passengerIds.length}');

        final List<String> assignedPassengerIds = [];
        final List<String> assignedPassengerNames = [];

        for (int i = 0; i < passengerIds.length; i++) {
          final passengerId = passengerIds[i];
          try {
            final passengerDoc = await FirebaseFirestore.instance
                .collection('passengers')
                .doc(passengerId)
                .get();

            if (passengerDoc.exists) {
              final passengerData = passengerDoc.data()!;
              final passengerDriverId = passengerData['driverId'];
              final passengerVehiclePlate = passengerData['vehiclePlate'];

              print(
                  '👤 Yolcu kontrol: $passengerId, Atanmış şoför: $passengerDriverId, Plaka: $passengerVehiclePlate');

              bool isAssigned = false;
              if (passengerDriverId == driverId) {
                isAssigned = true;
                print('✅ Yolcu şoför ID ile eşleşti');
              } else if (vehiclePlate != null &&
                  passengerVehiclePlate == vehiclePlate) {
                isAssigned = true;
                print('✅ Yolcu plaka ile eşleşti');
              }

              if (isAssigned) {
                assignedPassengerIds.add(passengerId);
                final passengerNames =
                    List<String>.from(stopData['passengerNames'] ?? []);
                if (i < passengerNames.length) {
                  assignedPassengerNames.add(passengerNames[i]);
                } else {
                  assignedPassengerNames
                      .add(passengerData['name'] ?? 'İsimsiz');
                }
              }
            } else {
              print('❌ Yolcu belgesi bulunamadı: $passengerId');
            }
          } catch (e) {
            print('❌ Yolcu kontrol hatası ($passengerId): $e');
          }
        }

        if (assignedPassengerIds.isNotEmpty) {
          final driverStop = {
            'id': doc.id,
            ...stopData,
            'assignedPassengerIds': assignedPassengerIds,
            'assignedPassengerNames': assignedPassengerNames,
            'assignedPassengerCount': assignedPassengerIds.length,
          };
          driverStops.add(driverStop);
          print(
              '✅ Durak eklendi: ${doc.id}, Atanmış yolcu sayısı: ${assignedPassengerIds.length}');
        } else {
          print('⚠️ Durakta şoföre atanmış yolcu yok: ${doc.id}');
        }
      }

      print('📊 Şoför için toplam durak sayısı: ${driverStops.length}');
      return driverStops;
    } catch (e) {
      print('❌ Şoför durakları getirme hatası: $e');
      return [];
    }
  }
}





