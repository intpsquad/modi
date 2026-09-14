import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 아래 `didInitializeImplicitFlutterEngine` 에서 다시 쏠 때 실어 보내려고 들고 있는다.
  /// 알림으로 앱이 켜진 경우 이 안에 그 알림이 들어 있고, firebase_messaging 이 그것으로
  /// `getInitialMessage()` 를 채운다.
  private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    self.launchOptions = launchOptions
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 🔴 **놓친 앱 실행 알림을 직접 쏜다**(2026-09-14, 이슈 #66).
    //
    // firebase_messaging 15.2.10 은 iOS 알림 배선 **전체**를
    // `UIApplicationDidFinishLaunchingNotification` 관찰자 하나에 몰아 넣는다
    // (`FLTFirebaseMessagingPlugin.m` 의 `application_onDidFinishLaunchingNotification:`,
    // 214-310행): 초기 알림 수집, APNs 스위즐러 설치, 원격 알림 도너 메서드,
    // `addApplicationDelegate:`, `UNUserNotificationCenter.delegate` 설정,
    // 그리고 `registerForRemoteNotifications`.
    //
    // 그 관찰자는 플러그인 `init` 에서 등록되는데, 이 앱은 **UIScene 을 채택**해서
    // (`Info.plist` 의 `UIApplicationSceneManifest`) 플러그인 등록이 바로 위 한 줄에서,
    // 즉 **그 알림이 이미 끝난 뒤에** 일어난다. 관찰자가 영영 안 불려 위 여섯 가지가
    // 통째로 실행되지 않는다. 그래서 푸시가 하나도 오지 않았다(운영 실측: 유저 44명 중
    // 토큰 보유 8명, 서버 로그에는 `FCM 토큰이 없어 푸시를 건너뛴다` 만).
    //
    // ⚠️ **`registerForRemoteNotifications()` 만 직접 부르는 것으로는 부족하다.** 그러면
    // 토큰을 받을 배선(스위즐러·델리게이트)이 없는 채로 등록만 시작되고, 토큰이
    // `Firebase.initializeApp()`(Dart, main.dart) 보다 먼저 도착하면 **아무도 받지 않고
    // 버려진다.** 알림을 쏘면 플러그인이 자기 설정을 전부 마치고, Firebase 가 아직이면
    // 토큰을 스스로 스태시했다가 나중에 흘려보내므로 그 경합이 없다.
    //
    // ⚠️ **반드시 플러그인 등록 뒤여야 한다** — 관찰자가 있어야 알림이 의미가 있다.
    //
    // 권한 팝업과는 무관하다. 팝업은 `UNUserNotificationCenter.requestAuthorization`
    // (Dart 의 `requestPermission`)이 띄운다.
    //
    // 🧹 지우는 시점과 업그레이드 판단은 `docs/fcm-setup.md` 에 있다.
    NotificationCenter.default.post(
      name: UIApplication.didFinishLaunchingNotification,
      object: UIApplication.shared,
      userInfo: launchOptions.map { options in
        // 플러그인은 ObjC 상수 키(`UIApplicationLaunchOptionsRemoteNotificationKey`)로 읽는다.
        // rawValue 로 풀어 두면 브리징에 기대지 않는다.
        Dictionary(uniqueKeysWithValues: options.map { ($0.key.rawValue as AnyHashable, $0.value) })
      }
    )
    launchOptions = nil

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
