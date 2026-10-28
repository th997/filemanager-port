import Flutter
import UIKit
import Security
import AVFoundation

private var avPlayerSwizzled = false
private var statusObserverKey: UInt8 = 0
private var itemObserverKey: UInt8 = 0
private var userRequestedPauseKey: UInt8 = 0

extension AVPlayer {
  var fm_userPaused: Bool {
    get {
      return (objc_getAssociatedObject(self, &userRequestedPauseKey) as? Bool) ?? false
    }
    set {
      objc_setAssociatedObject(self, &userRequestedPauseKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  @objc dynamic func fm_observeStatusIfNeeded() {
    guard objc_getAssociatedObject(self, &statusObserverKey) == nil else { return }

    let observation = self.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      guard let self = self else { return }
      // Auto-recovery: if AVPlayer paused on its own without user intervention, resume immediately
      if player.timeControlStatus == .paused && !self.fm_userPaused {
        let curTime = player.currentTime()
        let durTime = player.currentItem?.duration ?? .invalid
        let cur = CMTimeGetSeconds(curTime)
        let dur = CMTimeGetSeconds(durTime)
        let nearEnd = dur.isFinite && dur > 0 && (dur - cur < 0.5)
        if !nearEnd && player.currentItem?.status == .readyToPlay {
          DispatchQueue.main.async { [weak player] in
            guard let player = player, !player.fm_userPaused else { return }
            player.play()
          }
        }
      }
    }
    objc_setAssociatedObject(self, &statusObserverKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    self.fm_observeCurrentItemIfNeeded()
  }

  @objc dynamic func fm_observeCurrentItemIfNeeded() {
    guard let item = self.currentItem else { return }
    guard objc_getAssociatedObject(item, &itemObserverKey) == nil else { return }

    let obs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
      if let self = self, item.isPlaybackLikelyToKeepUp, !self.fm_userPaused && self.timeControlStatus == .paused {
        DispatchQueue.main.async { [weak self] in
          guard let self = self, !self.fm_userPaused else { return }
          self.play()
        }
      }
    }
    objc_setAssociatedObject(item, &itemObserverKey, [obs], .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  @objc dynamic func fm_initWithPlayerItem(_ item: AVPlayerItem?) -> AVPlayer {
    let player = self.fm_initWithPlayerItem(item)
    player.automaticallyWaitsToMinimizeStalling = true
    item?.preferredForwardBufferDuration = 15.0
    player.fm_observeStatusIfNeeded()
    return player
  }

  @objc dynamic func fm_setRate(_ rate: Float) {
    if rate > 0 {
      self.fm_userPaused = false
    }
    fm_observeStatusIfNeeded()
    self.fm_setRate(rate)
  }

  @objc dynamic func fm_play() {
    self.fm_userPaused = false
    self.automaticallyWaitsToMinimizeStalling = true
    fm_observeStatusIfNeeded()
    self.fm_play()
  }

  @objc dynamic func fm_pause() {
    self.fm_userPaused = true
    self.fm_pause()
  }

  @objc dynamic func fm_replaceCurrentItem(with item: AVPlayerItem?) {
    item?.preferredForwardBufferDuration = 15.0
    self.automaticallyWaitsToMinimizeStalling = true
    self.fm_replaceCurrentItem(with: item)
    fm_observeStatusIfNeeded()
  }

  static func swizzleForLowLatencyStreaming() {
    guard !avPlayerSwizzled else { return }
    avPlayerSwizzled = true

    let initSel = NSSelectorFromString("initWithPlayerItem:")
    if let orig = class_getInstanceMethod(AVPlayer.self, initSel),
       let swizz = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.fm_initWithPlayerItem(_:))) {
      method_exchangeImplementations(orig, swizz)
    }

    if let orig = class_getInstanceMethod(AVPlayer.self, #selector(setter: AVPlayer.rate)),
       let swizz = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.fm_setRate(_:))) {
      method_exchangeImplementations(orig, swizz)
    }

    if let orig = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.play)),
       let swizz = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.fm_play)) {
      method_exchangeImplementations(orig, swizz)
    }

    if let orig = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.pause)),
       let swizz = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.fm_pause)) {
      method_exchangeImplementations(orig, swizz)
    }

    if let orig = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.replaceCurrentItem(with:))),
       let swizz = class_getInstanceMethod(AVPlayer.self, #selector(AVPlayer.fm_replaceCurrentItem(with:))) {
      method_exchangeImplementations(orig, swizz)
    }
  }
}

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
    let launchResult = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback
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
      if type == AVAudioSession.InterruptionType.ended.rawValue,
        opts & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0
      {
        try? AVAudioSession.sharedInstance().setActive(true)
      }
    }

    AVPlayer.swizzleForLowLatencyStreaming()

    if let controller = window?.rootViewController as? FlutterViewController {
      AppDelegate.setupKeychainChannel(messenger: controller.binaryMessenger)
    }

    return launchResult
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Runner") {
      AppDelegate.setupKeychainChannel(messenger: registrar.messenger())
    }
  }
}
