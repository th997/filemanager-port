import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private func setupChannels(from scene: UIScene) {
    let windowScene = scene as? UIWindowScene
    if let controller = (windowScene?.windows.first?.rootViewController as? FlutterViewController) ?? (window?.rootViewController as? FlutterViewController) {
      AppDelegate.setupChannelsIfNeeded(messenger: controller.binaryMessenger)
    }
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if !connectionOptions.urlContexts.isEmpty {
      AppDelegate.handleIncomingURLContexts(connectionOptions.urlContexts)
    }
    if let shortcutItem = connectionOptions.shortcutItem {
      AppDelegate.deliverShortcutItem(shortcutItem)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupChannels(from: scene)
    AppDelegate.deliverPendingRequestsIfNeeded()
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    AppDelegate.deliverShortcutItem(shortcutItem)
    completionHandler(true)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    setupChannels(from: scene)
    AppDelegate.deliverPendingRequestsIfNeeded()
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if !URLContexts.isEmpty {
      AppDelegate.handleIncomingURLContexts(URLContexts)
    }
    super.scene(scene, openURLContexts: URLContexts)
    setupChannels(from: scene)
    AppDelegate.deliverPendingRequestsIfNeeded()
  }
}
