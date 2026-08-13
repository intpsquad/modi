import Flutter
import Foundation
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

    let channel = FlutterMethodChannel(
      name: "com.nomara.modi/share_auth",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSession":
        guard let arguments = call.arguments as? [String: Any],
              let idToken = arguments["idToken"] as? String,
              let apiBaseURL = arguments["apiBaseUrl"] as? String,
              !idToken.isEmpty else {
          result(FlutterError(code: "INVALID_SESSION", message: "공유 세션 값이 올바르지 않습니다.", details: nil))
          return
        }
        do {
          try ShareSessionStore.save(idToken: idToken)
          ShareSessionStore.saveAPIBaseURL(apiBaseURL)
          result(nil)
        } catch {
          // The token is never included in the error sent back to Dart or logs.
          result(FlutterError(code: "KEYCHAIN_WRITE_FAILED", message: "공유 세션을 저장하지 못했습니다.", details: nil))
        }
      case "clearSession":
        do {
          try ShareSessionStore.clear()
          UserDefaults(suiteName: ShareSessionStore.appGroupIdentifier)?.removeObject(forKey: "apiBaseURL")
          result(nil)
        } catch {
          result(FlutterError(code: "KEYCHAIN_DELETE_FAILED", message: "공유 세션을 정리하지 못했습니다.", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
