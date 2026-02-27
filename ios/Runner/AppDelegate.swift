import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Platform channel for native timelapse encoding
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "ar_drawing_app/timelapse", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "processVideo" {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing videoPath", details: nil))
          return
        }
        TimelapseEncoder.process(videoPath: videoPath) { success, error in
          DispatchQueue.main.async {
            if success {
              result("saved")
            } else {
              result(FlutterError(code: "PROCESS_FAILED", message: error ?? "Unknown error", details: nil))
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
