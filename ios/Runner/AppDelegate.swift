import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let feedbackChannelName = "zone.stomp.vinkit/scanner_feedback"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScannerFeedbackPlugin") {
      let channel = FlutterMethodChannel(
        name: Self.feedbackChannelName,
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "playScanBeep":
          AudioServicesPlaySystemSound(1057)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
