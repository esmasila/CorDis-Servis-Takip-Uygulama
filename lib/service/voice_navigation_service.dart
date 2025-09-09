import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'directions_service.dart';
class VoiceNavigationService {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isNavigationActive = false;
  static bool _isSpeaking = false;
  static Timer? _navigationTimer;
  static List<NavigationStep> _currentRoute = [];
  static int _currentStepIndex = 0;
  static StreamSubscription<Position>? _positionSubscription;
  static Function(String)? _onInstructionCallback;
  static Future<void> initializeTTS() async {
    await _flutterTts.setLanguage('tr-TR');
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _flutterTts.setErrorHandler((msg) {
      print('TTS Hatası: $msg');
      _isSpeaking = false;
    });
  }
  static Future<void> speakDirection(String instruction) async {
    if (_isSpeaking) {
      await _flutterTts.stop();
    }
    try {
      _isSpeaking = true;
      final turkishInstruction = _translateToTurkish(instruction);
      await _flutterTts.speak(turkishInstruction);
    } catch (e) {
      print('Sesli yönlendirme hatası: $e');
      _isSpeaking = false;
    }
  }
  static Future<void> startNavigation({
    required List<LatLng> route,
    required Function(String) onInstructionCallback,
  }) async {
    if (_isNavigationActive) {
      await stopNavigation();
    }
    _onInstructionCallback = onInstructionCallback;
    _isNavigationActive = true;
    _currentStepIndex = 0;
    _currentRoute = await _generateNavigationSteps(route);
    if (_currentRoute.isEmpty) {
      print('Navigasyon rotası oluşturulamadı');
      return;
    }
    await speakDirection('Navigasyon başlatılıyor. ${_currentRoute.first.instruction}');
    _onInstructionCallback?.call(_currentRoute.first.instruction);
    _startLocationTracking();
    _startPeriodicCheck();
  }
  static Future<void> stopNavigation() async {
    _isNavigationActive = false;
    _navigationTimer?.cancel();
    _positionSubscription?.cancel();
    if (_isSpeaking) {
      await _flutterTts.stop();
    }
    await speakDirection('Navigasyon sonlandırıldı.');
    _onInstructionCallback?.call('Navigasyon sonlandırıldı.');
    _currentRoute.clear();
    _currentStepIndex = 0;
  }
  static void _startLocationTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      _checkNavigationProgress(
        LatLng(position.latitude, position.longitude),
      );
    });
  }
  static void checkSimulationProgress(LatLng simulationLocation) {
    if (_isNavigationActive) {
      _checkNavigationProgress(simulationLocation);
    }
  }
  static void _checkNavigationProgress(LatLng currentLocation) {
    if (!_isNavigationActive || _currentStepIndex >= _currentRoute.length) {
      return;
    }
    final currentStep = _currentRoute[_currentStepIndex];
    final distanceToStep = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      currentStep.endLocation.latitude,
      currentStep.endLocation.longitude,
    );
    if (distanceToStep < 50 && _currentStepIndex < _currentRoute.length - 1) {
      _currentStepIndex++;
      final nextStep = _currentRoute[_currentStepIndex];
      speakDirection(nextStep.instruction);
      _onInstructionCallback?.call(nextStep.instruction);
    }
    if (distanceToStep < 20 && _currentStepIndex == _currentRoute.length - 1) {
      speakDirection('Hedefe ulaştınız.');
      _onInstructionCallback?.call('Hedefe ulaştınız.');
      stopNavigation();
    }
  }
  static void _startPeriodicCheck() {
    _navigationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isNavigationActive) {
        timer.cancel();
        return;
      }
      if (_currentStepIndex < _currentRoute.length) {
        final currentStep = _currentRoute[_currentStepIndex];
        _onInstructionCallback?.call(currentStep.instruction);
      }
    });
  }
  static Future<List<NavigationStep>> _generateNavigationSteps(
    List<LatLng> route,
  ) async {
    if (route.length < 2) return [];
    try {
      final directionsResult = await DirectionsService().getDirections(
        baslangic: route.first,
        hedef: route.last,
        araNoktalar: route.length > 2 ? route.sublist(1, route.length - 1) : null,
      );
      if (directionsResult != null && directionsResult.isValid) {
        final steps = <NavigationStep>[];
        final polylinePoints = directionsResult.latLngNoktalari;
        if (polylinePoints.length >= 2) {
          steps.add(NavigationStep(
            instruction: 'Rotaya başlayın',
            distance: directionsResult.toplamMesafe,
            duration: directionsResult.toplamSure,
            startLocation: polylinePoints.first,
            endLocation: polylinePoints.last,
          ));
          steps.add(NavigationStep(
            instruction: 'Hedefe ulaştınız',
            distance: '0 m',
            duration: '0 min',
            startLocation: polylinePoints.last,
            endLocation: polylinePoints.last,
          ));
        }
        return steps;
      }
    } catch (e) {
      print('Directions API hatası: $e');
    }
    return _generateSimpleSteps(route);
  }
  static List<NavigationStep> _generateSimpleSteps(List<LatLng> route) {
    final steps = <NavigationStep>[];
    for (int i = 0; i < route.length - 1; i++) {
      final start = route[i];
      final end = route[i + 1];
      final distance = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      final bearing = Geolocator.bearingBetween(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      final direction = _getDirectionFromBearing(bearing);
      steps.add(NavigationStep(
        instruction: '${distance.round()} metre $direction yönünde ilerleyin',
        distance: '${distance.round()} m',
        duration: '${(distance / 50).round()} dk',
        startLocation: start,
        endLocation: end,
      ));
    }
    return steps;
  }
  static String _getDirectionFromBearing(double bearing) {
    if (bearing >= -22.5 && bearing < 22.5) return 'kuzey';
    if (bearing >= 22.5 && bearing < 67.5) return 'kuzeydoğu';
    if (bearing >= 67.5 && bearing < 112.5) return 'doğu';
    if (bearing >= 112.5 && bearing < 157.5) return 'güneydoğu';
    if (bearing >= 157.5 || bearing < -157.5) return 'güney';
    if (bearing >= -157.5 && bearing < -112.5) return 'güneybatı';
    if (bearing >= -112.5 && bearing < -67.5) return 'batı';
    if (bearing >= -67.5 && bearing < -22.5) return 'kuzeybatı';
    return 'düz';
  }
  static String _translateToTurkish(String instruction) {
    String translated = instruction
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('Turn left', 'Sola dönün')
        .replaceAll('Turn right', 'Sağa dönün')
        .replaceAll('Continue straight', 'Düz devam edin')
        .replaceAll('Head north', 'Kuzeye doğru ilerleyin')
        .replaceAll('Head south', 'Güneye doğru ilerleyin')
        .replaceAll('Head east', 'Doğuya doğru ilerleyin')
        .replaceAll('Head west', 'Batıya doğru ilerleyin')
        .replaceAll('Slight left', 'Hafif sola')
        .replaceAll('Slight right', 'Hafif sağa')
        .replaceAll('Sharp left', 'Keskin sola')
        .replaceAll('Sharp right', 'Keskin sağa')
        .replaceAll('U-turn', 'U dönüşü yapın')
        .replaceAll('Roundabout', 'Kavşaktan')
        .replaceAll('Exit', 'Çıkış')
        .replaceAll('Merge', 'Birleşin')
        .replaceAll('Keep left', 'Solda kalın')
        .replaceAll('Keep right', 'Sağda kalın')
        .replaceAll('Destination', 'Hedef')
        .replaceAll('meters', 'metre')
        .replaceAll('kilometers', 'kilometre')
        .replaceAll('feet', 'feet')
        .replaceAll('miles', 'mil');
    return translated;
  }
  static bool get isNavigationActive => _isNavigationActive;
  static NavigationStep? get currentStep {
    if (_currentStepIndex < _currentRoute.length) {
      return _currentRoute[_currentStepIndex];
    }
    return null;
  }
  static int get remainingSteps => _currentRoute.length - _currentStepIndex - 1;
  static Future<void> updateTTSSettings({
    double? speechRate,
    double? volume,
    double? pitch,
    String? language,
  }) async {
    if (speechRate != null) {
      await _flutterTts.setSpeechRate(speechRate);
    }
    if (volume != null) {
      await _flutterTts.setVolume(volume);
    }
    if (pitch != null) {
      await _flutterTts.setPitch(pitch);
    }
    if (language != null) {
      await _flutterTts.setLanguage(language);
    }
  }
  static Future<void> dispose() async {
    await stopNavigation();
    _onInstructionCallback = null;
  }
}
class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;
  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
  });
  @override
  String toString() {
    return 'NavigationStep(instruction: $instruction, distance: $distance, duration: $duration)';
  }
}

// Updated


// Updated Again

