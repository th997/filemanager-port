import FileProvider
import Foundation
import UniformTypeIdentifiers

final class FileProviderStore {
  static let shared = FileProviderStore()

  private struct Tombstone: Codable {
    let revision: Int64
    let id: String
  }

  private struct PersistedIndex: Codable {
    var revision: Int64
    var idToRelPath: [String: String]
    var relPathToId: [String: String]
    var tombstones: [Tombstone]
  }

  private let lock = NSLock()
  private let fileManager = FileManager.default
  private let rootDir: URL
  private let filesDir: URL
  private let indexFile: URL
  private var index: PersistedIndex

  private init() {
    let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    self.rootDir = appSupport.appendingPathComponent("FPProviderStore", isDirectory: true)
    self.filesDir = rootDir.appendingPathComponent("files", isDirectory: true)
    self.indexFile = rootDir.appendingPathComponent("index.json")

    try? fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)

    if let data = try? Data(contentsOf: indexFile),
       let decoded = try? JSONDecoder().decode(PersistedIndex.self, from: data) {
      self.index = decoded
    } else {
      self.index = PersistedIndex(
        revision: 1,
        idToRelPath: [:],
        relPathToId: [:],
        tombstones: []
      )
    }

    ensureDefaultContentIfEmptyLocked()
    reconcileDiskLocked()
    saveIndexLocked()
  }

  private func ensureDefaultContentIfEmptyLocked() {
    let existing = (try? fileManager.contentsOfDirectory(atPath: filesDir.path)) ?? []
    let hasVisible = existing.contains { !$0.hasPrefix(".") }
    if !hasVisible {
      let downloads = filesDir.appendingPathComponent("Downloads", isDirectory: true)
      try? fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
    }
  }

  private func normalizeRelPath(_ raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    while trimmed.contains("//") {
      trimmed = trimmed.replacingOccurrences(of: "//", with: "/")
    }
    return trimmed
  }

  private func urlForRelPath(_ relPath: String) -> URL {
    let clean = normalizeRelPath(relPath)
    if clean.isEmpty {
      return filesDir
    }
    return filesDir.appendingPathComponent(clean)
  }

  private func isDirectoryAt(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
      return false
    }
    return isDir.boolValue
  }

  private func assignIdLocked(forRelPath relPath: String) -> String {
    let clean = normalizeRelPath(relPath)
    if let existing = index.relPathToId[clean] {
      return existing
    }
    let id = UUID().uuidString.lowercased()
    index.relPathToId[clean] = id
    index.idToRelPath[id] = clean
    return id
  }

  private func reconcileDiskLocked() {
    var diskRelPaths: [String] = []
    if let enumerator = fileManager.enumerator(
      at: filesDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      let basePath = filesDir.standardizedFileURL.path
      for case let url as URL in enumerator {
        let stdPath = url.standardizedFileURL.path
        guard stdPath.hasPrefix(basePath) else { continue }
        let suffix = String(stdPath.dropFirst(basePath.count))
        let rel = normalizeRelPath(suffix)
        if !rel.isEmpty {
          diskRelPaths.append(rel)
        }
      }
    }

    let diskSet = Set(diskRelPaths)
    let staleIds = index.idToRelPath.compactMap { (id, rel) -> String? in
      diskSet.contains(rel) ? nil : id
    }
    if !staleIds.isEmpty {
      index.revision += 1
      for id in staleIds {
        if let oldRel = index.idToRelPath.removeValue(forKey: id) {
          index.relPathToId.removeValue(forKey: oldRel)
        }
        recordTombstoneLocked(id: id)
      }
    }

    var added = false
    for rel in diskRelPaths where index.relPathToId[rel] == nil {
      _ = assignIdLocked(forRelPath: rel)
      added = true
    }
    if added {
      index.revision += 1
    }
  }

  private func recordTombstoneLocked(id: String) {
    index.tombstones.append(Tombstone(revision: index.revision, id: id))
    if index.tombstones.count > 500 {
      index.tombstones.removeFirst(index.tombstones.count - 500)
    }
  }

  private func saveIndexLocked() {
    guard let data = try? JSONEncoder().encode(index) else { return }
    try? data.write(to: indexFile, options: .atomic)
  }

  private func parentIdentifierLocked(forRelPath relPath: String) -> NSFileProviderItemIdentifier {
    let clean = normalizeRelPath(relPath)
    guard let slashIdx = clean.lastIndex(of: "/") else {
      return .rootContainer
    }
    let parentRel = String(clean[..<slashIdx])
    if parentRel.isEmpty {
      return .rootContainer
    }
    let parentId = assignIdLocked(forRelPath: parentRel)
    return NSFileProviderItemIdentifier(parentId)
  }

  private func metadataLocked(for identifier: NSFileProviderItemIdentifier) -> FPItemMetadata? {
    if identifier == .rootContainer {
      let attrs = try? fileManager.attributesOfItem(atPath: filesDir.path)
      let cDate = (attrs?[.creationDate] as? Date) ?? Date()
      let mDate = (attrs?[.modificationDate] as? Date) ?? Date()
      return FPItemMetadata(
        identifier: .rootContainer,
        parentIdentifier: .rootContainer,
        filename: "FP",
        isDirectory: true,
        size: 0,
        creationDate: cDate,
        modificationDate: mDate
      )
    }
    guard let relPath = index.idToRelPath[identifier.rawValue] else {
      return nil
    }
    let url = urlForRelPath(relPath)
    var isDir: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
      return nil
    }
    let attrs = try? fileManager.attributesOfItem(atPath: url.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let cDate = (attrs?[.creationDate] as? Date) ?? Date()
    let mDate = (attrs?[.modificationDate] as? Date) ?? Date()
    let name = url.lastPathComponent
    return FPItemMetadata(
      identifier: identifier,
      parentIdentifier: parentIdentifierLocked(forRelPath: relPath),
      filename: name,
      isDirectory: isDir.boolValue,
      size: size,
      creationDate: cDate,
      modificationDate: mDate
    )
  }

  private func sanitizeFilename(_ raw: String) -> String {
    let replaced = raw
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if replaced.isEmpty || replaced == "." || replaced == ".." {
      return "untitled"
    }
    return replaced
  }

  private func uniqueChildURL(in dirURL: URL, preferredName: String) -> URL {
    let base = (preferredName as NSString).deletingPathExtension
    let ext = (preferredName as NSString).pathExtension
    var candidate = dirURL.appendingPathComponent(preferredName)
    var counter = 2
    while fileManager.fileExists(atPath: candidate.path) {
      let nextName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
      candidate = dirURL.appendingPathComponent(nextName)
      counter += 1
    }
    return candidate
  }

  func currentAnchorData() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return Data("\(index.revision)".utf8)
  }

  func item(for identifier: NSFileProviderItemIdentifier) -> FileProviderItem? {
    lock.lock()
    defer { lock.unlock() }
    reconcileDiskLocked()
    saveIndexLocked()
    guard let meta = metadataLocked(for: identifier) else { return nil }
    return FileProviderItem(metadata: meta)
  }

  func children(of containerIdentifier: NSFileProviderItemIdentifier) throws -> [FileProviderItem] {
    lock.lock()
    defer { lock.unlock() }
    reconcileDiskLocked()
    saveIndexLocked()

    if containerIdentifier == .trashContainer {
      return []
    }

    let targetDir: URL
    let prefix: String
    if containerIdentifier == .rootContainer {
      targetDir = filesDir
      prefix = ""
    } else if let rel = index.idToRelPath[containerIdentifier.rawValue] {
      targetDir = urlForRelPath(rel)
      prefix = rel
    } else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }

    guard isDirectoryAt(targetDir) else {
      return []
    }

    let names = (try? fileManager.contentsOfDirectory(atPath: targetDir.path)) ?? []
    var items: [FileProviderItem] = []
    for name in names where !name.hasPrefix(".") {
      let childRel = prefix.isEmpty ? name : "\(prefix)/\(name)"
      let id = assignIdLocked(forRelPath: childRel)
      if let meta = metadataLocked(for: NSFileProviderItemIdentifier(id)) {
        items.append(FileProviderItem(metadata: meta))
      }
    }
    saveIndexLocked()
    return items
  }

  func allWorkingSetItems() -> [FileProviderItem] {
    lock.lock()
    defer { lock.unlock() }
    reconcileDiskLocked()
    saveIndexLocked()

    var items: [FileProviderItem] = []
    for id in index.idToRelPath.keys {
      if let meta = metadataLocked(for: NSFileProviderItemIdentifier(id)) {
        items.append(FileProviderItem(metadata: meta))
      }
    }
    return items
  }

  func changes(since anchorData: Data) -> (updated: [FileProviderItem], deleted: [NSFileProviderItemIdentifier], nextAnchor: Data) {
    lock.lock()
    defer { lock.unlock() }
    reconcileDiskLocked()
    saveIndexLocked()

    let rawStr = String(data: anchorData, encoding: .utf8) ?? ""
    let sinceRev = Int64(rawStr) ?? 0
    if sinceRev >= index.revision {
      return ([], [], Data("\(index.revision)".utf8))
    }

    var items: [FileProviderItem] = []
    for id in index.idToRelPath.keys {
      if let meta = metadataLocked(for: NSFileProviderItemIdentifier(id)) {
        items.append(FileProviderItem(metadata: meta))
      }
    }
    let deletedIds = index.tombstones
      .filter { $0.revision > sinceRev }
      .map { NSFileProviderItemIdentifier($0.id) }
    return (items, deletedIds, Data("\(index.revision)".utf8))
  }

  func materializeTempCopy(
    for identifier: NSFileProviderItemIdentifier,
    domain: NSFileProviderDomain
  ) throws -> (url: URL, item: FileProviderItem) {
    lock.lock()
    defer { lock.unlock() }
    reconcileDiskLocked()
    guard let rel = index.idToRelPath[identifier.rawValue],
          let meta = metadataLocked(for: identifier),
          !meta.isDirectory else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }
    let srcUrl = urlForRelPath(rel)
    guard let manager = NSFileProviderManager(for: domain) else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
    }
    let tempDir = try manager.temporaryDirectoryURL()
    let dstUrl = tempDir.appendingPathComponent("\(UUID().uuidString)-\(meta.filename)")
    try? fileManager.removeItem(at: dstUrl)
    try fileManager.copyItem(at: srcUrl, to: dstUrl)
    return (dstUrl, FileProviderItem(metadata: meta))
  }

  func createItem(
    basedOn template: NSFileProviderItem,
    contents: URL?,
    options: NSFileProviderCreateItemOptions
  ) throws -> FileProviderItem {
    lock.lock()
    defer { lock.unlock() }

    let parentRel: String
    if template.parentItemIdentifier == .rootContainer {
      parentRel = ""
    } else if let rel = index.idToRelPath[template.parentItemIdentifier.rawValue] {
      parentRel = rel
    } else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }

    let parentURL = urlForRelPath(parentRel)
    try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

    let safeName = sanitizeFilename(template.filename)
    let isDir = template.contentType?.conforms(to: .folder) == true ||
        template.typeIdentifier == UTType.folder.identifier
    let targetURL: URL
    let desiredURL = parentURL.appendingPathComponent(safeName)
    if fileManager.fileExists(atPath: desiredURL.path) {
      if options.contains(.mayAlreadyExist) {
        let rel = normalizeRelPath(parentRel.isEmpty ? safeName : "\(parentRel)/\(safeName)")
        let id = assignIdLocked(forRelPath: rel)
        saveIndexLocked()
        if let meta = metadataLocked(for: NSFileProviderItemIdentifier(id)) {
          return FileProviderItem(metadata: meta)
        }
      }
      targetURL = uniqueChildURL(in: parentURL, preferredName: safeName)
    } else {
      targetURL = desiredURL
    }

    if isDir {
      try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
    } else if let contents = contents {
      let scoped = contents.startAccessingSecurityScopedResource()
      defer {
        if scoped { contents.stopAccessingSecurityScopedResource() }
      }
      try? fileManager.removeItem(at: targetURL)
      try fileManager.copyItem(at: contents, to: targetURL)
    } else {
      fileManager.createFile(atPath: targetURL.path, contents: Data())
    }

    let finalName = targetURL.lastPathComponent
    let newRel = normalizeRelPath(parentRel.isEmpty ? finalName : "\(parentRel)/\(finalName)")
    index.revision += 1
    let id = assignIdLocked(forRelPath: newRel)
    saveIndexLocked()
    guard let meta = metadataLocked(for: NSFileProviderItemIdentifier(id)) else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }
    return FileProviderItem(metadata: meta)
  }

  func modifyItem(
    _ template: NSFileProviderItem,
    changedFields: NSFileProviderItemFields,
    contents newContents: URL?
  ) throws -> FileProviderItem {
    lock.lock()
    defer { lock.unlock() }

    let itemId = template.itemIdentifier.rawValue
    guard let oldRel = index.idToRelPath[itemId] else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }
    let oldURL = urlForRelPath(oldRel)
    guard fileManager.fileExists(atPath: oldURL.path) else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }

    // Handle trashing cleanly by deleting the backing item.
    if changedFields.contains(.parentItemIdentifier),
       template.parentItemIdentifier == .trashContainer {
      try deleteItemLocked(itemId: itemId)
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }

    let oldParentRel: String = {
      guard let slash = oldRel.lastIndex(of: "/") else { return "" }
      return String(oldRel[..<slash])
    }()

    let targetParentRel: String
    if changedFields.contains(.parentItemIdentifier) {
      if template.parentItemIdentifier == .rootContainer {
        targetParentRel = ""
      } else if let pRel = index.idToRelPath[template.parentItemIdentifier.rawValue] {
        targetParentRel = pRel
      } else {
        throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
      }
    } else {
      targetParentRel = oldParentRel
    }

    let targetName = changedFields.contains(.filename)
      ? sanitizeFilename(template.filename)
      : oldURL.lastPathComponent
    let desiredRel = normalizeRelPath(
      targetParentRel.isEmpty ? targetName : "\(targetParentRel)/\(targetName)"
    )

    var finalRel = oldRel
    var finalURL = oldURL
    if desiredRel != oldRel {
      let parentURL = urlForRelPath(targetParentRel)
      try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
      var dstURL = parentURL.appendingPathComponent(targetName)
      if fileManager.fileExists(atPath: dstURL.path) && dstURL.standardizedFileURL != oldURL.standardizedFileURL {
        dstURL = uniqueChildURL(in: parentURL, preferredName: targetName)
      }
      try fileManager.moveItem(at: oldURL, to: dstURL)
      finalURL = dstURL
      finalRel = normalizeRelPath(
        targetParentRel.isEmpty ? dstURL.lastPathComponent : "\(targetParentRel)/\(dstURL.lastPathComponent)"
      )

      // Update index for moved item and any nested descendants if it was a folder.
      let oldPrefix = oldRel + "/"
      var updatedMappings: [(id: String, newRel: String)] = [(itemId, finalRel)]
      for (childId, childRel) in index.idToRelPath where childRel.hasPrefix(oldPrefix) {
        let suffix = String(childRel.dropFirst(oldPrefix.count))
        updatedMappings.append((childId, "\(finalRel)/\(suffix)"))
      }
      for (id, _) in updatedMappings {
        if let prev = index.idToRelPath[id] {
          index.relPathToId.removeValue(forKey: prev)
        }
      }
      for (id, mapped) in updatedMappings {
        index.idToRelPath[id] = mapped
        index.relPathToId[mapped] = id
      }
    }

    if changedFields.contains(.contents), let newContents = newContents {
      let scoped = newContents.startAccessingSecurityScopedResource()
      defer {
        if scoped { newContents.stopAccessingSecurityScopedResource() }
      }
      let tempWrite = finalURL.deletingLastPathComponent()
        .appendingPathComponent(".\(UUID().uuidString).tmp")
      try? fileManager.removeItem(at: tempWrite)
      try fileManager.copyItem(at: newContents, to: tempWrite)
      _ = try fileManager.replaceItemAt(finalURL, withItemAt: tempWrite)
    }

    index.revision += 1
    saveIndexLocked()
    guard let meta = metadataLocked(for: NSFileProviderItemIdentifier(itemId)) else {
      throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }
    return FileProviderItem(metadata: meta)
  }

  func deleteItem(identifier: NSFileProviderItemIdentifier) throws {
    lock.lock()
    defer { lock.unlock() }
    try deleteItemLocked(itemId: identifier.rawValue)
  }

  private func deleteItemLocked(itemId: String) throws {
    guard let rel = index.idToRelPath[itemId] else {
      return
    }
    let url = urlForRelPath(rel)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    index.revision += 1
    let prefix = rel + "/"
    let removedIds = index.idToRelPath.compactMap { (id, childRel) -> String? in
      (id == itemId || childRel.hasPrefix(prefix)) ? id : nil
    }
    for id in removedIds {
      if let removedRel = index.idToRelPath.removeValue(forKey: id) {
        index.relPathToId.removeValue(forKey: removedRel)
      }
      recordTombstoneLocked(id: id)
    }
    saveIndexLocked()
  }
}
