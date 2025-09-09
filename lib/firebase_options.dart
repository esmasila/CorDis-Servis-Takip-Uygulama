import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'services/config_service.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
        apiKey: ConfigService.firebaseApiKeyWeb,
        appId: '1:283736871966:web:78e0052aea544581800a0f',
        messagingSenderId: ConfigService.firebaseMessagingSenderId,
        projectId: ConfigService.firebaseProjectId,
        authDomain: ConfigService.firebaseAuthDomain,
        storageBucket: ConfigService.firebaseStorageBucket,
        measurementId: ConfigService.firebaseMeasurementId,
      );
  static FirebaseOptions get android => FirebaseOptions(
        apiKey: ConfigService.firebaseApiKeyAndroid,
        appId: '1:283736871966:android:cf3f8ff89d360e55800a0f',
        messagingSenderId: ConfigService.firebaseMessagingSenderId,
        projectId: ConfigService.firebaseProjectId,
        storageBucket: ConfigService.firebaseStorageBucket,
      );
  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: ConfigService.firebaseApiKeyIos,
        appId: '1:283736871966:ios:a41db2bba32c8b2f800a0f',
        messagingSenderId: ConfigService.firebaseMessagingSenderId,
        projectId: ConfigService.firebaseProjectId,
        storageBucket: ConfigService.firebaseStorageBucket,
        iosBundleId: 'com.example.servisTakipUygulama',
      );
  static FirebaseOptions get macos => FirebaseOptions(
        apiKey: ConfigService.firebaseApiKeyIos,
        appId: '1:283736871966:ios:a41db2bba32c8b2f800a0f',
        messagingSenderId: ConfigService.firebaseMessagingSenderId,
        projectId: ConfigService.firebaseProjectId,
        storageBucket: ConfigService.firebaseStorageBucket,
        iosBundleId: 'com.example.servisTakipUygulama',
      );
}



 Again


