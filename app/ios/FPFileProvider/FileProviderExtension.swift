import FileProvider
import Foundation

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
  private let domain: NSFileProviderDomain
  private let store = FileProviderStore.shared

  required init(domain: NSFileProviderDomain) {
    self.domain = domain
    super.init()
  }

  func invalidate() {}

  private func signalWorkingSet() {
    NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
  }

  func item(
    for identifier: NSFileProviderItemIdentifier,
    request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    if let item = store.item(for: identifier) {
      completionHandler(item, nil)
    } else {
      completionHandler(
        nil,
        NSError(
          domain: NSFileProviderErrorDomain,
          code: NSFileProviderError.noSuchItem.rawValue
        )
      )
    }
    return Progress()
  }

  func fetchContents(
    for itemIdentifier: NSFileProviderItemIdentifier,
    version requestedVersion: NSFileProviderItemVersion?,
    request: NSFileProviderRequest,
    completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    do {
      let (tempUrl, item) = try store.materializeTempCopy(
        for: itemIdentifier,
        domain: domain
      )
      completionHandler(tempUrl, item, nil)
    } catch {
      completionHandler(nil, nil, error)
    }
    return Progress()
  }

  func createItem(
    basedOn itemTemplate: NSFileProviderItem,
    fields: NSFileProviderItemFields,
    contents url: URL?,
    options: NSFileProviderCreateItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    do {
      let created = try store.createItem(
        basedOn: itemTemplate,
        contents: url,
        options: options
      )
      signalWorkingSet()
      completionHandler(created, [], false, nil)
    } catch {
      completionHandler(nil, [], false, error)
    }
    return Progress()
  }

  func modifyItem(
    _ item: NSFileProviderItem,
    baseVersion version: NSFileProviderItemVersion,
    changedFields: NSFileProviderItemFields,
    contents newContents: URL?,
    options: NSFileProviderModifyItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    do {
      let updated = try store.modifyItem(
        item,
        changedFields: changedFields,
        contents: newContents
      )
      signalWorkingSet()
      completionHandler(updated, [], false, nil)
    } catch {
      completionHandler(nil, [], false, error)
    }
    return Progress()
  }

  func deleteItem(
    identifier: NSFileProviderItemIdentifier,
    baseVersion version: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping (Error?) -> Void
  ) -> Progress {
    do {
      try store.deleteItem(identifier: identifier)
      signalWorkingSet()
      completionHandler(nil)
    } catch {
      completionHandler(error)
    }
    return Progress()
  }

  func enumerator(
    for containerItemIdentifier: NSFileProviderItemIdentifier,
    request: NSFileProviderRequest
  ) throws -> NSFileProviderEnumerator {
    if containerItemIdentifier != .rootContainer &&
        containerItemIdentifier != .workingSet &&
        containerItemIdentifier != .trashContainer &&
        store.item(for: containerItemIdentifier) == nil {
      throw NSError(
        domain: NSFileProviderErrorDomain,
        code: NSFileProviderError.noSuchItem.rawValue
      )
    }
    return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
  }
}
