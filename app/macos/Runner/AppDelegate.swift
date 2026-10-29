import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static var pendingFilePath: String?
  private static var openFileChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.github.th997.filemanager/open_file",
        binaryMessenger: controller.engine.binaryMessenger
      )
      AppDelegate.openFileChannel = channel
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getInitialFile":
          let file = AppDelegate.pendingFilePath
          AppDelegate.pendingFilePath = nil
          result(file)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    AppDelegate.pendingFilePath = filename
    if let channel = AppDelegate.openFileChannel {
      channel.invokeMethod("onFileOpened", arguments: filename)
    }
    return true
  }
}
