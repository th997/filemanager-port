import Flutter
import UIKit
import Security
import AVFoundation

private class KeychainHelper {
  static let service = "com.github.th997.filemanager.keychain"

  static func save(key: String, data: String) -> Bool {
    guard let valueData = data.data(using: .utf8) else { return false }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: valueData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(attributes as CFDictionary, nil)
    return status == errSecSuccess
  }

  static func read(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static func setupKeychainChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.github.th997.filemanager/keychain",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a dictionary", details: nil))
        return
      }
      switch call.method {
      case "save":
        guard let key = args["key"] as? String, let value = args["value"] as? String else {
          result(false)
          return
        }
        result(KeychainHelper.save(key: key, data: value))
      case "read":
        guard let key = args["key"] as? String else {
          result(nil)
          return
        }
        result(KeychainHelper.read(key: key))
      case "delete":
        guard let key = args["key"] as? String else {
          result(false)
          return
        }
        result(KeychainHelper.delete(key: key))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      // `.allowBluetooth` is only valid with the playAndRecord category; passing
      // it here makes setCategory throw, which previously left the session at
      // the default (non-mixing) category.
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try AVAudioSession.sharedInstance().setActive(true)
      NSLog("AudioSession: configured category=\(AVAudioSession.sharedInstance().category.rawValue)")
    } catch {
      NSLog("AudioSession: configure failed: \(error)")
    }

    let center = NotificationCenter.default
    center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { note in
      let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
      let opts = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      NSLog("AudioSession: interruption type=\(type) options=\(opts)")
      if type == AVAudioSession.InterruptionType.ended.rawValue,
        opts & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0
      {
        try? AVAudioSession.sharedInstance().setActive(true)
        NSLog("AudioSession: reactivated after interruption")
      }
    }
    center.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { note in
      let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
      NSLog("AudioSession: route change reason=\(reason)")
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      AppDelegate.setupKeychainChannel(messenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeychainBackupPlugin") {
      AppDelegate.setupKeychainChannel(messenger: registrar.messenger())
    }
  }
}
