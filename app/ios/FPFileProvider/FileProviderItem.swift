import FileProvider
import Foundation
import UniformTypeIdentifiers

struct FPItemMetadata {
  let identifier: NSFileProviderItemIdentifier
  let parentIdentifier: NSFileProviderItemIdentifier
  let filename: String
  let isDirectory: Bool
  let size: Int64
  let creationDate: Date
  let modificationDate: Date
}

final class FileProviderItem: NSObject, NSFileProviderItem {
  private let meta: FPItemMetadata

  init(metadata: FPItemMetadata) {
    self.meta = metadata
    super.init()
  }

  var itemIdentifier: NSFileProviderItemIdentifier {
    meta.identifier
  }

  var parentItemIdentifier: NSFileProviderItemIdentifier {
    meta.parentIdentifier
  }

  var filename: String {
    meta.filename
  }

  var contentType: UTType {
    if meta.isDirectory || meta.identifier == .rootContainer {
      return .folder
    }
    let ext = (meta.filename as NSString).pathExtension
    if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
      return utType
    }
    return .data
  }

  var documentSize: NSNumber? {
    meta.isDirectory ? nil : NSNumber(value: meta.size)
  }

  var creationDate: Date? {
    meta.creationDate
  }

  var contentModificationDate: Date? {
    meta.modificationDate
  }

  var capabilities: NSFileProviderItemCapabilities {
    if meta.identifier == .rootContainer {
      return [.allowsContentEnumerating, .allowsAddingSubItems]
    }
    if meta.isDirectory {
      return [
        .allowsContentEnumerating,
        .allowsAddingSubItems,
        .allowsRenaming,
        .allowsReparenting,
        .allowsDeleting,
      ]
    }
    return [
      .allowsReading,
      .allowsWriting,
      .allowsRenaming,
      .allowsReparenting,
      .allowsDeleting,
    ]
  }

  var itemVersion: NSFileProviderItemVersion {
    if meta.identifier == .rootContainer {
      return NSFileProviderItemVersion(
        contentVersion: Data("root-v1".utf8),
        metadataVersion: Data("root-v1".utf8)
      )
    }
    let stamp = Int64(meta.modificationDate.timeIntervalSince1970 * 1000)
    let tag = "\(meta.size)-\(stamp)-\(meta.filename)"
    let bytes = Data(tag.utf8.prefix(120))
    return NSFileProviderItemVersion(
      contentVersion: bytes,
      metadataVersion: bytes
    )
  }
}
