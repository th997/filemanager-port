import FileProvider
import Foundation

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
  private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
  private let store = FileProviderStore.shared

  init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
    self.enumeratedItemIdentifier = enumeratedItemIdentifier
    super.init()
  }

  func invalidate() {}

  func enumerateItems(
    for observer: NSFileProviderEnumerationObserver,
    startingAt page: NSFileProviderPage
  ) {
    if enumeratedItemIdentifier == .workingSet {
      let items = store.allWorkingSetItems()
      if !items.isEmpty {
        observer.didEnumerate(items)
      }
      observer.finishEnumerating(upTo: nil)
      return
    }

    do {
      let items = try store.children(of: enumeratedItemIdentifier)
      if !items.isEmpty {
        observer.didEnumerate(items)
      }
      observer.finishEnumerating(upTo: nil)
    } catch {
      observer.finishEnumeratingWithError(error)
    }
  }

  func enumerateChanges(
    for observer: NSFileProviderChangeObserver,
    from anchor: NSFileProviderSyncAnchor
  ) {
    let result = store.changes(since: anchor.rawValue)
    if !result.updated.isEmpty {
      observer.didUpdate(result.updated)
    }
    if !result.deleted.isEmpty {
      observer.didDeleteItems(withIdentifiers: result.deleted)
    }
    observer.finishEnumeratingChanges(
      upTo: NSFileProviderSyncAnchor(result.nextAnchor),
      moreComing: false
    )
  }

  func currentSyncAnchor(
    completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
  ) {
    completionHandler(NSFileProviderSyncAnchor(store.currentAnchorData()))
  }
}
