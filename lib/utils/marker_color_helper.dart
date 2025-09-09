import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
class MarkerColorHelper {
  static String getMarkerColor(Map<String, dynamic> stopData) {
    if (stopData.containsKey('markerColor')) {
      return stopData['markerColor'] as String;
    }
    final isMainRoad = stopData['isMainRoad'] as bool? ?? false;
    final isHomeAddress = stopData['isHomeAddress'] as bool? ?? false;
    if (isMainRoad) {
      return 'green';
    } else if (isHomeAddress) {
      return 'red';
    } else {
      return 'blue';
    }
  }
  static double getMarkerHue(String colorString) {
    switch (colorString) {
      case 'green':
        return BitmapDescriptor.hueGreen;
      case 'red':
        return BitmapDescriptor.hueViolet;
      case 'blue':
      default:
        return BitmapDescriptor.hueBlue;
    }
  }
  static Color getCircleColor(String colorString) {
    switch (colorString) {
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'blue':
      default:
        return Colors.blue;
    }
  }
  static String getStopTypeDescription(String colorString) {
    switch (colorString) {
      case 'green':
        return 'Ana Yol Durağı';
      case 'red':
        return 'Ev Adresi';
      case 'blue':
      default:
        return 'Normal Durak';
    }
  }
}

// Updated


// Updated Again

