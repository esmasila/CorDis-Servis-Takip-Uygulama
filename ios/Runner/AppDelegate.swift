import UIKit
import Flutter
import FirebaseCore
import GoogleMaps   // <-- Google Maps import

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Firebase başlat
    FirebaseApp.configure()
    
    // Google Maps iOS API Key (sadece iOS için geçerli olan key'i buraya koy)
    GMSServices.provideAPIKey("AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
