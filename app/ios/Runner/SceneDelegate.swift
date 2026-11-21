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
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupChannels(from: scene)
    if !connectionOptions.urlContexts.isEmpty {
      AppDelegate.handleIncomingURLContexts(connectionOptions.urlContexts)
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    setupChannels(from: scene)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    setupChannels(from: scene)
    if !URLContexts.isEmpty {
      AppDelegate.handleIncomingURLContexts(URLContexts)
    }
  }
}
