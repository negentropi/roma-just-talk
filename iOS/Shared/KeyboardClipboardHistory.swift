import CryptoKit
import Foundation
import VoiceInkCore

enum VoiceInkKeyboardClipboardItemKind: String, Codable, CaseIterable, Sendable {
    case text
    case link
    case image
}

enum VoiceInkKeyboardClipboardFilter: String, CaseIterable, Sendable {
    case all
    case text
    case links
    case images
    case pinned

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .pinned: "Pinned"
        }
    }
}

struct VoiceInkKeyboardClipboardPayload: Equatable, Sendable {
    let kind: VoiceInkKeyboardClipboardItemKind
    let text: String?
    let imageData: Data?

    init?(text: String, kind: VoiceInkKeyboardClipboardItemKind = .text) {
        guard kind != .image,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.kind = kind
        self.text = text
        imageData = nil
    }

    init?(imageData: Data, searchableText: String? = nil) {
        guard !imageData.isEmpty else { return nil }
        kind = .image
        text = searchableText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageData = imageData
    }
}

struct VoiceInkKeyboardClipboardItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: VoiceInkKeyboardClipboardItemKind
    let fingerprint: String
    let createdAt: Date
    var lastUsedAt: Date
    var text: String?
    var imageFileName: String?
    var isPinned: Bool

    var summary: String {
        switch kind {
        case .text, .link:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            let searchableText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return searchableText.isEmpty ? "Clipboard image" : searchableText
        }
    }
}

enum VoiceInkKeyboardClipboardStoreError: LocalizedError, Equatable {
    case imageTooLarge
    case invalidPayload
    case unavailableSharedContainer

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            "That image is too large for keyboard history."
        case .invalidPayload:
            "The clipboard does not contain supported content."
        case .unavailableSharedContainer:
            "Clipboard history needs Full Access to use shared storage."
        }
    }
}

struct VoiceInkKeyboardClipboardSearch {
    static func items(
        _ items: [VoiceInkKeyboardClipboardItem],
        matching query: String,
        filter: VoiceInkKeyboardClipboardFilter
    ) -> [VoiceInkKeyboardClipboardItem] {
        let kindFiltered = items.filter { item in
            switch filter {
            case .all: true
            case .text: item.kind == .text
            case .links: item.kind == .link
            case .images: item.kind == .image
            case .pinned: item.isPinned
            }
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return kindFiltered }
        return kindFiltered.filter {
            $0.summary.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

struct VoiceInkKeyboardClipboardStore {
    static let appGroupDirectoryName = "KeyboardClipboardHistory"
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    static let maximumUnpinnedItemCount = 100
    static let maximumImageByteCount = 8 * 1_024 * 1_024

    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static func appGroupStore(fileManager: FileManager = .default) -> Self? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: VoiceInkAppIdentity.iOSAppGroupIdentifier
        ) else {
            return nil
        }

        return Self(
            directoryURL: containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(Self.appGroupDirectoryName, isDirectory: true),
            fileManager: fileManager
        )
    }

    func items(now: Date = Date()) throws -> [VoiceInkKeyboardClipboardItem] {
        let existing = try readItems()
        let normalized = normalizedItems(existing, now: now)
        if normalized != existing {
            try save(normalized, replacing: existing)
        }
        return normalized
    }

    @discardableResult
    func record(
        _ payload: VoiceInkKeyboardClipboardPayload,
        now: Date = Date()
    ) throws -> VoiceInkKeyboardClipboardItem {
        guard payload.kind == .image ? payload.imageData != nil : payload.text != nil else {
            throw VoiceInkKeyboardClipboardStoreError.invalidPayload
        }
        if let imageData = payload.imageData,
           imageData.count > Self.maximumImageByteCount {
            throw VoiceInkKeyboardClipboardStoreError.imageTooLarge
        }

        let previousItems = try readItems()
        var updatedItems = previousItems
        let fingerprint = Self.fingerprint(for: payload)

        let item: VoiceInkKeyboardClipboardItem
        if let existingIndex = updatedItems.firstIndex(where: { $0.fingerprint == fingerprint }) {
            var existing = updatedItems.remove(at: existingIndex)
            existing.lastUsedAt = now
            existing.text = payload.text
            item = existing
        } else {
            let id = UUID()
            let imageFileName = payload.imageData == nil ? nil : "\(id.uuidString).png"
            item = VoiceInkKeyboardClipboardItem(
                id: id,
                kind: payload.kind,
                fingerprint: fingerprint,
                createdAt: now,
                lastUsedAt: now,
                text: payload.text,
                imageFileName: imageFileName,
                isPinned: false
            )
        }

        if let imageData = payload.imageData,
           let imageFileName = item.imageFileName {
            try ensureDirectoryExists()
            try imageData.write(
                to: directoryURL.appendingPathComponent(imageFileName),
                options: .atomic
            )
            applyFileProtection(to: directoryURL.appendingPathComponent(imageFileName))
        }

        updatedItems.append(item)
        let normalized = normalizedItems(updatedItems, now: now)
        try save(normalized, replacing: previousItems)
        return item
    }

    func togglePinned(id: UUID, now: Date = Date()) throws {
        let previousItems = try readItems()
        var updatedItems = previousItems
        guard let index = updatedItems.firstIndex(where: { $0.id == id }) else { return }
        updatedItems[index].isPinned.toggle()
        updatedItems[index].lastUsedAt = now
        try save(normalizedItems(updatedItems, now: now), replacing: previousItems)
    }

    func markUsed(id: UUID, now: Date = Date()) throws {
        let previousItems = try readItems()
        var updatedItems = previousItems
        guard let index = updatedItems.firstIndex(where: { $0.id == id }) else { return }
        updatedItems[index].lastUsedAt = now
        try save(normalizedItems(updatedItems, now: now), replacing: previousItems)
    }

    func remove(id: UUID) throws {
        let previousItems = try readItems()
        let updatedItems = previousItems.filter { $0.id != id }
        try save(updatedItems, replacing: previousItems)
    }

    func removeAllUnpinned() throws {
        let previousItems = try readItems()
        let updatedItems = previousItems.filter(\.isPinned)
        try save(updatedItems, replacing: previousItems)
    }

    func imageData(for item: VoiceInkKeyboardClipboardItem) throws -> Data? {
        guard let imageFileName = item.imageFileName else { return nil }
        return try Data(contentsOf: directoryURL.appendingPathComponent(imageFileName))
    }
}

private extension VoiceInkKeyboardClipboardStore {
    var indexURL: URL {
        directoryURL.appendingPathComponent("index.json")
    }

    static func fingerprint(for payload: VoiceInkKeyboardClipboardPayload) -> String {
        var data = Data(payload.kind.rawValue.utf8)
        data.append(0)
        if let imageData = payload.imageData {
            data.append(imageData)
        } else if let text = payload.text {
            data.append(Data(text.utf8))
        }

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func readItems() throws -> [VoiceInkKeyboardClipboardItem] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode([VoiceInkKeyboardClipboardItem].self, from: data)
    }

    func normalizedItems(
        _ items: [VoiceInkKeyboardClipboardItem],
        now: Date
    ) -> [VoiceInkKeyboardClipboardItem] {
        let retentionCutoff = now.addingTimeInterval(-Self.retentionInterval)
        let retained = items.filter { $0.isPinned || $0.lastUsedAt >= retentionCutoff }
        let sorted = retained.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }

        var unpinnedCount = 0
        return sorted.filter { item in
            guard !item.isPinned else { return true }
            defer { unpinnedCount += 1 }
            return unpinnedCount < Self.maximumUnpinnedItemCount
        }
    }

    func save(
        _ items: [VoiceInkKeyboardClipboardItem],
        replacing previousItems: [VoiceInkKeyboardClipboardItem]
    ) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: indexURL, options: .atomic)
        applyFileProtection(to: indexURL)

        let retainedImageFiles = Set(items.compactMap(\.imageFileName))
        let removedImageFiles = Set(previousItems.compactMap(\.imageFileName))
            .subtracting(retainedImageFiles)
        for imageFileName in removedImageFiles {
            try? fileManager.removeItem(
                at: directoryURL.appendingPathComponent(imageFileName)
            )
        }
    }

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        applyFileProtection(to: directoryURL)
    }

    func applyFileProtection(to url: URL) {
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
