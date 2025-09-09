import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/stop_model.dart';
import 'firestore_service.dart';
import 'notification_service.dart';
import 'user_session.dart';
class StopTrackingService {
  static const double STOP_RADIUS = 50.0;
  static const int EARLY_ARRIVAL_THRESHOLD = 5;
  static const int MAX_WAIT_TIME = 180;
  static const int WARNING_WAIT_TIME = 30;
  static Future<void> recordStopVisit({
    required String driverId,
    required String stopId,
    required double latitude,
    required double longitude,
    required DateTime arrivalTime,
    String? stopName,
    String? stopAddress,
  }) async {
    try {
      final visitId = '${driverId}_${stopId}_${arrivalTime.millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('stop_visits')
          .doc(visitId)
          .set({
        'driverId': driverId,
        'stopId': stopId,
        'stopName': stopName ?? 'Bilinmeyen Durak',
        'stopAddress': stopAddress ?? '',
        'latitude': latitude,
        'longitude': longitude,
        'arrivalTime': arrivalTime,
        'departureTime': null,
        'waitDuration': null,
        'passengerCount': 0,
        'passengersPickedUp': [],
        'status': 'arrived',
        'isEarlyArrival': false,
        'scheduledTime': null,
        'createdAt': FieldValue.serverTimestamp(),
        'regionId': UserSession.regionId ?? '',
        'vehiclePlate': UserSession.vehiclePlate ?? '',
      });
      print('Durak ziyareti kaydedildi: $stopName');
    } catch (e) {
      print('Durak ziyareti kaydetme hatası: $e');
    }
  }
  static Future<void> recordStopDeparture({
    required String driverId,
    required String stopId,
    required DateTime departureTime,
    required List<String> passengersPickedUp,
  }) async {
    try {
      final visitQuery = await FirebaseFirestore.instance
          .collection('stop_visits')
          .where('driverId', isEqualTo: driverId)
          .where('stopId', isEqualTo: stopId)
          .where('status', isEqualTo: 'arrived')
          .orderBy('arrivalTime', descending: true)
          .limit(1)
          .get();
      if (visitQuery.docs.isNotEmpty) {
        final visitDoc = visitQuery.docs.first;
        final arrivalTime = (visitDoc.data()['arrivalTime'] as Timestamp).toDate();
        final waitDuration = departureTime.difference(arrivalTime).inSeconds;
        await visitDoc.reference.update({
          'departureTime': departureTime,
          'waitDuration': waitDuration,
          'passengerCount': passengersPickedUp.length,
          'passengersPickedUp': passengersPickedUp,
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('Durak ayrılma kaydı güncellendi. Bekleme süresi: ${waitDuration}s');
      }
    } catch (e) {
      print('Durak ayrılma kaydetme hatası: $e');
    }
  }
  static Future<void> checkStopProximity({
    required String driverId,
    required Position currentPosition,
  }) async {
    try {
      final stopsQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('isActive', isEqualTo: true)
          .where('regionId', isEqualTo: UserSession.regionId ?? '')
          .get();
      for (final stopDoc in stopsQuery.docs) {
        final stopData = stopDoc.data();
        final stopLat = stopData['latitude']?.toDouble() ?? 0.0;
        final stopLng = stopData['longitude']?.toDouble() ?? 0.0;
        final stopId = stopDoc.id;
        final stopName = stopData['name'] ?? 'Bilinmeyen Durak';
        final stopAddress = stopData['address'] ?? '';
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          stopLat,
          stopLng,
        );
        if (distance <= STOP_RADIUS) {
          await _handleStopArrival(
            driverId: driverId,
            stopId: stopId,
            stopName: stopName,
            stopAddress: stopAddress,
            latitude: stopLat,
            longitude: stopLng,
            currentPosition: currentPosition,
          );
        } else {
          await _handleStopDeparture(
            driverId: driverId,
            stopId: stopId,
          );
        }
      }
    } catch (e) {
      print('Durak yakınlık kontrolü hatası: $e');
    }
  }
  static Future<void> _handleStopArrival({
    required String driverId,
    required String stopId,
    required String stopName,
    required String stopAddress,
    required double latitude,
    required double longitude,
    required Position currentPosition,
  }) async {
    try {
      final existingVisitQuery = await FirebaseFirestore.instance
          .collection('stop_visits')
          .where('driverId', isEqualTo: driverId)
          .where('stopId', isEqualTo: stopId)
          .where('status', isEqualTo: 'arrived')
          .get();
      if (existingVisitQuery.docs.isEmpty) {
        final arrivalTime = DateTime.now();
        await recordStopVisit(
          driverId: driverId,
          stopId: stopId,
          latitude: latitude,
          longitude: longitude,
          arrivalTime: arrivalTime,
          stopName: stopName,
          stopAddress: stopAddress,
        );
        await _checkEarlyArrival(
          driverId: driverId,
          stopId: stopId,
          arrivalTime: arrivalTime,
        );
        await NotificationService.sendToUser(
          userId: driverId,
          title: 'Durağa Varış',
          message: '$stopName durağına vardınız. Yolcuları bekleyiniz.',
        );
        await _notifyPassengersAtStop(stopId);
      }
    } catch (e) {
      print('Durağa varış işlemi hatası: $e');
    }
  }
  static Future<void> _handleStopDeparture({
    required String driverId,
    required String stopId,
  }) async {
    try {
      final activeVisitQuery = await FirebaseFirestore.instance
          .collection('stop_visits')
          .where('driverId', isEqualTo: driverId)
          .where('stopId', isEqualTo: stopId)
          .where('status', isEqualTo: 'arrived')
          .get();
      if (activeVisitQuery.docs.isNotEmpty) {
        final departureTime = DateTime.now();
        final passengersQuery = await FirebaseFirestore.instance
            .collection('passengers')
            .where('stopId', isEqualTo: stopId)
            .where('driverId', isEqualTo: driverId)
            .where('isActive', isEqualTo: true)
            .get();
        final passengerIds = passengersQuery.docs.map((doc) => doc.id).toList();
        await recordStopDeparture(
          driverId: driverId,
          stopId: stopId,
          departureTime: departureTime,
          passengersPickedUp: passengerIds,
        );
      }
    } catch (e) {
      print('Duraktan ayrılış işlemi hatası: $e');
    }
  }
  static Future<void> _checkEarlyArrival({
    required String driverId,
    required String stopId,
    required DateTime arrivalTime,
  }) async {
    try {
      final pastVisitsQuery = await FirebaseFirestore.instance
          .collection('stop_visits')
          .where('driverId', isEqualTo: driverId)
          .where('stopId', isEqualTo: stopId)
          .where('status', isEqualTo: 'completed')
          .orderBy('arrivalTime', descending: true)
          .limit(10)
          .get();
      if (pastVisitsQuery.docs.length >= 3) {
        final pastArrivals = pastVisitsQuery.docs
            .map((doc) => (doc.data()['arrivalTime'] as Timestamp).toDate())
            .toList();
        final avgHour = pastArrivals
            .map((date) => date.hour)
            .reduce((a, b) => a + b) / pastArrivals.length;
        final avgMinute = pastArrivals
            .map((date) => date.minute)
            .reduce((a, b) => a + b) / pastArrivals.length;
        final expectedTime = DateTime(
          arrivalTime.year,
          arrivalTime.month,
          arrivalTime.day,
          avgHour.round(),
          avgMinute.round(),
        );
        final timeDifference = expectedTime.difference(arrivalTime).inMinutes;
        if (timeDifference > EARLY_ARRIVAL_THRESHOLD) {
          await NotificationService.sendEarlyArrivalNotification(
            userId: driverId,
            passengerName: 'Durak',
            minutesEarly: timeDifference,
          );
          final visitQuery = await FirebaseFirestore.instance
              .collection('stop_visits')
              .where('driverId', isEqualTo: driverId)
              .where('stopId', isEqualTo: stopId)
              .where('status', isEqualTo: 'arrived')
              .orderBy('arrivalTime', descending: true)
              .limit(1)
              .get();
          if (visitQuery.docs.isNotEmpty) {
            await visitQuery.docs.first.reference.update({
              'isEarlyArrival': true,
              'scheduledTime': expectedTime,
              'earlyMinutes': timeDifference,
            });
          }
        }
      }
    } catch (e) {
      print('Erken gelme kontrolü hatası: $e');
    }
  }
  static Future<void> _notifyPassengersAtStop(String stopId) async {
    try {
      final passengersQuery = await FirebaseFirestore.instance
          .collection('passengers')
          .where('stopId', isEqualTo: stopId)
          .where('isActive', isEqualTo: true)
          .get();
      for (final passengerDoc in passengersQuery.docs) {
        await NotificationService.sendToUser(
          userId: passengerDoc.id,
          title: 'Servis Geldi',
          message: 'Servis durağınıza ulaştı. Lütfen hazır olun.',
        );
      }
    } catch (e) {
      print('Yolcu bildirim hatası: $e');
    }
  }
  static Future<Map<String, dynamic>> getStopStatistics({
    required String driverId,
    required String stopId,
    int? lastDays,
  }) async {
    try {
      var query = FirebaseFirestore.instance
          .collection('stop_visits')
          .where('stopId', isEqualTo: stopId)
          .where('status', isEqualTo: 'completed');
      if (driverId != 'admin') {
        query = query.where('driverId', isEqualTo: driverId);
      }
      if (lastDays != null) {
        final startDate = DateTime.now().subtract(Duration(days: lastDays));
        query = query.where('arrivalTime', isGreaterThan: startDate);
      }
      final visitsQuery = await query.orderBy('arrivalTime', descending: true).get();
      if (visitsQuery.docs.isEmpty) {
        return {
          'totalVisits': 0,
          'averageWaitTime': 0,
          'totalPassengers': 0,
          'averagePassengers': 0,
          'earlyArrivals': 0,
          'lastVisit': null,
        };
      }
      final visits = visitsQuery.docs.map((doc) => doc.data()).toList();
      final totalVisits = visits.length;
      final totalWaitTime = visits
          .where((visit) => visit['waitDuration'] != null)
          .map((visit) => visit['waitDuration'] as int)
          .fold(0, (sum, duration) => sum + duration);
      final averageWaitTime = totalWaitTime / totalVisits;
      final totalPassengers = visits
          .map((visit) => visit['passengerCount'] as int? ?? 0)
          .fold(0, (sum, count) => sum + count);
      final averagePassengers = totalPassengers / totalVisits;
      final earlyArrivals = visits
          .where((visit) => visit['isEarlyArrival'] == true)
          .length;
      final lastVisit = visits.isNotEmpty 
          ? (visits.first['arrivalTime'] as Timestamp).toDate()
          : null;
      return {
        'totalVisits': totalVisits,
        'averageWaitTime': averageWaitTime.round(),
        'totalPassengers': totalPassengers,
        'averagePassengers': averagePassengers,
        'earlyArrivals': earlyArrivals,
        'lastVisit': lastVisit,
      };
    } catch (e) {
      print('Durak istatistikleri alma hatası: $e');
      return {};
    }
  }
  static Future<List<Map<String, dynamic>>> getDailyStopReport({
    required String driverId,
    DateTime? date,
  }) async {
    try {
      final targetDate = date ?? DateTime.now();
      final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      var visitsQuery = FirebaseFirestore.instance
          .collection('stop_visits')
          .where('arrivalTime', isGreaterThanOrEqualTo: startOfDay)
          .where('arrivalTime', isLessThan: endOfDay);
      if (driverId != 'admin') {
        visitsQuery = visitsQuery.where('driverId', isEqualTo: driverId);
      }
      final visitsSnapshot = await visitsQuery.orderBy('arrivalTime').get();
      return visitsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'stopName': data['stopName'],
          'stopAddress': data['stopAddress'],
          'arrivalTime': (data['arrivalTime'] as Timestamp).toDate(),
          'departureTime': data['departureTime'] != null 
              ? (data['departureTime'] as Timestamp).toDate() 
              : null,
          'waitDuration': data['waitDuration'],
          'passengerCount': data['passengerCount'],
          'isEarlyArrival': data['isEarlyArrival'] ?? false,
          'earlyMinutes': data['earlyMinutes'],
          'status': data['status'],
        };
      }).toList();
    } catch (e) {
      print('Günlük durak raporu alma hatası: $e');
      return [];
    }
  }
}

// Updated


// Updated Again

