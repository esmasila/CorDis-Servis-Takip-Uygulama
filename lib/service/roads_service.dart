import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
class RoadsService {
  static const String _baseUrl = 'https://roads.googleapis.com/v1/snapToRoads';
  static const String _googleApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ',
  );
  static Future<List<LatLng>> snapToRoads(List<LatLng> inputPoints) async {
    if (inputPoints.length < 2) return inputPoints;
    final List<LatLng> snapped = [];
    const int maxPerRequest = 100;
    for (int i = 0; i < inputPoints.length; i += maxPerRequest) {
      final chunk = inputPoints.sublist(
        i,
        i + maxPerRequest > inputPoints.length
            ? inputPoints.length
            : i + maxPerRequest,
      );
      final path = chunk
          .map((p) =>
              '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
          .join('|');
      final uri =
          Uri.parse('$_baseUrl?interpolate=true&path=$path&key=$_googleApiKey');
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final List<dynamic>? snappedPoints =
            data['snappedPoints'] as List<dynamic>?;
        if (snappedPoints == null || snappedPoints.isEmpty) continue;
        for (final sp in snappedPoints) {
          final loc = sp['location'] as Map<String, dynamic>?;
          if (loc == null) continue;
          final lat = (loc['latitude'] as num?)?.toDouble();
          final lng = (loc['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          snapped.add(LatLng(lat, lng));
        }
      } catch (_) {
      }
    }
    return snapped.isNotEmpty ? snapped : inputPoints;
  }
}

// Updated


// Updated Again

