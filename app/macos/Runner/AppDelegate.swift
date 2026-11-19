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
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()

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

  @objc func openInFileManager(
    _ pboard: NSPasteboard,
    userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    var targetPath: String?
    if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
       let first = urls.first {
      targetPath = first.path
    } else if let paths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
              let first = paths.first {
      targetPath = first
    }

    guard let path = targetPath, !path.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)
    AppDelegate.dispatchOpenedFile(path)
  }

  private static func dispatchOpenedFile(_ path: String) {
    guard !path.isEmpty else { return }
    AppDelegate.pendingFilePath = path
    if let channel = AppDelegate.openFileChannel {
      channel.invokeMethod("onFileOpened", arguments: path)
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    AppDelegate.dispatchOpenedFile(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if let first = filenames.first {
      AppDelegate.dispatchOpenedFile(first)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.isFileURL {
        AppDelegate.dispatchOpenedFile(url.path)
        break
      }
    }
    application.reply(toOpenOrPrint: .success)
  }
}
