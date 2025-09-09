import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'geocoding_service.dart';
import '../services/config_service.dart';

class AutoStopService {
  static const double _proximityThreshold = 100.0;
  static const double _mainRoadSearchRadius = 1000.0;
  static Future<void> processPassengerAddress({
    required String passengerId,
    required String passengerName,
    required String address,
    required String regionId,
  }) async {
    try {
      if (address.trim().isEmpty) return;

      print(
          '[AutoStopService] Yolcu adresi işleniyor: $passengerName - $address');

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
        print('[AutoStopService] Yakın durak bulundu: ${nearbyStop['name']}');

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
              '[AutoStopService] ✅ Yolcu mevcut durağa eklendi: ${nearbyStop['name']}');
        } else {
          print(
              '[AutoStopService] ℹ️ Yolcu zaten bu durakta: ${nearbyStop['name']}');
        }
        return;
      }

      final existingPassengerStop =
          await _findExistingPassengerStop(passengerId, regionId);

      if (existingPassengerStop != null) {
        print(
            '[AutoStopService] Yolcunun mevcut durağı bulundu, güncelleniyor: ${existingPassengerStop['name']}');

        await _updateStopLocation(
          existingPassengerStop['id'],
          coordinates['lat']!,
          coordinates['lng']!,
          address,
        );

        print(
            '[AutoStopService] ✅ Mevcut durak güncellendi: ${existingPassengerStop['name']}');
        return;
      }

      final optimalStopLocation = await _findOptimalStopLocationByRoadWidth(
        homeLatitude: coordinates['lat']!,
        homeLongitude: coordinates['lng']!,
        regionId: regionId,
      );

      await _createNewAutoStop(
        passengerId: passengerId,
        passengerName: passengerName,
        address: address,
        homeLatitude: coordinates['lat']!,
        homeLongitude: coordinates['lng']!,
        stopLatitude: optimalStopLocation['lat']!,
        stopLongitude: optimalStopLocation['lng']!,
        stopAddress: optimalStopLocation['address']!,
        regionId: regionId,
      );
      print(
          '[AutoStopService] ✅ Ana yol üzerinde yeni otomatik durak oluşturuldu: ${optimalStopLocation['address']}');
    } catch (e) {
      print('[AutoStopService] ❌ Otomatik durak işlemi hatası: $e');
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
            '[AutoStopService] ✅ Flutter geocoding ile koordinat bulundu: $coordinates');
        return coordinates;
      }
    } catch (e) {
      print('[AutoStopService] ❌ Geocoding hatası: $e');
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
      Map<String, dynamic>? extendedStop;
      double? extendedDistance;

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

          if (distance <= _proximityThreshold) {
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

          if (distance <= 1000.0) {
            final passengerCount = (data['passengerCount'] ?? 0) as int;
            if (passengerCount < 3) {
              if (extendedDistance == null || distance < extendedDistance) {
                extendedDistance = distance;
                extendedStop = {
                  'id': doc.id,
                  'name': data['name'],
                  'distance': distance,
                  ...data,
                };
              }
            }
          }
        }
      }

      if (closestStop != null) {
        print(
            '[AutoStopService] En yakın durak bulundu: ${closestStop['name']} (${closestDistance?.toStringAsFixed(1)}m)');
        return closestStop;
      }

      if (extendedStop != null) {
        print(
            '[AutoStopService] Genişletilmiş arama ile durak bulundu: ${extendedStop['name']} (${extendedDistance?.toStringAsFixed(1)}m)');
        return extendedStop;
      }
    } catch (e) {
      print('Yakın durak arama hatası: $e');
    }
    return null;
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
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final stopDoc = await transaction.get(stopRef);
        if (!stopDoc.exists) {
          print('Durak bulunamadı: $stopId');
          return;
        }
        final data = stopDoc.data();
        if (data == null) {
          print('Durak verisi null: $stopId');
          return;
        }
        final passengerIds = List<String>.from(data['passengerIds'] ?? []);
        final passengerNames = List<String>.from(data['passengerNames'] ?? []);
        final addresses = List<String>.from(data['addresses'] ?? []);
        final existingIndex = passengerIds.indexOf(passengerId);
        if (existingIndex != -1) {
          passengerNames[existingIndex] = passengerName;
          addresses[existingIndex] = address;
        } else {
          passengerIds.add(passengerId);
          passengerNames.add(passengerName);
          addresses.add(address);
        }
        transaction.update(stopRef, {
          'passengerIds': passengerIds,
          'passengerNames': passengerNames,
          'addresses': addresses,
          'passengerCount': passengerIds.length,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      print('Durağa yolcu ekleme hatası: $e');
    }
  }

  static Future<Map<String, dynamic>> _findOptimalStopLocationByRoadWidth({
    required double homeLatitude,
    required double homeLongitude,
    required String regionId,
  }) async {
    try {
      print('Ev konumu için ana yol aranıyor: $homeLatitude, $homeLongitude');
      final homeAddress =
          await _getAddressFromCoordinates(homeLatitude, homeLongitude);
      print('Ev adresi: $homeAddress');
      final roadInfo =
          await _getRoadTypeFromCoordinates(homeLatitude, homeLongitude);
      print('Yol bilgisi: $roadInfo');
      if (!_isMainRoadByType(roadInfo) || !_isMainRoad(homeAddress ?? '')) {
        print('Ev adresi ana yol değil, yakındaki ana yol aranıyor...');
        final mainRoadResult =
            await _findNearestMainRoadByWidth(homeLatitude, homeLongitude);
        print(
            '🟢 ANA YOL DURAK KOORDİNATI: ${mainRoadResult['lat']}, ${mainRoadResult['lng']} - ${mainRoadResult['address']}');
        return mainRoadResult;
      }
      print('Ev adresi ana yol, durak noktası belirleniyor...');
      final actualMainRoadResult = await _findActualMainRoadPoint(
          homeLatitude, homeLongitude, homeAddress ?? '');
      print(
          '🟢 ANA YOL DURAK KOORDİNATI: ${actualMainRoadResult['lat']}, ${actualMainRoadResult['lng']} - ${actualMainRoadResult['address']}');
      return actualMainRoadResult;
    } catch (e) {
      print('Ana yol noktası bulma hatası: $e');
      return await _findNearestMainRoadByWidth(homeLatitude, homeLongitude);
    }
  }

  static Future<Map<String, dynamic>> _getRoadTypeFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      try {
        ConfigService.googleMapsApiKey;
      } catch (e) {
        print(
            'Google Maps API anahtarı ayarlanmamış, varsayılan kontrol yapılıyor');
        return {'isMainRoad': false};
      }
      final url =
          'https://roads.googleapis.com/v1/snapToRoads?points=$latitude,$longitude&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['snappedPoints'] != null && data['snappedPoints'].isNotEmpty) {
          final roadData = data['snappedPoints'][0];
          return {
            'placeId': roadData['placeId'] ?? '',
            'location': roadData['location'] ?? {},
            'isMainRoad': true,
          };
        }
      }
    } catch (e) {
      print('Roads API hatası: $e');
    }
    return {'isMainRoad': false};
  }

  static Future<bool> _isMainRoadByWidth(
      double latitude, double longitude) async {
    try {
      try {
        ConfigService.googleMapsApiKey;
      } catch (e) {
        return false;
      }
      final url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$latitude,$longitude&radius=50&type=route&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          for (final place in data['results']) {
            final types = List<String>.from(place['types'] ?? []);
            if (types.contains('route') ||
                types.contains('street_address') ||
                types.contains('premise')) {
              final placeDetails = await _getPlaceDetails(place['place_id']);
              return _isMainRoadByPlaceDetails(placeDetails);
            }
          }
        }
      }
    } catch (e) {
      print('Yol kalınlığı tespiti hatası: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>> _getPlaceDetails(String placeId) async {
    try {
      try {
        ConfigService.googleMapsApiKey;
      } catch (e) {
        return {};
      }
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,types,address_components,geometry&key=${ConfigService.googleMapsApiKey}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['result'] ?? {};
      } else {
        print(
            'Place Details API hatası: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Place details hatası: $e');
    }
    return {};
  }

  static bool _isMainRoadByPlaceDetails(Map<String, dynamic> placeDetails) {
    if (placeDetails.isEmpty) return false;
    final types = List<String>.from(placeDetails['types'] ?? []);
    final name = placeDetails['name']?.toString().toLowerCase() ?? '';
    final mainRoadTypes = ['route', 'street_address', 'establishment'];
    final mainRoadKeywords = [
      'cadde',
      'caddesi',
      'bulvar',
      'bulvarı',
      'avenue',
      'boulevard',
      'highway',
      'otoyol',
      'anayol',
      'ana yol'
    ];
    bool hasMainRoadType = types.any((type) => mainRoadTypes.contains(type));
    bool hasMainRoadName =
        mainRoadKeywords.any((keyword) => name.contains(keyword));
    return hasMainRoadType || hasMainRoadName;
  }

  static bool _isMainRoadByType(Map<String, dynamic> roadInfo) {
    return roadInfo['isMainRoad'] == true;
  }

  static Future<Map<String, dynamic>> _findNearestMainRoadByWidth(
    double homeLatitude,
    double homeLongitude,
  ) async {
    try {
      print('🔍 En yakın ana yol arama başlatılıyor...');
      Map<String, dynamic>? bestMainRoad;
      double minDistance = double.infinity;
      List<Map<String, dynamic>> foundMainRoads = [];
      final searchRadiuses = [
        0.0002,
        0.0005,
        0.001,
        0.0015,
        0.002,
        0.0025,
        0.003,
        0.004,
        0.005,
        0.007,
        0.010,
        0.015,
      ];
      for (final radius in searchRadiuses) {
        print(
            '🔍 ${(radius * 111000).toInt()}m yarıçapında ana yol aranıyor...');
        List<Map<String, dynamic>> currentRadiusRoads = [];
        for (int i = 0; i < 72; i++) {
          final angle = (i * 5.0) * (pi / 180);
          final searchLat = homeLatitude + (radius * cos(angle));
          final searchLng = homeLongitude + (radius * sin(angle));
          final address =
              await _getAddressFromCoordinates(searchLat, searchLng);
          if (address != null && _isMainRoad(address)) {
            final distance = Geolocator.distanceBetween(
              homeLatitude,
              homeLongitude,
              searchLat,
              searchLng,
            );
            print('✅ ANA YOL BULUNDU: $address - ${distance.toInt()}m');
            currentRadiusRoads.add({
              'lat': searchLat,
              'lng': searchLng,
              'address': address,
              'distance': distance,
              'isMainRoad': true,
            });
            foundMainRoads.add({
              'lat': searchLat,
              'lng': searchLng,
              'address': address,
              'distance': distance,
              'isMainRoad': true,
            });
          }
          await Future.delayed(Duration(milliseconds: 15));
        }
        if (currentRadiusRoads.isNotEmpty) {
          currentRadiusRoads
              .sort((a, b) => a['distance'].compareTo(b['distance']));
          bestMainRoad = currentRadiusRoads.first;
          minDistance = bestMainRoad['distance'];
          print(
              '🎯 ${(radius * 111000).toInt()}m yarıçapında en yakın ana yol bulundu: ${bestMainRoad['address']} - ${minDistance.toInt()}m');
          print('🛑 Arama durduruluyor - en yakın mesafe bulundu.');
          break;
        }
      }
      if (bestMainRoad == null) {
        print(
            '⚠️ Yakın mesafede ana yol bulunamadı, büyük yollar için özel arama yapılıyor...');
        bestMainRoad =
            await _findMajorRoadsBySpecialSearch(homeLatitude, homeLongitude);
      }
      if (foundMainRoads.isNotEmpty) {
        print('\n📊 BULUNAN TÜM ANA YOLLAR:');
        foundMainRoads.sort((a, b) => a['distance'].compareTo(b['distance']));
        for (int i = 0; i < foundMainRoads.length && i < 5; i++) {
          final road = foundMainRoads[i];
          final isSelected = road['address'] == bestMainRoad?['address'];
          print(
              '${isSelected ? "🎯" : "📍"} ${i + 1}. ${road['address']} - ${road['distance'].toInt()}m ${isSelected ? "(SEÇİLDİ)" : ""}');
        }
        print('');
      }
      if (bestMainRoad == null) {
        print('❌ Hiçbir ana yol bulunamadı, en yakın cadde/bulvar aranıyor...');
        bestMainRoad =
            await _findNearestStreetWithKeywords(homeLatitude, homeLongitude);
      }
      if (bestMainRoad == null) {
        print(
            '❌ Hiçbir uygun yol bulunamadı, varsayılan durak oluşturuluyor...');
        final fallbackAddress =
            await _getAddressFromCoordinates(homeLatitude, homeLongitude);
        bestMainRoad = {
          'lat': homeLatitude + 0.001,
          'lng': homeLongitude + 0.001,
          'address': '${fallbackAddress ?? 'Bilinmeyen'} Yakını Ana Yol Durağı',
          'isMainRoad': true,
        };
      } else {
        print(
            '🎯 SONUÇ: En yakın ana yol seçildi: ${bestMainRoad['address']}, mesafe: ${minDistance.toInt()}m');
      }
      return bestMainRoad;
    } catch (e) {
      print('Ana yol arama hatası: $e');
      return {
        'lat': homeLatitude + 0.001,
        'lng': homeLongitude + 0.001,
        'address': 'Ana Yol Durağı',
        'isMainRoad': true,
      };
    }
  }

  static Future<Map<String, dynamic>?> _findNearestStreetWithKeywords(
    double homeLatitude,
    double homeLongitude,
  ) async {
    try {
      print('🔍 En yakın cadde/bulvar aranıyor...');
      final searchRadiuses = [0.005, 0.010, 0.015, 0.020];
      for (final radius in searchRadiuses) {
        for (int i = 0; i < 24; i++) {
          final angle = (i * 15.0) * (pi / 180);
          final searchLat = homeLatitude + (radius * cos(angle));
          final searchLng = homeLongitude + (radius * sin(angle));
          final address =
              await _getAddressFromCoordinates(searchLat, searchLng);
          if (address != null) {
            final lowerAddress = address.toLowerCase();
            if (lowerAddress.contains('cadde') ||
                lowerAddress.contains('bulvar') ||
                lowerAddress.contains('avenue') ||
                lowerAddress.contains('boulevard')) {
              final distance = Geolocator.distanceBetween(
                  homeLatitude, homeLongitude, searchLat, searchLng);
              print('✅ Cadde/Bulvar bulundu: $address - ${distance.toInt()}m');
              return {
                'lat': searchLat,
                'lng': searchLng,
                'address': address,
                'distance': distance,
                'isMainRoad': true,
              };
            }
          }
          await Future.delayed(Duration(milliseconds: 20));
        }
      }
      return null;
    } catch (e) {
      print('Cadde/bulvar arama hatası: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _findMajorRoadsBySpecialSearch(
    double homeLatitude,
    double homeLongitude,
  ) async {
    try {
      print('Büyük yollar için özel arama başlatılıyor...');
      final largeSearchRadiuses = [
        0.020,
        0.025,
        0.030,
        0.035,
        0.040,
        0.045,
        0.050
      ];
      for (final radius in largeSearchRadiuses) {
        print(
            '🔍 Büyük yarıçapta ana yol aranıyor: ${(radius * 111000).toInt()}m çapında...');
        final mainDirections = [0, 45, 90, 135, 180, 225, 270, 315];
        for (final angleDegree in mainDirections) {
          final angle = angleDegree * (pi / 180);
          final searchLat = homeLatitude + (radius * cos(angle));
          final searchLng = homeLongitude + (radius * sin(angle));
          final address =
              await _getAddressFromCoordinates(searchLat, searchLng);
          if (address != null) {
            print('🔍 Büyük yarıçap adres kontrolü: $address');
            final lowerAddress = address.toLowerCase();
            if (lowerAddress.contains(RegExp(r'd\d+')) ||
                lowerAddress.contains('otoyol') ||
                lowerAddress.contains('highway') ||
                lowerAddress.contains('tem') ||
                lowerAddress.contains(RegExp(r'o-\d+')) ||
                lowerAddress.contains('anayol') ||
                lowerAddress.contains('ana yol') ||
                lowerAddress.contains('büyük cadde') ||
                lowerAddress.contains('ana cadde')) {
              final distance = Geolocator.distanceBetween(
                homeLatitude,
                homeLongitude,
                searchLat,
                searchLng,
              );
              print(
                  '✅ BÜYÜK ANA YOL TESPİT EDİLDİ! 🟢 Adres: $address, Mesafe: ${distance.toInt()}m, Koordinat: ($searchLat, $searchLng)');
              return {
                'lat': searchLat,
                'lng': searchLng,
                'address': address,
                'distance': distance,
                'isMainRoad': true,
              };
            }
          }
          await Future.delayed(Duration(milliseconds: 50));
        }
      }
      return null;
    } catch (e) {
      print('Özel arama hatası: $e');
      return null;
    }
  }

  static Future<String?> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.street ?? ''} ${placemark.subLocality ?? ''} ${placemark.locality ?? ''}'
            .trim();
      }
    } catch (e) {
      print('Reverse geocoding hatası: $e');
    }
    return null;
  }

  static bool _isMainRoad(String address) {
    if (address.isEmpty) return false;
    final lowerAddress = address.toLowerCase();
    print('🔍 Ana yol kontrolü yapılıyor: $address');
    final mainRoadKeywords = [
      'cadde',
      'caddesi',
      'bulvar',
      'bulvarı',
      'avenue',
      'boulevard',
      'highway',
      'otoyol',
      'anayol',
      'ana yol',
      'devlet yolu',
      'karayolu',
      'çevreyolu',
      'ring',
    ];
    final majorRoadPatterns = [
      RegExp(r'd\d+'),
      RegExp(r'o-\d+'),
      RegExp(r'tem'),
      RegExp(r'e-?5'),
      RegExp(r'\b[1-9]00\b'),
    ];
    final excludedKeywords = [
      'mahalle',
      'mahallesi',
      'mah.',
      'sokak',
      'sokağı',
      'sk.',
      'site',
      'sitesi',
      'konut',
      'residence',
      'villa',
      'apartman',
      'apt.',
      'evler',
      'evleri',
      'park',
      'parkı',
      'plaza',
      'plazası',
      'pasaj',
      'çarşı',
      'market',
      'dükkân',
      'iş merkezi',
      'alışveriş',
      'no:',
      'kapı',
    ];
    bool hasExcludedKeyword =
        excludedKeywords.any((keyword) => lowerAddress.contains(keyword));
    if (hasExcludedKeyword) {
      print('🔴 Mahalle sokağı tespit edildi, ana yol değil');
      return false;
    }
    bool hasMainRoadKeyword =
        mainRoadKeywords.any((keyword) => lowerAddress.contains(keyword));
    if (hasMainRoadKeyword) {
      print('✅ Ana yol anahtar kelimesi bulundu: $lowerAddress');
    }
    bool hasMajorRoadPattern =
        majorRoadPatterns.any((pattern) => pattern.hasMatch(lowerAddress));
    if (hasMajorRoadPattern) {
      print('✅ Büyük yol deseni bulundu: $lowerAddress');
    }
    bool isMainRoad = hasMainRoadKeyword || hasMajorRoadPattern;
    if (isMainRoad) {
      print('🟢 ANA YOL TESPİT EDİLDİ! $address');
      return true;
    } else {
      print('🔴 Ana yol değil: $address');
      return false;
    }
  }

  static bool _hasSameWordRepeat(String lowerAddress) {
    final words = lowerAddress.split(' ');
    for (int i = 0; i < words.length - 1; i++) {
      if (words[i] == words[i + 1] && words[i].length > 3) {
        return true;
      }
    }
    return false;
  }

  static bool _isNeighborhoodStreet(String lowerAddress) {
    print('🔍 Mahalle sokağı kontrolü: $lowerAddress');
    final strongNeighborhoodIndicators = [
      'mahalle',
      'mahallesi',
      'mah.',
      'site',
      'sitesi',
      'konut',
      'residence',
      'villa',
      'apartman',
      'apt.',
      'evler',
      'evleri',
      'park',
      'parkı',
      'plaza',
      'plazası',
    ];
    final weakNeighborhoodIndicators = [
      'sokak',
      'sokağı',
      'sk.',
    ];
    final mainRoadIndicators = [
      'cadde',
      'caddesi',
      'bulvar',
      'bulvarı',
      'yol',
      'yolu',
      'mevkii',
      'mevki',
    ];
    bool hasStrongIndicator = strongNeighborhoodIndicators
        .any((indicator) => lowerAddress.contains(indicator));
    if (hasStrongIndicator) {
      print('🔴 Güçlü mahalle göstergesi bulundu');
      return true;
    }
    bool hasWeakIndicator = weakNeighborhoodIndicators
        .any((indicator) => lowerAddress.contains(indicator));
    bool hasMainRoadIndicator =
        mainRoadIndicators.any((indicator) => lowerAddress.contains(indicator));
    if (hasWeakIndicator && hasMainRoadIndicator) {
      print(
          '🟡 Hem sokak hem ana yol göstergesi var, ana yol olarak kabul ediliyor');
      return false;
    }
    if (hasWeakIndicator) {
      print('🔴 Sadece zayıf mahalle göstergesi var');
      return true;
    }
    print('🟢 Mahalle sokağı değil');
    return false;
  }

  static Future<Map<String, dynamic>> _findActualMainRoadPoint(
    double homeLatitude,
    double homeLongitude,
    String homeAddress,
  ) async {
    try {
      final offsets = [
        {'lat': 0.0005, 'lng': 0.0},
        {'lat': -0.0005, 'lng': 0.0},
        {'lat': 0.0, 'lng': 0.0005},
        {'lat': 0.0, 'lng': -0.0005},
      ];
      for (final offset in offsets) {
        final newLat = homeLatitude + offset['lat']!;
        final newLng = homeLongitude + offset['lng']!;
        final address = await _getAddressFromCoordinates(newLat, newLng);
        if (address != null && _isSameMainRoad(homeAddress, address)) {
          return {
            'lat': newLat,
            'lng': newLng,
            'address': address,
            'isMainRoad': true,
          };
        }
      }
      return {
        'lat': homeLatitude,
        'lng': homeLongitude,
        'address': homeAddress,
        'isMainRoad': true,
      };
    } catch (e) {
      print('Gerçek ana yol noktası bulma hatası: $e');
      return {
        'lat': homeLatitude,
        'lng': homeLongitude,
        'address': homeAddress,
        'isMainRoad': true,
      };
    }
  }

  static bool _isSameMainRoad(String address1, String address2) {
    final mainRoad1 = _extractMainRoadName(address1);
    final mainRoad2 = _extractMainRoadName(address2);
    return mainRoad1.isNotEmpty &&
        mainRoad2.isNotEmpty &&
        mainRoad1 == mainRoad2;
  }

  static String _extractMainRoadName(String address) {
    final lowerAddress = address.toLowerCase();
    final patterns = [
      RegExp(r'([^,]*(?:cadde|caddesi|bulvar|bulvarı)[^,]*)',
          caseSensitive: false),
      RegExp(r'([^,]*(?:d\d+)[^,]*)', caseSensitive: false),
      RegExp(r'([^,]*(?:otoyol)[^,]*)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerAddress);
      if (match != null) {
        return match.group(1)?.trim() ?? '';
      }
    }
    return '';
  }

  static Future<void> _createNewAutoStop({
    required String passengerId,
    required String passengerName,
    required String address,
    required double homeLatitude,
    required double homeLongitude,
    required double stopLatitude,
    required double stopLongitude,
    required String stopAddress,
    required String regionId,
  }) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc();
      final isMainRoadStop = AutoStopService._isMainRoad(stopAddress);
      final markerColor = isMainRoadStop ? 'green' : 'red';
      final stopType = isMainRoadStop ? 'Ana Yol Durağı' : 'Ev Adresi Durağı';
      await stopRef.set({
        'id': stopRef.id,
        'name': 'Otomatik Durak - $stopAddress',
        'address': stopAddress,
        'latitude': stopLatitude,
        'longitude': stopLongitude,
        'regionId': regionId,
        'isActive': true,
        'isAutoGenerated': true,
        'markerColor': markerColor,
        'stopType': stopType,
        'isMainRoad': isMainRoadStop,
        'passengerIds': [passengerId],
        'passengerNames': [passengerName],
        'addresses': [address],
        'passengerCount': 1,
        'homeCoordinates': {
          'latitude': homeLatitude,
          'longitude': homeLongitude,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print(
          '✅ Yeni otomatik durak oluşturuldu: ${stopRef.id} - $stopType ($markerColor marker)');
    } catch (e) {
      print('Otomatik durak oluşturma hatası: $e');
    }
  }

  static Future<void> removePassengerFromStop(
    String stopId,
    String passengerId,
  ) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc(stopId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final stopDoc = await transaction.get(stopRef);
        if (!stopDoc.exists) {
          print('Durak bulunamadı: $stopId');
          return;
        }
        final data = stopDoc.data();
        if (data == null) {
          print('Durak verisi null: $stopId');
          return;
        }
        final passengerIds = List<String>.from(data['passengerIds'] ?? []);
        final passengerNames = List<String>.from(data['passengerNames'] ?? []);
        final addresses = List<String>.from(data['addresses'] ?? []);
        final passengerIndex = passengerIds.indexOf(passengerId);
        if (passengerIndex == -1) {
          print('Yolcu durakta bulunamadı: $passengerId');
          return;
        }
        passengerIds.removeAt(passengerIndex);
        passengerNames.removeAt(passengerIndex);
        addresses.removeAt(passengerIndex);
        if (passengerIds.isEmpty && data['isAutoGenerated'] == true) {
          transaction.delete(stopRef);
          print('Otomatik oluşturulmuş boş durak silindi: $stopId');
        } else {
          transaction.update(stopRef, {
            'passengerIds': passengerIds,
            'passengerNames': passengerNames,
            'addresses': addresses,
            'passengerCount': passengerIds.length,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('Yolcu duraktan kaldırıldı: $passengerId');
        }
      });
    } catch (e) {
      print('Yolcu kaldırma hatası: $e');
    }
  }

  static Future<void> updateStopsBasedOnNearbyPassengers(
      String regionId) async {
    try {
      print('🔄 Yakın yolculara göre durak optimizasyonu başlatılıyor...');
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      final passengerDensityMap = await _analyzePassengerDensity(regionId);
      await _optimizeStopsBasedOnDensity(
          stopsSnapshot.docs, passengerDensityMap, regionId);
      await _suggestNewStopsForHighDensityAreas(passengerDensityMap, regionId);
      print('✅ Durak optimizasyonu tamamlandı');
    } catch (e) {
      print('Durak güncelleme hatası: $e');
    }
  }

  static Future<Map<String, dynamic>> _analyzePassengerDensity(
      String regionId) async {
    try {
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      Map<String, List<Map<String, dynamic>>> densityAreas = {};
      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();
        final passengerCount = data['passengerCount'] ?? 0;
        final latitude = data['latitude'] as double?;
        final longitude = data['longitude'] as double?;
        if (latitude != null && longitude != null && passengerCount > 0) {
          final gridKey =
              '${(latitude * 200).round()}_${(longitude * 200).round()}';
          if (!densityAreas.containsKey(gridKey)) {
            densityAreas[gridKey] = [];
          }
          densityAreas[gridKey]!.add({
            'stopId': doc.id,
            'passengerCount': passengerCount,
            'latitude': latitude,
            'longitude': longitude,
            'address': data['address'] ?? '',
          });
        }
      }
      Map<String, dynamic> densityScores = {};
      densityAreas.forEach((gridKey, stops) {
        final totalPassengers = stops.fold<int>(
            0, (sum, stop) => sum + (stop['passengerCount'] as int));
        final avgLat =
            stops.fold<double>(0, (sum, stop) => sum + stop['latitude']) /
                stops.length;
        final avgLng =
            stops.fold<double>(0, (sum, stop) => sum + stop['longitude']) /
                stops.length;
        densityScores[gridKey] = {
          'totalPassengers': totalPassengers,
          'stopCount': stops.length,
          'density': totalPassengers / stops.length,
          'centerLat': avgLat,
          'centerLng': avgLng,
          'stops': stops,
        };
      });
      print('📊 Yoğunluk analizi: ${densityScores.length} alan analiz edildi');
      return densityScores;
    } catch (e) {
      print('Yoğunluk analizi hatası: $e');
      return {};
    }
  }

  static Future<void> _optimizeStopsBasedOnDensity(
    List<QueryDocumentSnapshot> stops,
    Map<String, dynamic> densityMap,
    String regionId,
  ) async {
    try {
      for (final entry in densityMap.entries) {
        final areaData = entry.value;
        final totalPassengers = areaData['totalPassengers'] as int;
        final stopCount = areaData['stopCount'] as int;
        final areaStops = areaData['stops'] as List<Map<String, dynamic>>;
        if (totalPassengers >= 5 && stopCount > 1) {
          await _mergeNearbyStops(areaStops, regionId);
        } else if (totalPassengers <= 2 && stopCount == 1) {
          await _checkForStopConsolidation(areaStops.first, regionId);
        }
      }
    } catch (e) {
      print('Durak optimizasyonu hatası: $e');
    }
  }

  static Future<void> _mergeNearbyStops(
    List<Map<String, dynamic>> areaStops,
    String regionId,
  ) async {
    try {
      if (areaStops.length < 2) return;
      areaStops.sort((a, b) =>
          (b['passengerCount'] as int).compareTo(a['passengerCount'] as int));
      final mainStop = areaStops.first;
      final stopsToMerge = areaStops.skip(1).toList();
      print(
          '🔄 Durak birleştirme: ${stopsToMerge.length} durak ${mainStop['stopId']} durağına birleştiriliyor');
      for (final stopToMerge in stopsToMerge) {
        await _transferPassengersAndDeleteStop(
            stopToMerge['stopId'], mainStop['stopId']);
      }
    } catch (e) {
      print('Durak birleştirme hatası: $e');
    }
  }

  static Future<void> _transferPassengersAndDeleteStop(
    String fromStopId,
    String toStopId,
  ) async {
    try {
      final fromStopRef = FirebaseFirestore.instance
          .collection('enhanced_stops')
          .doc(fromStopId);
      final toStopRef =
          FirebaseFirestore.instance.collection('enhanced_stops').doc(toStopId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final fromStopDoc = await transaction.get(fromStopRef);
        final toStopDoc = await transaction.get(toStopRef);
        if (!fromStopDoc.exists || !toStopDoc.exists) return;
        final fromData = fromStopDoc.data()!;
        final toData = toStopDoc.data()!;
        final fromPassengerIds =
            List<String>.from(fromData['passengerIds'] ?? []);
        final fromPassengerNames =
            List<String>.from(fromData['passengerNames'] ?? []);
        final fromAddresses = List<String>.from(fromData['addresses'] ?? []);
        final toPassengerIds = List<String>.from(toData['passengerIds'] ?? []);
        final toPassengerNames =
            List<String>.from(toData['passengerNames'] ?? []);
        final toAddresses = List<String>.from(toData['addresses'] ?? []);
        for (int i = 0; i < fromPassengerIds.length; i++) {
          if (!toPassengerIds.contains(fromPassengerIds[i])) {
            toPassengerIds.add(fromPassengerIds[i]);
            toPassengerNames.add(fromPassengerNames[i]);
            toAddresses.add(fromAddresses[i]);
          }
        }
        transaction.update(toStopRef, {
          'passengerIds': toPassengerIds,
          'passengerNames': toPassengerNames,
          'addresses': toAddresses,
          'passengerCount': toPassengerIds.length,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        transaction.delete(fromStopRef);
      });
      print('✅ Durak transfer edildi: $fromStopId -> $toStopId');
    } catch (e) {
      print('Durak transfer hatası: $e');
    }
  }

  static Future<void> _checkForStopConsolidation(
    Map<String, dynamic> stopData,
    String regionId,
  ) async {
    try {
      final stopLat = stopData['latitude'] as double;
      final stopLng = stopData['longitude'] as double;
      final nearbyStops =
          await _findStopsInRadius(stopLat, stopLng, 300.0, regionId);
      if (nearbyStops.length > 1) {
        final targetStop = nearbyStops
            .where((stop) => stop['stopId'] != stopData['stopId'])
            .first;
        await _transferPassengersAndDeleteStop(
            stopData['stopId'], targetStop['stopId']);
        print(
            '🔄 Düşük yoğunluklu durak konsolide edildi: ${stopData['stopId']}');
      }
    } catch (e) {
      print('Konsolidasyon kontrolü hatası: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> _findStopsInRadius(
    double centerLat,
    double centerLng,
    double radiusMeters,
    String regionId,
  ) async {
    try {
      final stopsSnapshot = await FirebaseFirestore.instance
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
              centerLat, centerLng, stopLat, stopLng);
          if (distance <= radiusMeters) {
            nearbyStops.add({
              'stopId': doc.id,
              'distance': distance,
              'passengerCount': data['passengerCount'] ?? 0,
              ...data,
            });
          }
        }
      }
      nearbyStops.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));
      return nearbyStops;
    } catch (e) {
      print('Yarıçap arama hatası: $e');
      return [];
    }
  }

  static Future<void> _suggestNewStopsForHighDensityAreas(
    Map<String, dynamic> densityMap,
    String regionId,
  ) async {
    try {
      for (final entry in densityMap.entries) {
        final areaData = entry.value;
        final totalPassengers = areaData['totalPassengers'] as int;
        final density = areaData['density'] as double;
        if (totalPassengers >= 10 && density > 3.0) {
          final centerLat = areaData['centerLat'] as double;
          final centerLng = areaData['centerLng'] as double;
          final mainRoadLocation = await _findOptimalStopLocationByRoadWidth(
            homeLatitude: centerLat,
            homeLongitude: centerLng,
            regionId: regionId,
          );
          final nearestStop = await _findNearbyStop(
            mainRoadLocation['lat']!,
            mainRoadLocation['lng']!,
            regionId,
          );
          if (nearestStop == null || nearestStop['distance'] > 200) {
            await _createSuggestedStop(
              centerLat: centerLat,
              centerLng: centerLng,
              stopLat: mainRoadLocation['lat']!,
              stopLng: mainRoadLocation['lng']!,
              stopAddress: mainRoadLocation['address']!,
              regionId: regionId,
              passengerCount: totalPassengers,
            );
            print(
                '💡 Yüksek yoğunluk için yeni durak önerildi: ${mainRoadLocation['address']}');
          }
        }
      }
    } catch (e) {
      print('Durak önerisi hatası: $e');
    }
  }

  static Future<void> _createSuggestedStop({
    required double centerLat,
    required double centerLng,
    required double stopLat,
    required double stopLng,
    required String stopAddress,
    required String regionId,
    required int passengerCount,
  }) async {
    try {
      final stopRef =
          FirebaseFirestore.instance.collection('suggested_stops').doc();
      await stopRef.set({
        'id': stopRef.id,
        'name': 'Önerilen Durak - $stopAddress',
        'address': stopAddress,
        'latitude': stopLat,
        'longitude': stopLng,
        'regionId': regionId,
        'isActive': false,
        'isSuggested': true,
        'suggestedReason': 'Yüksek yolcu yoğunluğu ($passengerCount yolcu)',
        'centerCoordinates': {
          'latitude': centerLat,
          'longitude': centerLng,
        },
        'estimatedPassengerCount': passengerCount,
        'markerColor': 'blue',
        'stopType': 'Önerilen Durak',
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('💡 Önerilen durak oluşturuldu: ${stopRef.id}');
    } catch (e) {
      print('Önerilen durak oluşturma hatası: $e');
    }
  }

  static Future<void> schedulePeriodicStopOptimization(String regionId) async {
    try {
      print('⏰ Periyodik durak optimizasyonu başlatılıyor...');
      await updateStopsBasedOnNearbyPassengers(regionId);
      await FirebaseFirestore.instance
          .collection('system_settings')
          .doc('optimization_schedule')
          .set({
        'lastOptimization': FieldValue.serverTimestamp(),
        'regionId': regionId,
        'status': 'completed',
      }, SetOptions(merge: true));
      print('✅ Periyodik optimizasyon tamamlandı');
    } catch (e) {
      print('Periyodik optimizasyon hatası: $e');
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
          .limit(1)
          .get();

      if (stopsSnapshot.docs.isNotEmpty) {
        final doc = stopsSnapshot.docs.first;
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }
      return null;
    } catch (e) {
      print('[AutoStopService] Yolcunun mevcut durağını bulma hatası: $e');
      return null;
    }
  }

  static Future<void> _updateStopLocation(
    String stopId,
    double latitude,
    double longitude,
    String address,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('enhanced_stops')
          .doc(stopId)
          .update({
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('[AutoStopService] Durak konumu güncellendi: $stopId');
    } catch (e) {
      print('[AutoStopService] Durak konumu güncelleme hatası: $e');
    }
  }
}

// Updated

