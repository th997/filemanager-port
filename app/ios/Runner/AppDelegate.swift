import Flutter
import UIKit
import Security
import AVFoundation
import MediaPlayer

private var avPlayerSwizzled = false
private var statusObserverKey: UInt8 = 0
private var itemObserverKey: UInt8 = 0
private var userRequestedPauseKey: UInt8 = 0
private var targetRateKey: UInt8 = 0
private var savedPlayerKey: UInt8 = 0
private let activeAVPlayers = NSHashTable<AVPlayer>.weakObjects()

private func makeSilentAudioData() -> Data {
  let sampleRate: Int32 = 8000
  let numChannels: Int16 = 1
  let bitsPerSample: Int16 = 16
  let byteRate: Int32 = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
  let blockAlign: Int16 = numChannels * (bitsPerSample / 8)
  let pcmDataSize: Int32 = sampleRate * Int32(blockAlign)
  let chunkSize: Int32 = 36 + pcmDataSize

  var data = Data()
  data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
  data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
  data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
  data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
  data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
  data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
  data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
  data.append(contentsOf: withUnsafeBytes(of: pcmDataSize.littleEndian) { Array($0) })
  data.append(Data(count: Int(pcmDataSize)))
  return data
}

private class SilentAudioKeepAlive {
  static let shared = SilentAudioKeepAlive()
  private var audioPlayer: AVAudioPlayer?

  private init() {}

  func start() {
    guard audioPlayer == nil else {
      if audioPlayer?.isPlaying == false {
        audioPlayer?.play()
      }
      return
    }
    let data = makeSilentAudioData()
    do {
      let player = try AVAudioPlayer(data: data)
      player.numberOfLoops = -1
      player.volume = 0.01
      player.prepareToPlay()
      player.play()
      self.audioPlayer = player
      NSLog("SilentAudioKeepAlive: started")
    } catch {
      NSLog("SilentAudioKeepAlive: failed: \(error)")
    }
  }

  func stop() {
    guard let player = audioPlayer else { return }
    player.stop()
    audioPlayer = nil
    NSLog("SilentAudioKeepAlive: stopped")
  }
}

private func getAllPlayerLayers() -> [AVPlayerLayer] {
  var result: [AVPlayerLayer] = []
  var roots: [CALayer] = []

  if let window = (UIApplication.shared.delegate as? AppDelegate)?.window {
    roots.append(window.layer)
  }
  for scene in UIApplication.shared.connectedScenes {
    if let windowScene = scene as? UIWindowScene {
      for win in windowScene.windows {
        roots.append(win.layer)
      }
    }
  }

  func search(layer: CALayer) {
    if let pl = layer as? AVPlayerLayer {
      result.append(pl)
    }
    if let sub = layer.sublayers {
      for child in sub {
        search(layer: child)
      }
    }
  }

  for r in roots {
    search(layer: r)
  }
  return result
}

private func detachAllPlayerLayers() {
  for layer in getAllPlayerLayers() {
    if let player = layer.player {
      objc_setAssociatedObject(layer, &savedPlayerKey, player, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      layer.player = nil
      NSLog("AVPlayerLayer: detached player")
    }
  }
}

private func reattachAllPlayerLayers() {
  for layer in getAllPlayerLayers() {
    if let player = objc_getAssociatedObject(layer, &savedPlayerKey) as? AVPlayer {
      layer.player = player
      objc_setAssociatedObject(layer, &savedPlayerKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      NSLog("AVPlayerLayer: reattached player")
    }
  }
}

private func isAnyPlayerActive() -> Bool {
  for player in activeAVPlayers.allObjects {
    if !player.fm_userPaused {
      return true
    }
  }
  return false
}

extension AVPlayer {
  var fm_userPaused: Bool {
    get {
      return (objc_getAssociatedObject(self, &userRequestedPauseKey) as? Bool) ?? false
    }
    set {
      objc_setAssociatedObject(self, &userRequestedPauseKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  var fm_targetRate: Float {
    get {
      return (objc_getAssociatedObject(self, &targetRateKey) as? Float) ?? 1.0
    }
    set {
      objc_setAssociatedObject(self, &targetRateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  func fm_resumePlayback() {
    guard !self.fm_userPaused else { return }
    let target = self.fm_targetRate > 0 ? self.fm_targetRate : 1.0
    if #available(iOS 16.0, *) {
      self.defaultRate = target
    }
    if target != 1.0 {
      self.rate = target
    } else {
      self.play()
    }
  }

  @objc dynamic func fm_observeStatusIfNeeded() {
    activeAVPlayers.add(self)
    guard objc_getAssociatedObject(self, &statusObserverKey) == nil else { return }

    let observation = self.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      guard let self = self else { return }
      if player.timeControlStatus == .paused && !self.fm_userPaused {
        let curTime = player.currentTime()
        let durTime = player.currentItem?.duration ?? .invalid
        let cur = CMTimeGetSeconds(curTime)
        let dur = CMTimeGetSeconds(durTime)
        let nearEnd = dur.isFinite && dur > 0 && (dur - cur < 0.5)
        if !nearEnd && player.currentItem?.status == .readyToPlay {
          DispatchQueue.main.async { [weak player] in
            guard let player = player, !player.fm_userPaused else { return }
            player.fm_resumePlayback()
          }
        }
      } else if player.timeControlStatus == .paused && self.fm_userPaused {
        if !isAnyPlayerActive() {
          SilentAudioKeepAlive.shared.stop()
        }
      }
    }
    objc_setAssociatedObject(self, &statusObserverKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    self.fm_observeCurrentItemIfNeeded()
  }

  @objc dynamic func fm_observeCurrentItemIfNeeded() {
    guard let item = self.currentItem else { return }
    guard objc_getAssociatedObject(item, &itemObserverKey) == nil else { return }

    let obs1 = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
      if let self = self, item.isPlaybackLikelyToKeepUp, !self.fm_userPaused && self.timeControlStatus != .playing {
        DispatchQueue.main.async { [weak self] in
          guard let self = self, !self.fm_userPaused else { return }
          self.fm_resumePlayback()
        }
      }
    }

    let obs2 = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemPlaybackStalled,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self = self, !self.fm_userPaused else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, !self.fm_userPaused else { return }
        self.fm_resumePlayback()
      }
    }

    objc_setAssociatedObject(item, &itemObserverKey, [obs1, obs2], .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  static var customForwardBufferDuration: TimeInterval = 15.0

  @objc dynamic func fm_initWithPlayerItem(_ item: AVPlayerItem?) -> AVPlayer {
    let player = self.fm_initWithPlayerItem(item)
    player.automaticallyWaitsToMinimizeStalling = true
    item?.preferredForwardBufferDuration = AVPlayer.customForwardBufferDuration
    player.fm_observeStatusIfNeeded()
    return player
  }

  @objc dynamic func fm_setRate(_ rate: Float) {
    if rate > 0 {
      self.fm_userPaused = false
      self.fm_targetRate = rate
      if #available(iOS 16.0, *) {
        self.defaultRate = rate
      }
    }
    fm_observeStatusIfNeeded()
    self.fm_setRate(rate)
  }

  @objc dynamic func fm_play() {
    self.fm_userPaused = false
    self.automaticallyWaitsToMinimizeStalling = true
    fm_observeStatusIfNeeded()
    let target = self.fm_targetRate > 0 ? self.fm_targetRate : 1.0
    if #available(iOS 16.0, *) {
      self.defaultRate = target
    }
    if target != 1.0 {
      self.fm_setRate(target)
    } else {
      self.fm_play()
    }
  }

  @objc dynamic func fm_pause() {
    self.fm_userPaused = true
    self.fm_pause()
    if !isAnyPlayerActive() {
      SilentAudioKeepAlive.shared.stop()
    }
  }

  @objc dynamic func fm_replaceCurrentItem(with item: AVPlayerItem?) {
    item?.preferredForwardBufferDuration = AVPlayer.customForwardBufferDuration
    self.automaticallyWaitsToMinimizeStalling = true
    self.fm_replaceCurrentItem(with: item)
    if item != nil {
      fm_observeStatusIfNeeded()
    } else {
      self.fm_userPaused = true
      activeAVPlayers.remove(self)
      if !isAnyPlayerActive() {
        SilentAudioKeepAlive.shared.stop()
      }
    }
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

  static func save(key: String, data: String, thisDeviceOnly: Bool = false) -> Bool {
    guard let valueData = data.data(using: .utf8) else { return false }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
    let accessibility: CFString = thisDeviceOnly
      ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      : kSecAttrAccessibleAfterFirstUnlock
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: valueData,
      kSecAttrAccessible as String: accessibility,
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

private class NowPlayingManager {
  static let shared = NowPlayingManager()
  private var channel: FlutterMethodChannel?
  private var isConfigured = false

  func setupChannel(messenger: FlutterBinaryMessenger) {
    let chan = FlutterMethodChannel(
      name: "com.github.th997.filemanager/now_playing",
      binaryMessenger: messenger
    )
    self.channel = chan
    chan.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "update":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        self?.update(args: args)
        result(true)
      case "setBufferDuration":
        if let args = call.arguments as? [String: Any], let sec = args["seconds"] as? Double {
          AVPlayer.customForwardBufferDuration = max(1.0, sec)
          for player in activeAVPlayers.allObjects {
            player.currentItem?.preferredForwardBufferDuration = AVPlayer.customForwardBufferDuration
          }
          result(true)
        } else {
          result(false)
        }
      case "clear":
        self?.clear()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    setupRemoteCommands()
  }

  private func setupRemoteCommands() {
    guard !isConfigured else { return }
    isConfigured = true

    DispatchQueue.main.async {
      UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    center.playCommand.removeTarget(nil)
    center.playCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        for player in activeAVPlayers.allObjects {
          player.fm_userPaused = false
          player.fm_resumePlayback()
        }
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "play")
      }
      return .success
    }

    center.pauseCommand.isEnabled = true
    center.pauseCommand.removeTarget(nil)
    center.pauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        for player in activeAVPlayers.allObjects {
          player.fm_pause()
        }
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "pause")
      }
      return .success
    }

    center.togglePlayPauseCommand.isEnabled = true
    center.togglePlayPauseCommand.removeTarget(nil)
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "togglePlayPause")
      }
      return .success
    }

    center.changePlaybackPositionCommand.isEnabled = true
    center.changePlaybackPositionCommand.removeTarget(nil)
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let targetSeconds = posEvent.positionTime
      DispatchQueue.main.async {
        for player in activeAVPlayers.allObjects {
          player.seek(to: CMTime(seconds: targetSeconds, preferredTimescale: 600))
        }
        self?.channel?.invokeMethod("onRemoteCommand", arguments: ["seek": targetSeconds])
      }
      return .success
    }

    center.skipForwardCommand.preferredIntervals = [10]
    center.skipForwardCommand.isEnabled = true
    center.skipForwardCommand.removeTarget(nil)
    center.skipForwardCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "forward10")
      }
      return .success
    }

    center.skipBackwardCommand.preferredIntervals = [10]
    center.skipBackwardCommand.isEnabled = true
    center.skipBackwardCommand.removeTarget(nil)
    center.skipBackwardCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "rewind10")
      }
      return .success
    }

    center.nextTrackCommand.isEnabled = true
    center.nextTrackCommand.removeTarget(nil)
    center.nextTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "next")
      }
      return .success
    }

    center.previousTrackCommand.isEnabled = true
    center.previousTrackCommand.removeTarget(nil)
    center.previousTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.channel?.invokeMethod("onRemoteCommand", arguments: "prev")
      }
      return .success
    }
  }

  func update(args: [String: Any]) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

    if let title = args["title"] as? String {
      info[MPMediaItemPropertyTitle] = title
    }
    if let artist = args["artist"] as? String {
      info[MPMediaItemPropertyArtist] = artist
    } else {
      info[MPMediaItemPropertyArtist] = "FileManager"
    }

    let duration = (args["duration"] as? Double) ?? 0.0
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }

    if let position = args["position"] as? Double {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    }

    let rate = (args["rate"] as? Double) ?? 0.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = rate
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

    let isAudio = (args["isAudio"] as? Bool) ?? false
    info[MPNowPlayingInfoPropertyMediaType] = isAudio
      ? MPNowPlayingInfoMediaType.audio.rawValue
      : MPNowPlayingInfoMediaType.video.rawValue

    if let hasNext = args["hasNext"] as? Bool {
      MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
    }
    if let hasPrev = args["hasPrev"] as? Bool {
      MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = hasPrev
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }
    NSLog("NowPlayingManager: updated title=\(args["title"] ?? "") rate=\(rate) duration=\(duration)")
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    NSLog("NowPlayingManager: cleared")
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static var pendingFilePath: String?
  static var pendingSharePaths: [String]?
  static var openFileChannel: FlutterMethodChannel?
  private static weak var configuredMessenger: AnyObject?
  private static var recentIncomingURLs: [String: Date] = [:]
  private static var privacyMaskEnabled = false
  private static let privacyBlurTag = 948271

  static func setupChannelsIfNeeded(messenger: FlutterBinaryMessenger) {
    let messengerObj = messenger as AnyObject
    if configuredMessenger !== messengerObj {
      configuredMessenger = messengerObj
      setupKeychainChannel(messenger: messenger)
      setupVaultNativeChannel(messenger: messenger)
      setupOpenFileChannel(messenger: messenger)
      NowPlayingManager.shared.setupChannel(messenger: messenger)
      NSLog("AppDelegate: all method channels configured")
    }
    deliverPendingRequestsIfNeeded()
  }

  static func deliverPendingRequestsIfNeeded() {
    DispatchQueue.main.async {
      if let paths = pendingSharePaths, !paths.isEmpty {
        deliverSharedFiles([])
      }
      if let path = pendingFilePath, !path.isEmpty {
        deliverOpenedFile(path)
      }
    }
  }

  static func setupOpenFileChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.github.th997.filemanager/open_file",
      binaryMessenger: messenger
    )
    openFileChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getInitialFile":
        let file = pendingFilePath
        pendingFilePath = nil
        result(file)
      case "getInitialShareRequest":
        let paths = pendingSharePaths
        pendingSharePaths = nil
        result(paths)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func isChannelDeliverySuccess(_ response: Any?) -> Bool {
    return (response as? Bool) == true
  }

  private static func deliverOpenedFile(_ path: String) {
    pendingFilePath = path
    guard let channel = openFileChannel else {
      NSLog("[ShareReceiver] openFileChannel not ready, queued opened file: \(path)")
      return
    }
    DispatchQueue.main.async {
      guard let fileToDeliver = pendingFilePath, !fileToDeliver.isEmpty else { return }
      NSLog("[ShareReceiver] Invoking onFileOpened: \(fileToDeliver)")
      channel.invokeMethod("onFileOpened", arguments: fileToDeliver) { response in
        let ok = isChannelDeliverySuccess(response)
        NSLog("[ShareReceiver] onFileOpened ack=\(ok) rawResponse=\(String(describing: response))")
        if ok && pendingFilePath == fileToDeliver {
          pendingFilePath = nil
        }
      }
    }
  }

  private static func deliverSharedFiles(_ paths: [String]) {
    var merged = pendingSharePaths ?? []
    for path in paths {
      if !merged.contains(path) {
        merged.append(path)
      }
    }
    guard !merged.isEmpty else { return }
    pendingSharePaths = merged

    guard let channel = openFileChannel else {
      NSLog("[ShareReceiver] openFileChannel not ready, queued \(merged.count) shared file(s)")
      return
    }
    DispatchQueue.main.async {
      guard let pathsToDeliver = pendingSharePaths, !pathsToDeliver.isEmpty else { return }
      NSLog("[ShareReceiver] Invoking onShareReceived with \(pathsToDeliver.count) path(s): \(pathsToDeliver)")
      channel.invokeMethod("onShareReceived", arguments: ["paths": pathsToDeliver]) { response in
        let ok = isChannelDeliverySuccess(response)
        NSLog("[ShareReceiver] onShareReceived ack=\(ok) rawResponse=\(String(describing: response))")
        guard ok else { return }
        if pendingSharePaths == pathsToDeliver {
          pendingSharePaths = nil
        } else if let current = pendingSharePaths {
          let remaining = current.filter { !pathsToDeliver.contains($0) }
          pendingSharePaths = remaining.isEmpty ? nil : remaining
        }
      }
    }
  }

  static func handleIncomingFile(url: URL) {
    handleIncomingFiles(urls: [url])
  }

  static func handleIncomingURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
    let urls = urlContexts
      .map { $0.url }
      .sorted { $0.absoluteString < $1.absoluteString }
    handleIncomingFiles(urls: urls)
  }

  static func handleIncomingFiles(urls: [URL]) {
    let enqueue: () -> Void = {
      guard !urls.isEmpty else { return }
      let now = Date()
      recentIncomingURLs = recentIncomingURLs.filter { now.timeIntervalSince($0.value) < 1.5 }
      var accepted: [URL] = []
      for url in urls {
        let key = url.absoluteString
        if recentIncomingURLs[key] != nil {
          continue
        }
        recentIncomingURLs[key] = now
        accepted.append(url)
      }
      guard !accepted.isEmpty else { return }
      NSLog("[ShareReceiver] Accepted \(accepted.count) incoming URL(s): \(accepted.map { $0.absoluteString })")

      DispatchQueue.global(qos: .userInitiated).async {
        var resolvedPaths: [String] = []
        for url in accepted {
          if let path = resolveIncomingUrl(url), !resolvedPaths.contains(path) {
            resolvedPaths.append(path)
          }
        }
        guard !resolvedPaths.isEmpty else {
          NSLog("[ShareReceiver] No incoming URLs could be resolved")
          return
        }
        DispatchQueue.main.async {
          if resolvedPaths.count == 1 {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedPaths[0], isDirectory: &isDir), isDir.boolValue {
              deliverOpenedFile(resolvedPaths[0])
              return
            }
          }
          deliverSharedFiles(resolvedPaths)
        }
      }
    }

    if Thread.isMainThread {
      enqueue()
    } else {
      DispatchQueue.main.async(execute: enqueue)
    }
  }

  private static func isPathInside(_ path: String, dir: String) -> Bool {
    guard !dir.isEmpty else { return false }
    if path == dir { return true }
    let prefix = dir.hasSuffix("/") ? dir : dir + "/"
    return path.hasPrefix(prefix)
  }

  static func resolveIncomingUrl(_ url: URL) -> String? {
    guard url.isFileURL else { return nil }

    let hasScoped = url.startAccessingSecurityScopedResource()
    var retainScopedAccess = false
    defer {
      if hasScoped && !retainScopedAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    let resolvedUrl = url.resolvingSymlinksInPath()
    let resolvedPath = resolvedUrl.path

    var isDir: ObjCBool = false
    if fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue {
      if hasScoped {
        retainScopedAccess = true
      }
      return resolvedPath
    }

    let rawDocs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
    let rawTmp = NSTemporaryDirectory()
    let rawCaches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""

    let docsUrl = (rawDocs.isEmpty
      ? (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: rawTmp))
      : URL(fileURLWithPath: rawDocs)).resolvingSymlinksInPath()
    let tmpUrl = URL(fileURLWithPath: rawTmp.isEmpty ? NSTemporaryDirectory() : rawTmp).resolvingSymlinksInPath()
    let docsPath = rawDocs.isEmpty ? "" : docsUrl.path
    let tmpPath = tmpUrl.path
    let cachesPath = rawCaches.isEmpty ? "" : URL(fileURLWithPath: rawCaches).resolvingSymlinksInPath().path

    if isPathInside(resolvedPath, dir: docsPath) ||
       isPathInside(resolvedPath, dir: tmpPath) ||
       isPathInside(resolvedPath, dir: cachesPath) {
      if fileManager.fileExists(atPath: resolvedPath) {
        return resolvedPath
      }
    }

    let inboxDir = tmpUrl.appendingPathComponent("inbox", isDirectory: true)
    try? fileManager.createDirectory(at: inboxDir, withIntermediateDirectories: true, attributes: nil)

    let rawName = url.lastPathComponent
    let fileName = (rawName.isEmpty || rawName == "/")
      ? "shared_\(Int(Date().timeIntervalSince1970))"
      : rawName
    var destUrl = inboxDir.appendingPathComponent(fileName)

    if destUrl.resolvingSymlinksInPath().path == resolvedPath {
      return resolvedPath
    }

    if fileManager.fileExists(atPath: destUrl.path) {
      let ext = (fileName as NSString).pathExtension
      let base = (fileName as NSString).deletingPathExtension
      var count = 1
      repeat {
        let candidateName = ext.isEmpty ? "\(base)_\(count)" : "\(base)_\(count).\(ext)"
        destUrl = inboxDir.appendingPathComponent(candidateName)
        count += 1
      } while fileManager.fileExists(atPath: destUrl.path)
    }

    func attemptCopy(from source: URL, to dest: URL) -> Bool {
      try? fileManager.removeItem(at: dest)
      do {
        try fileManager.copyItem(at: source, to: dest)
        return fileManager.fileExists(atPath: dest.path)
      } catch {
        try? fileManager.removeItem(at: dest)
        if let data = try? Data(contentsOf: source) {
          do {
            try data.write(to: dest, options: .atomic)
            return fileManager.fileExists(atPath: dest.path)
          } catch {
            try? fileManager.removeItem(at: dest)
          }
        }
        return false
      }
    }

    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var copied = false
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readUrl in
      copied = attemptCopy(from: readUrl, to: destUrl)
    }
    if copied {
      return destUrl.resolvingSymlinksInPath().path
    }

    var uploadError: NSError?
    coordinator.coordinate(readingItemAt: url, options: .forUploading, error: &uploadError) { readUrl in
      copied = attemptCopy(from: readUrl, to: destUrl)
    }
    if copied {
      return destUrl.resolvingSymlinksInPath().path
    }

    if attemptCopy(from: url, to: destUrl) {
      return destUrl.resolvingSymlinksInPath().path
    }

    NSLog("[ShareReceiver] Failed to copy \(url): coordError=\(String(describing: coordError)) uploadError=\(String(describing: uploadError))")
    if fileManager.isReadableFile(atPath: resolvedPath) {
      if hasScoped {
        retainScopedAccess = true
      }
      return resolvedPath
    }
    return nil
  }

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
        let thisDeviceOnly = args["thisDeviceOnly"] as? Bool ?? false
        result(KeychainHelper.save(key: key, data: value, thisDeviceOnly: thisDeviceOnly))
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

  private static func allAppWindows() -> [UIWindow] {
    var windows: [UIWindow] = []
    if let w = (UIApplication.shared.delegate as? AppDelegate)?.window {
      windows.append(w)
    }
    for scene in UIApplication.shared.connectedScenes {
      if let ws = scene as? UIWindowScene {
        for w in ws.windows where !windows.contains(w) {
          windows.append(w)
        }
      }
    }
    return windows
  }

  static func showPrivacyBlurOverlay() {
    for window in allAppWindows() {
      if window.viewWithTag(privacyBlurTag) != nil { continue }
      let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
      blur.frame = window.bounds
      blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      blur.tag = privacyBlurTag
      window.addSubview(blur)
    }
  }

  static func removePrivacyBlurOverlay() {
    for window in allAppWindows() {
      window.viewWithTag(privacyBlurTag)?.removeFromSuperview()
    }
  }

  private static func setupVaultNativeChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.github.th997.filemanager/vault_native",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "excludeFromBackup":
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
          result(false)
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(true)
        } catch {
          NSLog("excludeFromBackup failed: \(error)")
          result(false)
        }
      case "setPrivacyMask":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        AppDelegate.privacyMaskEnabled = enabled
        if !enabled {
          DispatchQueue.main.async {
            AppDelegate.removePrivacyBlurOverlay()
          }
        }
        result(true)
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

    application.beginReceivingRemoteControlEvents()

    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
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

    center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { _ in
      if isAnyPlayerActive() {
        SilentAudioKeepAlive.shared.start()
        detachAllPlayerLayers()
        for player in activeAVPlayers.allObjects {
          player.fm_resumePlayback()
        }
      } else {
        SilentAudioKeepAlive.shared.stop()
      }
    }

    center.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { _ in
      SilentAudioKeepAlive.shared.stop()
      reattachAllPlayerLayers()
      for player in activeAVPlayers.allObjects {
        if !player.fm_userPaused {
          player.fm_resumePlayback()
        }
      }
    }

    center.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      if AppDelegate.privacyMaskEnabled {
        AppDelegate.showPrivacyBlurOverlay()
      }
    }

    center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      AppDelegate.removePrivacyBlurOverlay()
    }

    AVPlayer.swizzleForLowLatencyStreaming()

    if let controller = window?.rootViewController as? FlutterViewController {
      AppDelegate.setupChannelsIfNeeded(messenger: controller.binaryMessenger)
    }

    return launchResult
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    AppDelegate.handleIncomingFile(url: url)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Runner") {
      AppDelegate.setupChannelsIfNeeded(messenger: registrar.messenger())
    }
  }
}
