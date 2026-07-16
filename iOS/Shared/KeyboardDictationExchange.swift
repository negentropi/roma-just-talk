import CryptoKit
import Foundation
import VoiceInkCore

enum VoiceInkKeyboardDocumentIdentifierPolicy {
    static func resolve(_ rawValue: Any?) -> UUID? {
        rawValue as? UUID
    }
}

struct VoiceInkKeyboardDictationDelivery: Equatable, Sendable {
    let requestID: UUID
    let text: String
    let shouldLowercase: Bool
    let shouldInsertReturn: Bool
}

struct VoiceInkKeyboardDictationRequest: Equatable, Sendable {
    let requestID: UUID
    let surroundingTextBeforeCursor: String?
}

enum VoiceInkKeyboardDictationExchangeStatus: Equatable, Sendable {
    case none
    case requested(requestID: UUID)
    case ready(requestID: UUID)
    case readyForManualInsertion(requestID: UUID)
    case failed(requestID: UUID, message: String)
    case waitingForOriginalDocument(requestID: UUID)
}

struct VoiceInkKeyboardDictationExchangeStore {
    static let expirationInterval: TimeInterval = 15 * 60

    private enum State: String, Codable {
        case requested
        case succeeded
        case failed
    }

    private struct Exchange: Codable {
        let requestID: UUID
        let documentIdentifier: UUID
        let requestedAt: Date
        var updatedAt: Date
        var state: State
        var surroundingTextBeforeCursor: String?
        var documentContextFingerprint: Data?
        var text: String?
        var shouldLowercase: Bool?
        var shouldInsertReturn: Bool?
        var failureMessage: String?
    }

    private static let storageKey = "keyboardDictationExchange.v1"
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    @discardableResult
    func begin(
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String? = nil,
        surroundingTextAfterCursor: String? = nil,
        requestID: UUID = UUID(),
        now: Date = Date()
    ) -> UUID? {
        let boundedContextBeforeCursor = VoiceInkCursorTextContextPolicy.boundedSuffix(
            surroundingTextBeforeCursor
        )
        let exchange = Exchange(
            requestID: requestID,
            documentIdentifier: documentIdentifier,
            requestedAt: now,
            updatedAt: now,
            state: .requested,
            surroundingTextBeforeCursor: boundedContextBeforeCursor,
            documentContextFingerprint: Self.documentContextFingerprint(
                requestID: requestID,
                beforeCursor: boundedContextBeforeCursor,
                afterCursor: Self.boundedPrefix(surroundingTextAfterCursor)
            ),
            text: nil,
            shouldLowercase: nil,
            shouldInsertReturn: nil,
            failureMessage: nil
        )

        return write(exchange) ? requestID : nil
    }

    func takePendingRequest(now: Date = Date()) -> VoiceInkKeyboardDictationRequest? {
        guard var exchange = read(now: now), exchange.state == .requested else {
            return nil
        }

        let request = VoiceInkKeyboardDictationRequest(
            requestID: exchange.requestID,
            surroundingTextBeforeCursor: exchange.surroundingTextBeforeCursor
        )
        exchange.surroundingTextBeforeCursor = nil
        exchange.updatedAt = now
        return write(exchange) ? request : nil
    }

    @discardableResult
    func complete(
        requestID: UUID,
        text: String,
        shouldLowercase: Bool = false,
        shouldInsertReturn: Bool = false,
        now: Date = Date()
    ) -> Bool {
        guard var exchange = read(now: now),
              exchange.requestID == requestID,
              exchange.state == .requested else {
            return false
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fail(
                requestID: requestID,
                message: "Transcription returned no text.",
                now: now
            )
        }

        exchange.updatedAt = now
        exchange.state = .succeeded
        exchange.surroundingTextBeforeCursor = nil
        exchange.text = text
        exchange.shouldLowercase = shouldLowercase
        exchange.shouldInsertReturn = shouldInsertReturn
        exchange.failureMessage = nil
        return write(exchange)
    }

    @discardableResult
    func fail(
        requestID: UUID,
        message: String,
        now: Date = Date()
    ) -> Bool {
        guard var exchange = read(now: now),
              exchange.requestID == requestID,
              exchange.state == .requested else {
            return false
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        exchange.updatedAt = now
        exchange.state = .failed
        exchange.surroundingTextBeforeCursor = nil
        exchange.text = nil
        exchange.shouldLowercase = nil
        exchange.shouldInsertReturn = nil
        exchange.failureMessage = trimmedMessage.isEmpty ? "Transcription failed." : trimmedMessage
        return write(exchange)
    }

    func status(
        for documentIdentifier: UUID,
        surroundingTextBeforeCursor: String? = nil,
        surroundingTextAfterCursor: String? = nil,
        now: Date = Date()
    ) -> VoiceInkKeyboardDictationExchangeStatus {
        guard let exchange = read(now: now) else {
            return .none
        }

        let documentMatch = documentMatch(
            exchange,
            documentIdentifier: documentIdentifier,
            surroundingTextBeforeCursor: surroundingTextBeforeCursor,
            surroundingTextAfterCursor: surroundingTextAfterCursor
        )
        guard documentMatch != .mismatch else {
            return .waitingForOriginalDocument(requestID: exchange.requestID)
        }

        switch exchange.state {
        case .requested:
            return .requested(requestID: exchange.requestID)
        case .succeeded:
            if documentMatch == .manualConfirmationRequired {
                return .readyForManualInsertion(requestID: exchange.requestID)
            }
            return .ready(requestID: exchange.requestID)
        case .failed:
            return .failed(
                requestID: exchange.requestID,
                message: exchange.failureMessage ?? "Transcription failed."
            )
        }
    }

    func takeCompletedResult(
        for documentIdentifier: UUID,
        surroundingTextBeforeCursor: String? = nil,
        surroundingTextAfterCursor: String? = nil,
        confirmDocumentChange: Bool = false,
        now: Date = Date()
    ) -> VoiceInkKeyboardDictationDelivery? {
        guard let exchange = read(now: now),
              exchange.state == .succeeded,
              let text = exchange.text else {
            return nil
        }

        switch documentMatch(
            exchange,
            documentIdentifier: documentIdentifier,
            surroundingTextBeforeCursor: surroundingTextBeforeCursor,
            surroundingTextAfterCursor: surroundingTextAfterCursor
        ) {
        case .automatic:
            break
        case .manualConfirmationRequired where confirmDocumentChange:
            break
        case .manualConfirmationRequired, .mismatch:
            return nil
        }

        defaults?.removeObject(forKey: Self.storageKey)
        return VoiceInkKeyboardDictationDelivery(
            requestID: exchange.requestID,
            text: text,
            shouldLowercase: exchange.shouldLowercase ?? false,
            shouldInsertReturn: exchange.shouldInsertReturn ?? false
        )
    }

    @discardableResult
    func clear(requestID: UUID, now: Date = Date()) -> Bool {
        guard let exchange = read(now: now), exchange.requestID == requestID else {
            return false
        }

        defaults?.removeObject(forKey: Self.storageKey)
        return true
    }

    private enum DocumentMatch: Equatable {
        case automatic
        case manualConfirmationRequired
        case mismatch
    }

    private func documentMatch(
        _ exchange: Exchange,
        documentIdentifier: UUID,
        surroundingTextBeforeCursor: String?,
        surroundingTextAfterCursor: String?
    ) -> DocumentMatch {
        if exchange.documentIdentifier == documentIdentifier {
            return .automatic
        }

        let originalFingerprint = exchange.documentContextFingerprint
            ?? Self.documentContextFingerprint(
                requestID: exchange.requestID,
                beforeCursor: exchange.surroundingTextBeforeCursor,
                afterCursor: nil
            )
        let currentFingerprint = Self.documentContextFingerprint(
            requestID: exchange.requestID,
            beforeCursor: VoiceInkCursorTextContextPolicy.boundedSuffix(
                surroundingTextBeforeCursor
            ),
            afterCursor: Self.boundedPrefix(surroundingTextAfterCursor)
        )

        guard let originalFingerprint else {
            return currentFingerprint == nil ? .manualConfirmationRequired : .mismatch
        }

        return originalFingerprint == currentFingerprint ? .automatic : .mismatch
    }

    private static func documentContextFingerprint(
        requestID: UUID,
        beforeCursor: String?,
        afterCursor: String?
    ) -> Data? {
        let hasMeaningfulContext = [beforeCursor, afterCursor]
            .compactMap { $0 }
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasMeaningfulContext else {
            return nil
        }

        var payload = Data(requestID.uuidString.utf8)
        append(beforeCursor, to: &payload)
        append(afterCursor, to: &payload)
        return Data(SHA256.hash(data: payload))
    }

    private static func append(_ value: String?, to data: inout Data) {
        let bytes = Data((value ?? "").utf8)
        data.append(value == nil ? 0 : 1)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) {
            data.append(contentsOf: $0)
        }
        data.append(bytes)
    }

    private static func boundedPrefix(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return String(value.prefix(VoiceInkCursorTextContextPolicy.defaultMaximumLength))
    }

    private func read(now: Date) -> Exchange? {
        guard let defaults,
              let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }

        guard let exchange = try? JSONDecoder().decode(Exchange.self, from: data) else {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }

        guard now.timeIntervalSince(exchange.updatedAt) <= Self.expirationInterval else {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }

        return exchange
    }

    private func write(_ exchange: Exchange) -> Bool {
        guard let defaults,
              let data = try? JSONEncoder().encode(exchange) else {
            return false
        }

        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}
