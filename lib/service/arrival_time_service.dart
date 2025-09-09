import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import 'route_optimization_service.dart';

class ArrivalTimeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final RouteOptimizationService _routeService =
      RouteOptimizationService();

  static Future<Map<String, dynamic>?> calculateArrivalTime({
    required String passengerId,
    required String driverId,
  }) async {
    try {
      print(
          '🔍 ArrivalTimeService: Varış süresi hesaplanıyor - Yolcu: $passengerId, Şoför: $driverId');

      final driverLocationDoc =
          await _firestore.collection('live_locations').doc(driverId).get();
      if (!driverLocationDoc.exists) {
        print('⚠️ Şoför konum verisi bulunamadı: $driverId');
        return null;
      }

      final driverData = driverLocationDoc.data()!;
      print(
          '📍 Şoför konum verisi alındı: ${driverData['lat']}, ${driverData['lng']}');

      final driverPosition = Position(
        latitude: driverData['lat'],
        longitude: driverData['lng'],
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      print('📍 Şoför konumu: (${driverData['lat']}, ${driverData['lng']})');

      print('🔍 Enhanced_stops koleksiyonundan durak aranıyor...');
      final stopsQuery = await _firestore
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      print(
          '📊 Enhanced_stops sorgu sonucu: ${stopsQuery.docs.length} durak bulundu');

      if (stopsQuery.docs.isEmpty) {
        print('⚠️ Yolcu için aktif durak bulunamadı: $passengerId');
        print('🔍 Legacy stops koleksiyonu deneniyor...');
        final legacyStopsQuery = await _firestore
            .collection('stops')
            .where('assignedPassengerIds', arrayContains: passengerId)
            .limit(1)
            .get();

        print(
            '📊 Legacy stops sorgu sonucu: ${legacyStopsQuery.docs.length} durak bulundu');

        if (legacyStopsQuery.docs.isEmpty) {
          print('❌ Hiçbir koleksiyonda durak bulunamadı');
          return null;
        }

        final legacyStopDoc = legacyStopsQuery.docs.first;
        final legacyStopData = legacyStopDoc.data();
        print(
            '✅ Legacy durak bulundu: ${legacyStopData['name']} - ${legacyStopData['address']}');

        return {
          'estimatedMinutes': 0,
          'arrivalTime': DateTime.now(),
          'nextStopName':
              legacyStopData['address'] ?? legacyStopData['name'] ?? 'Durak',
          'stopAddress': legacyStopData['address'] ?? '',
          'currentStopIndex': 0,
          'totalStopsCount': 1,
          'distanceToStop': 0.0,
        };
      }

      final stopDoc = stopsQuery.docs.first;
      final stopData = stopDoc.data();

      print('✅ Yolcu durağı bulundu: ${stopData['address']}');
      print('📋 Durak verileri:');
      print('   - ID: ${stopDoc.id}');
      print('   - Address: "${stopData['address']}"');
      print('   - PassengerName: "${stopData['passengerName']}"');
      print('   - Name: "${stopData['name']}"');
      print('   - Latitude: ${stopData['latitude']} / ${stopData['lat']}');
      print('   - Longitude: ${stopData['longitude']} / ${stopData['lng']}');
      print('   - Order: ${stopData['order']}');
      print('   - PassengerIds: ${stopData['passengerIds']}');
      print('   - Raw stopData: $stopData');
      print('🔍 DEBUG: stopData[\'address\'] = "${stopData['address']}"');
      print(
          '🔍 DEBUG: stopData[\'passengerName\'] = "${stopData['passengerName']}"');

      final passengerStop = StopModel(
        id: stopDoc.id,
        driverId: driverId,
        passengerName: stopData['passengerName'] ?? stopData['name'] ?? 'Durak',
        address: stopData['address'] ?? '',
        lat: (stopData['latitude'] ?? stopData['lat'] ?? 0.0).toDouble(),
        lng: (stopData['longitude'] ?? stopData['lng'] ?? 0.0).toDouble(),
        date: DateTime.now(),
        order: stopData['order'] ?? 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        passengerIds: List<String>.from(stopData['passengerIds'] ?? []),
      );

      print(
          '✅ StopModel oluşturuldu: ${passengerStop.passengerName} - ${passengerStop.address}');

      print('🔍 Şoförün tüm durakları aranıyor...');
      final allStopsQuery = await _firestore
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();

      print(
          '📊 Şoför durakları sorgu sonucu: ${allStopsQuery.docs.length} durak bulundu');

      if (allStopsQuery.docs.isEmpty) {
        print('⚠️ Şoför için aktif durak bulunamadı: $driverId');
        print('🔍 Legacy şoför durakları deneniyor...');
        final legacyAllStopsQuery = await _firestore
            .collection('stops')
            .where('driverId', isEqualTo: driverId)
            .get();

        print(
            '📊 Legacy şoför durakları sorgu sonucu: ${legacyAllStopsQuery.docs.length} durak bulundu');

        if (legacyAllStopsQuery.docs.isEmpty) {
          print('❌ Hiçbir koleksiyonda şoför durakları bulunamadı');
          return null;
        }

        final legacyStops = legacyAllStopsQuery.docs.map((doc) {
          final data = doc.data();
          return StopModel(
            id: doc.id,
            driverId: driverId,
            passengerName: data['name'] ?? 'Durak',
            address: data['address'] ?? '',
            lat: (data['latitude'] ?? 0.0).toDouble(),
            lng: (data['longitude'] ?? 0.0).toDouble(),
            date: DateTime.now(),
            order: data['order'] ?? 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            passengerIds: List<String>.from(data['assignedPassengerIds'] ?? []),
          );
        }).toList();

        print('✅ Legacy şoför durakları işlendi: ${legacyStops.length} durak');
        return _calculateETAFromStops(
            driverPosition, passengerStop, legacyStops, driverData);
      }

      final allStops = allStopsQuery.docs.map((doc) {
        final data = doc.data();
        return StopModel(
          id: doc.id,
          driverId: driverId,
          passengerName: data['passengerName'] ?? data['name'] ?? 'Durak',
          address: data['address'] ?? '',
          lat: (data['latitude'] ?? data['lat'] ?? 0.0).toDouble(),
          lng: (data['longitude'] ?? data['lng'] ?? 0.0).toDouble(),
          date: DateTime.now(),
          order: data['order'] ?? 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          passengerIds: List<String>.from(data['passengerIds'] ?? []),
        );
      }).toList();

      print('📊 Toplam durak sayısı: ${allStops.length}');
      print('🔍 Duraklar:');
      for (int i = 0; i < allStops.length; i++) {
        final stop = allStops[i];
        print(
            '   ${i + 1}. ${stop.passengerName} - ${stop.address} (Order: ${stop.order})');
      }

      return _calculateETAFromStops(
          driverPosition, passengerStop, allStops, driverData);
    } catch (e) {
      print('❌ Varış süresi hesaplama hatası: $e');
      return null;
    }
  }

  static Map<String, dynamic> _calculateETAFromStops(
    Position driverPosition,
    StopModel passengerStop,
    List<StopModel> allStops,
    Map<String, dynamic> driverData,
  ) {
    try {
      print('🔍 _calculateETAFromStops başladı');
      print(
          '   - Driver Position: (${driverPosition.latitude}, ${driverPosition.longitude})');
      print(
          '   - Passenger Stop: ${passengerStop.passengerName} - ${passengerStop.address}');
      print('   - Total Stops: ${allStops.length}');

      final optimizedStops = allStops;

      int passengerStopIndex = -1;
      for (int i = 0; i < optimizedStops.length; i++) {
        if (optimizedStops[i].id == passengerStop.id) {
          passengerStopIndex = i;
          break;
        }
      }

      print('   - Passenger Stop Index: $passengerStopIndex');

      if (passengerStopIndex == -1) {
        print('⚠️ Yolcu durağı optimize edilmiş rotada bulunamadı');
        passengerStopIndex = 0;
        print('   - Passenger Stop Index varsayılan olarak 0 yapıldı');
      }

      int estimatedMinutes = 0;
      estimatedMinutes += 5;

      for (int i = 0; i <= passengerStopIndex; i++) {
        estimatedMinutes += 3;
        if (i < passengerStopIndex) {
          estimatedMinutes += 4;
        }
      }

      print('   - Base Estimated Minutes: $estimatedMinutes');

      if (driverData['speed'] != null && driverData['speed'] > 0) {
        final speedFactor = 0.8;
        estimatedMinutes = (estimatedMinutes * speedFactor).round();
        print(
            '   - Speed factor applied: $speedFactor, New estimated minutes: $estimatedMinutes');
      }

      final arrivalTime =
          DateTime.now().add(Duration(minutes: estimatedMinutes));

      final distance = _calculateDistance(
        driverPosition.latitude,
        driverPosition.longitude,
        passengerStop.lat,
        passengerStop.lng,
      );

      print(
          '✅ ETA hesaplandı: $estimatedMinutes dakika, ${distance.toStringAsFixed(1)} km');
      print('📋 Final return data:');
      print('   - estimatedMinutes: $estimatedMinutes');
      print('   - arrivalTime: $arrivalTime');
      print(
          '   - nextStopName: ${passengerStop.address ?? 'Bilinmeyen Durak'}');
      print('   - stopAddress: ${passengerStop.address}');
      print('   - currentStopIndex: ${passengerStopIndex + 1}');
      print('   - totalStopsCount: ${optimizedStops.length}');
      print('   - distanceToStop: $distance');
      print('   - eta: $estimatedMinutes');

      return {
        'estimatedMinutes': estimatedMinutes,
        'arrivalTime': arrivalTime,
        'nextStopName': passengerStop.address ?? 'Bilinmeyen Durak',
        'stopAddress': passengerStop.address,
        'currentStopIndex': passengerStopIndex + 1,
        'totalStopsCount': optimizedStops.length,
        'distanceToStop': distance,
        'eta': estimatedMinutes,
      };
    } catch (e) {
      print('❌ ETA hesaplama hatası: $e');
      return {
        'estimatedMinutes': 0,
        'arrivalTime': DateTime.now(),
        'nextStopName': passengerStop.address ?? 'Bilinmeyen Durak',
        'stopAddress': passengerStop.address,
        'currentStopIndex': 1,
        'totalStopsCount': 1,
        'distanceToStop': 0.0,
        'eta': 0,
      };
    }
  }

  static Future<bool> isDriverActive(String driverId) async {
    try {
      final driverLocationDoc =
          await _firestore.collection('live_locations').doc(driverId).get();
      if (!driverLocationDoc.exists) {
        return false;
      }
      final data = driverLocationDoc.data()!;
      final lastUpdate = (data['timestamp'] as Timestamp?)?.toDate();
      if (lastUpdate == null) {
        return false;
      }
      final now = DateTime.now();
      final difference = now.difference(lastUpdate).inMinutes;
      return difference <= 5;
    } catch (e) {
      print('❌ Şoför aktiflik kontrolü hatası: $e');
      return false;
    }
  }

  static Stream<Map<String, dynamic>?> getArrivalTimeStream({
    required String passengerId,
    required String driverId,
  }) {
    return Stream.periodic(const Duration(seconds: 30), (count) async {
      return await calculateArrivalTime(
        passengerId: passengerId,
        driverId: driverId,
      );
    }).asyncMap((future) => future);
  }

  static double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
}





