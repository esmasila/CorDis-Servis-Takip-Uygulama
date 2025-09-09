import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'directions_service.dart';
class ETACalculationService {
  static final Map<String, StreamSubscription> _etaSubscriptions = {};
  static final Map<String, Timer> _calculationTimers = {};
  static final Map<String, ETAData> _cachedETAs = {};
  static Future<Duration?> calculateETA({
    required LatLng driverLocation,
    required LatLng passengerStop,
    required List<LatLng> remainingStops,
    bool useTrafficData = true,
  }) async {
    try {
      Duration totalDuration = Duration.zero;
      LatLng currentLocation = driverLocation;
      for (final stop in remainingStops) {
        final segmentDuration = await _calculateSegmentDuration(
          currentLocation,
          stop,
          useTrafficData,
        );
        if (segmentDuration != null) {
          totalDuration += segmentDuration;
          totalDuration += const Duration(minutes: 2);
          currentLocation = stop;
        }
      }
      final finalSegmentDuration = await _calculateSegmentDuration(
        currentLocation,
        passengerStop,
        useTrafficData,
      );
      if (finalSegmentDuration != null) {
        totalDuration += finalSegmentDuration;
      }
      return totalDuration;
    } catch (e) {
      print('ETA hesaplama hatası: $e');
      return _calculateSimpleETA(driverLocation, passengerStop, remainingStops);
    }
  }
  static Future<Duration?> _calculateSegmentDuration(
    LatLng origin,
    LatLng destination,
    bool useTrafficData,
  ) async {
    try {
      final directionsResult = await DirectionsService().getDirections(
        baslangic: origin,
        hedef: destination,
      );
      if (directionsResult != null && directionsResult.isValid) {
        final durationText = directionsResult.toplamSure;
        final duration = _parseDurationFromText(durationText);
        return duration;
      }
    } catch (e) {
      print('Directions API hatası: $e');
    }
    return _calculateSimpleSegmentDuration(origin, destination);
  }
  static Duration _calculateSimpleETA(
    LatLng driverLocation,
    LatLng passengerStop,
    List<LatLng> remainingStops,
  ) {
    double totalDistance = 0.0;
    LatLng currentLocation = driverLocation;
    for (final stop in remainingStops) {
      totalDistance += Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        stop.latitude,
        stop.longitude,
      );
      currentLocation = stop;
    }
    totalDistance += Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      passengerStop.latitude,
      passengerStop.longitude,
    );
    final averageSpeedMs = 25 * 1000 / 3600;
    final travelTimeSeconds = totalDistance / averageSpeedMs;
    final stopWaitTime = remainingStops.length * 2 * 60;
    return Duration(seconds: (travelTimeSeconds + stopWaitTime).round());
  }
  static Duration _calculateSimpleSegmentDuration(
    LatLng origin,
    LatLng destination,
  ) {
    final distance = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final averageSpeedMs = 25 * 1000 / 3600;
    final travelTimeSeconds = distance / averageSpeedMs;
    return Duration(seconds: travelTimeSeconds.round());
  }
  static Duration _parseDurationFromText(String durationText) {
    try {
      final text = durationText.toLowerCase();
      int totalMinutes = 0;
      final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(text);
      if (hourMatch != null) {
        totalMinutes += int.parse(hourMatch.group(1)!) * 60;
      }
      final minMatch = RegExp(r'(\d+)\s*min').firstMatch(text);
      if (minMatch != null) {
        totalMinutes += int.parse(minMatch.group(1)!);
      }
      return Duration(minutes: totalMinutes);
    } catch (e) {
      print('Süre parse hatası: $e');
      return const Duration(minutes: 15);
    }
  }
  static Stream<ETAData> getRealtimeETA(String passengerId) {
    final controller = StreamController<ETAData>.broadcast();
    _etaSubscriptions[passengerId]?.cancel();
    _calculationTimers[passengerId]?.cancel();
    _etaSubscriptions[passengerId] = FirebaseFirestore.instance
        .collection('passengers')
        .doc(passengerId)
        .snapshots()
        .listen((passengerDoc) async {
      if (!passengerDoc.exists) return;
      final passengerData = passengerDoc.data()!;
      final driverId = passengerData['driverId'] as String?;
      if (driverId == null) {
        controller.add(ETAData(
          passengerId: passengerId,
          estimatedArrival: null,
          isDriverActive: false,
          lastUpdated: DateTime.now(),
        ));
        return;
      }
      _startETACalculation(passengerId, driverId, controller);
    });
    return controller.stream;
  }
  static void _startETACalculation(
    String passengerId,
    String driverId,
    StreamController<ETAData> controller,
  ) {
    _calculationTimers[passengerId] = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        try {
          final etaData = await _calculateRealtimeETA(passengerId, driverId);
          if (etaData != null) {
            _cachedETAs[passengerId] = etaData;
            controller.add(etaData);
            await _saveETAToFirebase(etaData);
          }
        } catch (e) {
          print('Gerçek zamanlı ETA hesaplama hatası: $e');
        }
      },
    );
    _calculateRealtimeETA(passengerId, driverId).then((etaData) {
      if (etaData != null) {
        _cachedETAs[passengerId] = etaData;
        controller.add(etaData);
        _saveETAToFirebase(etaData);
      }
    });
  }
  static Future<ETAData?> _calculateRealtimeETA(
    String passengerId,
    String driverId,
  ) async {
    try {
      final driverLocationDoc = await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (!driverLocationDoc.exists) {
        return ETAData(
          passengerId: passengerId,
          estimatedArrival: null,
          isDriverActive: false,
          lastUpdated: DateTime.now(),
        );
      }
      final driverData = driverLocationDoc.data()!;
      final driverLocation = LatLng(
        driverData['lat'],
        driverData['lng'],
      );
      final isDriverActive = driverData['isActive'] ?? false;
      if (!isDriverActive) {
        return ETAData(
          passengerId: passengerId,
          estimatedArrival: null,
          isDriverActive: false,
          lastUpdated: DateTime.now(),
        );
      }
      final passengerStopQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('passengerIds', arrayContains: passengerId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (passengerStopQuery.docs.isEmpty) {
        return ETAData(
          passengerId: passengerId,
          estimatedArrival: null,
          isDriverActive: true,
          lastUpdated: DateTime.now(),
          message: 'Aktif durak bulunamadı',
        );
      }
      final stopData = passengerStopQuery.docs.first.data();
      final passengerStop = LatLng(
        stopData['latitude'],
        stopData['longitude'],
      );
      final remainingStopsQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .where('order', isLessThan: stopData['order'])
          .orderBy('order')
          .get();
      final remainingStops = remainingStopsQuery.docs
          .map((doc) => LatLng(doc.data()['latitude'], doc.data()['longitude']))
          .toList();
      final eta = await calculateETA(
        driverLocation: driverLocation,
        passengerStop: passengerStop,
        remainingStops: remainingStops,
      );
      final estimatedArrival = eta != null 
          ? DateTime.now().add(eta)
          : null;
      return ETAData(
        passengerId: passengerId,
        driverId: driverId,
        estimatedArrival: estimatedArrival,
        estimatedDuration: eta,
        isDriverActive: true,
        driverLocation: driverLocation,
        passengerStop: passengerStop,
        remainingStopsCount: remainingStops.length,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      print('Gerçek zamanlı ETA hesaplama hatası: $e');
      return null;
    }
  }
  static Future<void> _saveETAToFirebase(ETAData etaData) async {
    try {
      await FirebaseFirestore.instance
          .collection('eta_calculations')
          .doc(etaData.passengerId)
          .set(etaData.toMap(), SetOptions(merge: true));
    } catch (e) {
      print('ETA Firebase kaydetme hatası: $e');
    }
  }
  static void stopETAStream(String passengerId) {
    _etaSubscriptions[passengerId]?.cancel();
    _etaSubscriptions.remove(passengerId);
    _calculationTimers[passengerId]?.cancel();
    _calculationTimers.remove(passengerId);
    _cachedETAs.remove(passengerId);
  }
  static void stopAllETAStreams() {
    for (final subscription in _etaSubscriptions.values) {
      subscription.cancel();
    }
    _etaSubscriptions.clear();
    for (final timer in _calculationTimers.values) {
      timer.cancel();
    }
    _calculationTimers.clear();
    _cachedETAs.clear();
  }
  static ETAData? getCachedETA(String passengerId) {
    return _cachedETAs[passengerId];
  }
  static Future<Map<String, ETAData>> calculateETAForAllPassengers(
    String driverId,
  ) async {
    final etaMap = <String, ETAData>{};
    try {
      final passengersQuery = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .get();
      for (final doc in passengersQuery.docs) {
        final data = doc.data();
        final passengerIds = List<String>.from(data['passengerIds'] ?? []);
        if (passengerIds.isNotEmpty) {
          final passengerId = passengerIds.first;
          final etaData = await _calculateRealtimeETA(passengerId, driverId);
          if (etaData != null) {
            etaMap[passengerId] = etaData;
          }
        }
      }
    } catch (e) {
      print('Toplu ETA hesaplama hatası: $e');
    }
    return etaMap;
  }
  static Future<void> clearOldETAData() async {
    try {
      final cutoffTime = DateTime.now().subtract(const Duration(hours: 1));
      final oldETAQuery = await FirebaseFirestore.instance
          .collection('eta_calculations')
          .where('lastUpdated', isLessThan: Timestamp.fromDate(cutoffTime))
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in oldETAQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Eski ETA verileri temizlendi: ${oldETAQuery.docs.length} kayıt');
    } catch (e) {
      print('ETA veri temizleme hatası: $e');
    }
  }
  static Future<void> initialize({
    required String passengerId,
    required String driverId,
  }) async {
    try {
      print('ETACalculationService başlatılıyor - Passenger: $passengerId, Driver: $driverId');
      await _calculateRealtimeETA(passengerId, driverId);
    } catch (e) {
      print('ETA servis başlatma hatası: $e');
    }
  }
  static Stream<ETAData> getPassengerETAStream(String passengerId) {
    return getRealtimeETA(passengerId);
  }
  static void dispose() {
    stopAllETAStreams();
    print('ETACalculationService temizlendi');
  }
}
class ETAData {
  final String passengerId;
  final String? driverId;
  final DateTime? estimatedArrival;
  final Duration? estimatedDuration;
  final bool isDriverActive;
  final LatLng? driverLocation;
  final LatLng? passengerStop;
  final int remainingStopsCount;
  final DateTime lastUpdated;
  final String? message;
  ETAData({
    required this.passengerId,
    this.driverId,
    this.estimatedArrival,
    this.estimatedDuration,
    required this.isDriverActive,
    this.driverLocation,
    this.passengerStop,
    this.remainingStopsCount = 0,
    required this.lastUpdated,
    this.message,
  });
  bool get isValid {
    final now = DateTime.now();
    return lastUpdated.isAfter(now.subtract(const Duration(minutes: 5)));
  }
  int? get remainingMinutes {
    if (estimatedArrival == null) return null;
    final now = DateTime.now();
    final difference = estimatedArrival!.difference(now);
    return difference.inMinutes.clamp(0, double.infinity).toInt();
  }
  String get statusMessage {
    if (message != null) return message!;
    if (!isDriverActive) {
      return 'Şoför aktif değil';
    }
    if (estimatedArrival == null) {
      return 'Varış süresi hesaplanıyor...';
    }
    final minutes = remainingMinutes;
    if (minutes == null) return 'Bilinmiyor';
    if (minutes <= 0) {
      return 'Şoför yakında';
    } else if (minutes == 1) {
      return '1 dakika';
    } else {
      return '$minutes dakika';
    }
  }
  Map<String, dynamic> toMap() {
    return {
      'passengerId': passengerId,
      'driverId': driverId,
      'estimatedArrival': estimatedArrival?.millisecondsSinceEpoch,
      'estimatedDurationMinutes': estimatedDuration?.inMinutes,
      'isDriverActive': isDriverActive,
      'driverLatitude': driverLocation?.latitude,
      'driverLongitude': driverLocation?.longitude,
      'passengerLatitude': passengerStop?.latitude,
      'passengerLongitude': passengerStop?.longitude,
      'remainingStopsCount': remainingStopsCount,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'message': message,
    };
  }
  factory ETAData.fromMap(Map<String, dynamic> map) {
    return ETAData(
      passengerId: map['passengerId'],
      driverId: map['driverId'],
      estimatedArrival: map['estimatedArrival'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['estimatedArrival'])
          : null,
      estimatedDuration: map['estimatedDurationMinutes'] != null
          ? Duration(minutes: map['estimatedDurationMinutes'])
          : null,
      isDriverActive: map['isDriverActive'] ?? false,
      driverLocation: map['driverLatitude'] != null && map['driverLongitude'] != null
          ? LatLng(map['driverLatitude'], map['driverLongitude'])
          : null,
      passengerStop: map['passengerLatitude'] != null && map['passengerLongitude'] != null
          ? LatLng(map['passengerLatitude'], map['passengerLongitude'])
          : null,
      remainingStopsCount: map['remainingStopsCount'] ?? 0,
      lastUpdated: (map['lastUpdated'] as Timestamp).toDate(),
      message: map['message'],
    );
  }
  @override
  String toString() {
    return 'ETAData(passengerId: $passengerId, estimatedArrival: $estimatedArrival, isDriverActive: $isDriverActive)';
  }
}

// Updated


// Updated Again

