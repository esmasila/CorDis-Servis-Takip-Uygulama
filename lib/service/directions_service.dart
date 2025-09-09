import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/directions_model.dart';

class DirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String _googleApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ');
  final Dio _dio;
  static DirectionsService? _instance;
  DirectionsService._({Dio? dio}) : _dio = dio ?? Dio();
  static DirectionsService get instance {
    _instance ??= DirectionsService._();
    return _instance!;
  }

  factory DirectionsService({Dio? dio}) => DirectionsService._(dio: dio);
  Future<bool> testApiKey() async {
    try {
      print('🔑 API Key test ediliyor: ${_googleApiKey.substring(0, 10)}...');
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'origin': '41.0082,28.9784',
          'destination': '41.0186,28.9647',
          'key': _googleApiKey,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final status = data['status'] as String;
        print('📊 API Test Sonucu: $status');
        if (status == 'OK') {
          print('✅ API Key çalışıyor!');
          return true;
        } else {
          print('❌ API Hatası: $status');
          if (data['error_message'] != null) {
            print('❌ Hata Detayı: ${data['error_message']}');
          }
          return false;
        }
      } else {
        print('❌ HTTP Hatası: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ API Key test hatası: $e');
      return false;
    }
  }

  Future<DirectionsModel?> getDirections({
    required LatLng baslangic,
    required LatLng hedef,
    List<LatLng>? araNoktalar,
  }) async {
    try {
      print(
          '🗺️ Rota bilgileri alınıyor: ${baslangic.latitude},${baslangic.longitude} -> ${hedef.latitude},${hedef.longitude}');
      print('🔑 API Key: ${_googleApiKey.substring(0, 10)}...');
      final queryParameters = <String, dynamic>{
        'origin': '${baslangic.latitude},${baslangic.longitude}',
        'destination': '${hedef.latitude},${hedef.longitude}',
        'key': _googleApiKey,
        'language': 'tr',
        'region': 'tr',
        'mode': 'driving',
        'avoid': 'tolls',
        'traffic_model': 'best_guess',
        'departure_time': 'now',
        'units': 'metric',
      };
      if (araNoktalar != null && araNoktalar.isNotEmpty) {
        final waypoints = araNoktalar
            .map((nokta) => '${nokta.latitude},${nokta.longitude}')
            .join('|');
        queryParameters['waypoints'] = 'optimize:true|$waypoints';
        print('📍 Ara noktalar: $waypoints');
      }
      final response = await _dio.get(
        _baseUrl,
        queryParameters: queryParameters,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['status'] != 'OK') {
          print('❌ Google Directions API hatası: ${data['status']}');
          if (data['error_message'] != null) {
            print('❌ Hata detayı: ${data['error_message']}');
          }
          return null;
        }
        final directions = DirectionsModel.fromMap(data);
        if (directions.isValid) {
          print(
              '✅ Rota başarıyla alındı: ${directions.toplamMesafe}, ${directions.toplamSure}');
          return directions;
        } else {
          print('⚠️ Geçersiz rota verisi');
          return null;
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ Network hatası: ${e.message}');
      if (e.response != null) {
        print('❌ Response data: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('❌ Beklenmeyen hata: $e');
      return null;
    }
  }

  Future<DirectionsModel?> getOptimizedRoute({
    required LatLng baslangic,
    required List<LatLng> duraklar,
  }) async {
    print('🎯 getOptimizedRoute çağrıldı');
    print('📍 Başlangıç: ${baslangic.latitude}, ${baslangic.longitude}');
    print('🚏 Durak sayısı: ${duraklar.length}');
    if (duraklar.isEmpty) {
      print('⚠️ Durak listesi boş');
      return null;
    }
    for (int i = 0; i < duraklar.length; i++) {
      print('🚏 Durak $i: ${duraklar[i].latitude}, ${duraklar[i].longitude}');
    }
    if (duraklar.length == 1) {
      print('🎯 Tek durak var, direkt rota alınıyor...');
      return getDirections(
        baslangic: baslangic,
        hedef: duraklar.first,
      );
    }
    print('🎯 Çoklu durak için optimize edilmiş rota alınıyor...');
    final hedef = duraklar.last;
    final araNoktalar = duraklar.take(duraklar.length - 1).toList();
    print('🏁 Hedef: ${hedef.latitude}, ${hedef.longitude}');
    print('🛤️ Ara nokta sayısı: ${araNoktalar.length}');
    return getDirections(
      baslangic: baslangic,
      hedef: hedef,
      araNoktalar: araNoktalar,
    );
  }

  Future<Map<String, dynamic>?> getDistanceMatrix({
    required List<LatLng> baslangiclar,
    required List<LatLng> hedefler,
  }) async {
    try {
      print('📊 Mesafe matrisi alınıyor...');
      final originsStr =
          baslangiclar.map((p) => '${p.latitude},${p.longitude}').join('|');
      final destinationsStr =
          hedefler.map((p) => '${p.latitude},${p.longitude}').join('|');
      const matrixUrl =
          'https://maps.googleapis.com/maps/api/distancematrix/json';
      final response = await _dio.get(
        matrixUrl,
        queryParameters: {
          'origins': originsStr,
          'destinations': destinationsStr,
          'key': _googleApiKey,
          'language': 'tr',
          'units': 'metric',
          'mode': 'driving',
          'avoid': 'tolls',
          'traffic_model': 'best_guess',
          'departure_time': 'now',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          print('✅ Mesafe matrisi başarıyla alındı');
          return data;
        } else {
          print('❌ Distance Matrix API hatası: ${data['status']}');
          return null;
        }
      }
      return null;
    } catch (e) {
      print('❌ Mesafe matrisi hatası: $e');
      return null;
    }
  }

  bool get isApiKeyValid =>
      _googleApiKey.isNotEmpty && _googleApiKey != 'YOUR_API_KEY_HERE';
  Future<bool> checkServiceHealth() async {
    try {
      const testBaslangic = LatLng(39.9334, 32.8597);
      const testHedef = LatLng(41.0082, 28.9784);
      final directions = await getDirections(
        baslangic: testBaslangic,
        hedef: testHedef,
      );
      return directions != null && directions.isValid;
    } catch (e) {
      print('❌ Servis sağlık kontrolü başarısız: $e');
      return false;
    }
  }
}

// Updated


// Updated Again

