import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RoomAudioSession")
    else { return }
    let channel = FlutterMethodChannel(
      name: "internalization_room/audio_session",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let session = AVAudioSession.sharedInstance()
      switch call.method {
      case "sampleRate":
        result(session.sampleRate)
      case "preferSampleRate":
        guard let rate = call.arguments as? Double else {
          result(FlutterError(code: "BAD_RATE", message: nil, details: nil))
          return
        }
        do {
          try session.setPreferredSampleRate(rate)
          result(nil)
        } catch {
          result(
            FlutterError(code: "SESSION", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
