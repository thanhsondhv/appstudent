import UIKit
import Flutter
import FirebaseCore // 👈 1. Phải thêm dòng này

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 👈 2. Khởi tạo Firebase ở phía Native TRƯỚC khi đăng ký Plugin
    FirebaseApp.configure() 
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}