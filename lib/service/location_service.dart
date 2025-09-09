import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_session.dart';
class LocationService {
  static LocationService? _instance;
  LocationService._();
  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }
  factory LocationService() => instance;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationSharingActive = false;
  Position? _lastKnownPosition;
  bool get isLocationSharingActive => _isLocationSharingActive;
  Position? get lastKnownPosition => _lastKnownPosition;
  set positionStreamSubscription(StreamSubscription<Position>? subscription) {
    _positionStreamSubscription = subscription;
  }
  StreamSubscription<Position>? get positionStreamSubscription =>
      _positionStreamSubscription;
  Future<bool> checkAndRequestPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Konum izni reddedildi');
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('Konum izni kalıcı olarak reddedildi');
        return false;
      }
      return true;
    } catch (e) {
      print('İzin kontrolü hatası: $e');
      return false;
    }
  }
  Future<void> initializeService() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        print('Konum izni alınamadı');
        return;
      }
      print('LocationService başlatıldı');
    } catch (e) {
      print('LocationService başlatma hatası: $e');
    }
  }
  Future<void> requestAndShareLocation() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        print('Konum izni gerekli');
        return;
      }
      await startLocationSharing();
      UserSession.isLocationSharing = true;
      print('Konum paylaşımı başlatıldı');
    } catch (e) {
      print('Konum paylaşımı başlatma hatası: $e');
    }
  }
  Future<void> updateLocationInBackground() async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return;
      final position = await getCurrentPosition();
      if (position != null) {
        await _updateLocationInFirestore(position);
        await saveLocationToHistory(position);
        _lastKnownPosition = position;
      }
    } catch (e) {
      print('Arka plan konum güncelleme hatası: $e');
    }
  }
  Future<void> checkProximityAndMarkStops() async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return;
      final position = await getCurrentPosition();
      if (position == null) return;
      final nearbyStops = await _getNearbyStops(position);
      for (final stop in nearbyStops) {
        final numLat = (stop['lat'] ?? stop['latitude']) as num? ?? 0;
        final numLng = (stop['lng'] ?? stop['longitude']) as num? ?? 0;
        if (isWithinRadius(
            position, numLat.toDouble(), numLng.toDouble(), 50)) {
          await _markStopAsVisited(stop['id'] as String);
        }
      }
    } catch (e) {
      print('Durak yakınlık kontrolü hatası: $e');
    }
  }
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Mevcut konum alma hatası: $e');
      return null;
    }
  }
  Future<Position?> getCurrentLocation() async {
    return await getCurrentPosition();
  }
  Future<void> startLocationSharing() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) return;
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) async {
          await _updateLocationInFirestore(position);
          await saveLocationToHistory(position);
          _lastKnownPosition = position;
        },
        onError: (error) {
          print('Konum stream hatası: $error');
        },
      );
      _isLocationSharingActive = true;
      UserSession.isLocationSharing = true;
    } catch (e) {
      print('Konum paylaşımı başlatma hatası: $e');
    }
  }
  Future<void> stopLocationSharing() async {
    try {
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _isLocationSharingActive = false;
      UserSession.isLocationSharing = false;
      print('Konum paylaşımı durduruldu');
    } catch (e) {
      print('Konum paylaşımı durdurma hatası: $e');
    }
  }
  Future<void> _updateLocationInFirestore(Position position) async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return;
      await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(userId)
          .set({
        'lat': position.latitude,
        'lng': position.longitude,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'altitude': position.altitude,
        if (UserSession.regionId != null) 'regionId': UserSession.regionId,
        if (UserSession.vehiclePlate != null)
          'vehiclePlate': UserSession.vehiclePlate,
        'isSimulation': false,
        'isActive': true,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Firestore konum güncelleme hatası: $e');
    }
  }
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
  Future<double> getDistanceToLocation(
      double targetLat, double targetLng) async {
    try {
      final position = await getCurrentPosition();
      if (position == null) return 0.0;
      return calculateDistance(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );
    } catch (e) {
      print('Mesafe hesaplama hatası: $e');
      return 0.0;
    }
  }
  bool isWithinRadius(Position position, double targetLat, double targetLng,
      double radiusInMeters) {
    final distance = calculateDistance(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );
    return distance <= radiusInMeters;
  }
  Future<List<Map<String, dynamic>>> getLocationHistory() async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return [];
      final querySnapshot = await FirebaseFirestore.instance
          .collection('location_history')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Konum geçmişi alma hatası: $e');
      return [];
    }
  }
  Future<void> saveLocationToHistory(Position position) async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return;
      await FirebaseFirestore.instance.collection('location_history').add({
        'userId': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'accuracy': position.accuracy,
        'speed': position.speed,
      });
    } catch (e) {
      print('Konum geçmişi kaydetme hatası: $e');
    }
  }
  Future<Position?> getDriverLocation(String driverId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('live_locations')
          .doc(driverId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      final num? latN = (data['lat'] ?? data['latitude']) as num?;
      final num? lngN = (data['lng'] ?? data['longitude']) as num?;
      if (latN == null || lngN == null) return null;
      return Position(
        latitude: latN.toDouble(),
        longitude: lngN.toDouble(),
        timestamp: DateTime.now(),
        accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
        altitude: (data['altitude'] as num?)?.toDouble() ?? 0.0,
        altitudeAccuracy: 0.0,
        heading: (data['heading'] as num?)?.toDouble() ?? 0.0,
        headingAccuracy: 0.0,
        speed: (data['speed'] as num?)?.toDouble() ?? 0.0,
        speedAccuracy: 0.0,
      );
    } catch (e) {
      print('Şoför konumu alma hatası: $e');
      return null;
    }
  }
  Future<List<Map<String, dynamic>>> getNearbyDrivers(
      Position position, double radiusInKm) async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance.collection('live_locations').get();
      final nearbyDrivers = <Map<String, dynamic>>[];
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final num? latN = (data['lat'] ?? data['latitude']) as num?;
        final num? lngN = (data['lng'] ?? data['longitude']) as num?;
        if (latN == null || lngN == null) continue;
        final distance = calculateDistance(
          position.latitude,
          position.longitude,
          latN.toDouble(),
          lngN.toDouble(),
        );
        if (distance <= radiusInKm * 1000) {
          nearbyDrivers.add({
            'driverId': doc.id,
            'distance': distance,
            ...data,
          });
        }
      }
      return nearbyDrivers;
    } catch (e) {
      print('Yakındaki şoförler alma hatası: $e');
      return [];
    }
  }
  Future<List<Map<String, dynamic>>> _getNearbyStops(Position position) async {
    try {
      final userId = UserSession.userId;
      if (userId == null) return [];
      final querySnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('driverId', isEqualTo: userId)
          .where('isCompleted', isEqualTo: false)
          .get();
      return querySnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      print('Yakındaki duraklar alma hatası: $e');
      return [];
    }
  }
  Future<void> _markStopAsVisited(String stopId) async {
    try {
      await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .doc(stopId)
          .update({
        'isCompleted': true,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Durak işaretleme hatası: $e');
    }
  }
  void dispose() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isLocationSharingActive = false;
  }
  bool isLocationAccurate(Position position) {
    return position.accuracy <= 20.0;
  }
  bool isLocationRecent(Position position) {
    final now = DateTime.now();
    final positionTime = position.timestamp ?? now;
    return now.difference(positionTime).inMinutes <= 5;
  }
  bool isSpeedReasonable(Position position) {
    return position.speed <= 50.0;
  }
}





