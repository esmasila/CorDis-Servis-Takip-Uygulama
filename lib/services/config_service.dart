import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService {
  static const String _googleMapsApiKey = 'GOOGLE_MAPS_API_KEY';
  static const String _firebaseApiKeyWeb = 'FIREBASE_API_KEY_WEB';
  static const String _firebaseApiKeyAndroid = 'FIREBASE_API_KEY_ANDROID';
  static const String _firebaseApiKeyIos = 'FIREBASE_API_KEY_IOS';
  static const String _firebaseProjectId = 'FIREBASE_PROJECT_ID';
  static const String _firebaseMessagingSenderId =
      'FIREBASE_MESSAGING_SENDER_ID';
  static const String _firebaseStorageBucket = 'FIREBASE_STORAGE_BUCKET';
  static const String _firebaseAuthDomain = 'FIREBASE_AUTH_DOMAIN';
  static const String _firebaseMeasurementId = 'FIREBASE_MEASUREMENT_ID';

  // Google Maps API Key
  static String get googleMapsApiKey {
    final key = dotenv.env[_googleMapsApiKey];
    if (key == null || key.isEmpty) {
      throw Exception('Google Maps API key not found in environment variables');
    }
    return key;
  }

  // Firebase Configuration
  static String get firebaseApiKeyWeb {
    final key = dotenv.env[_firebaseApiKeyWeb];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Web API key not found in environment variables');
    }
    return key;
  }

  static String get firebaseApiKeyAndroid {
    final key = dotenv.env[_firebaseApiKeyAndroid];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Android API key not found in environment variables');
    }
    return key;
  }

  static String get firebaseApiKeyIos {
    final key = dotenv.env[_firebaseApiKeyIos];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase iOS API key not found in environment variables');
    }
    return key;
  }

  static String get firebaseProjectId {
    final key = dotenv.env[_firebaseProjectId];
    if (key == null || key.isEmpty) {
      throw Exception('Firebase Project ID not found in environment variables');
    }
    return key;
  }

  static String get firebaseMessagingSenderId {
    final key = dotenv.env[_firebaseMessagingSenderId];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Messaging Sender ID not found in environment variables');
    }
    return key;
  }

  static String get firebaseStorageBucket {
    final key = dotenv.env[_firebaseStorageBucket];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Storage Bucket not found in environment variables');
    }
    return key;
  }

  static String get firebaseAuthDomain {
    final key = dotenv.env[_firebaseAuthDomain];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Auth Domain not found in environment variables');
    }
    return key;
  }

  static String get firebaseMeasurementId {
    final key = dotenv.env[_firebaseMeasurementId];
    if (key == null || key.isEmpty) {
      throw Exception(
          'Firebase Measurement ID not found in environment variables');
    }
    return key;
  }

  // Initialize the configuration service
  static Future<void> initialize() async {
    await dotenv.load(fileName: ".env");
  }
}





