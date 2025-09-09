import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
class DirectionsModel {
  final LatLngBounds sinirlar;
  final List<PointLatLng> polylineNoktalari;
  final String toplamMesafe;
  final String toplamSure;
  const DirectionsModel({
    required this.sinirlar,
    required this.polylineNoktalari,
    required this.toplamMesafe,
    required this.toplamSure,
  });
  String get totalDistance => toplamMesafe;
  String get totalDuration => toplamSure;
  factory DirectionsModel.fromMap(Map<String, dynamic> map) {
    try {
      if ((map['routes'] as List).isEmpty) {
        print('⚠️ Rota bulunamadı');
        return DirectionsModel.empty();
      }
      final data = Map<String, dynamic>.from(map['routes'][0]);
      final northeast = data['bounds']['northeast'];
      final southwest = data['bounds']['southwest'];
      final sinirlar = LatLngBounds(
        northeast: LatLng(northeast['lat'], northeast['lng']),
        southwest: LatLng(southwest['lat'], southwest['lng']),
      );
      String mesafe = '';
      String sure = '';
      if ((data['legs'] as List).isNotEmpty) {
        final leg = data['legs'][0];
        mesafe = leg['distance']['text'];
        sure = leg['duration']['text'];
      }
      final polylineNoktalari =
          PolylinePoints.decodePolyline(data['overview_polyline']['points']);
      print('✅ Rota başarıyla parse edildi: $mesafe, $sure');
      return DirectionsModel(
        sinirlar: sinirlar,
        polylineNoktalari: polylineNoktalari,
        toplamMesafe: mesafe,
        toplamSure: sure,
      );
    } catch (e) {
      print('❌ Rota parse hatası: $e');
      return DirectionsModel.empty();
    }
  }
  factory DirectionsModel.empty() {
    return DirectionsModel(
      sinirlar: LatLngBounds(
        northeast: LatLng(0, 0),
        southwest: LatLng(0, 0),
      ),
      polylineNoktalari: const [],
      toplamMesafe: '',
      toplamSure: '',
    );
  }
  bool get isValid =>
      polylineNoktalari.isNotEmpty &&
      toplamMesafe.isNotEmpty &&
      toplamSure.isNotEmpty;
  List<LatLng> get latLngNoktalari => polylineNoktalari
      .map((nokta) => LatLng(nokta.latitude, nokta.longitude))
      .toList();
  @override
  String toString() {
    return 'DirectionsModel(mesafe: $toplamMesafe, sure: $toplamSure, nokta_sayisi: ${polylineNoktalari.length})';
  }
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DirectionsModel &&
        other.toplamMesafe == toplamMesafe &&
        other.toplamSure == toplamSure &&
        listEquals(other.polylineNoktalari, polylineNoktalari);
  }
  @override
  int get hashCode => Object.hash(
        toplamMesafe,
        toplamSure,
        polylineNoktalari.length,
      );
}

// Updated

