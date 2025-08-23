import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
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
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDU9DVmj9Et8DmJVeEahvPX2jlgm7e3Ipw',
    appId: '1:283736871966:web:78e0052aea544581800a0f',
    messagingSenderId: '283736871966',
    projectId: 'servis-takip-uygulama',
    authDomain: 'servis-takip-uygulama.firebaseapp.com',
    storageBucket: 'servis-takip-uygulama.firebasestorage.app',
    measurementId: 'G-BD67ZE7ETF',
  );
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA7t0-yEER8KVruoUi5Msbqlo7bNh0WkM0',
    appId: '1:283736871966:android:cf3f8ff89d360e55800a0f',
    messagingSenderId: '283736871966',
    projectId: 'servis-takip-uygulama',
    storageBucket: 'servis-takip-uygulama.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCUlKQGtxJzw3qXOa-wCi3eoMzwI9PVtSw',
    appId: '1:283736871966:ios:a41db2bba32c8b2f800a0f',
    messagingSenderId: '283736871966',
    projectId: 'servis-takip-uygulama',
    storageBucket: 'servis-takip-uygulama.firebasestorage.app',
    iosBundleId: 'com.example.servisTakipUygulama',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCUlKQGtxJzw3qXOa-wCi3eoMzwI9PVtSw',
    appId: '1:283736871966:ios:a41db2bba32c8b2f800a0f',
    messagingSenderId: '283736871966',
    projectId: 'servis-takip-uygulama',
    storageBucket: 'servis-takip-uygulama.firebasestorage.app',
    iosBundleId: 'com.example.servisTakipUygulama',
  );
}
