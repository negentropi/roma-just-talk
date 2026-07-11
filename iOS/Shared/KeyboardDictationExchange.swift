import Foundation

struct VoiceInkKeyboardDictationDelivery: Equatable, Sendable {
    let requestID: UUID
    let text: String
    let shouldLowercase: Bool
}

struct VoiceInkKeyboardDictationRequest: Equatable, Sendable {
    let requestID: UUID
    let surroundingTextBeforeCursor: String?
}

enum VoiceInkKeyboardDictationExchangeStatus: Equatable, Sendable {
    case none
    case requested(requestID: UUID)
    case ready(requestID: UUID)
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
        var text: String?
        var shouldLowercase: Bool?
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
        requestID: UUID = UUID(),
        now: Date = Date()
    ) -> UUID? {
        let exchange = Exchange(
            requestID: requestID,
            documentIdentifier: documentIdentifier,
            requestedAt: now,
            updatedAt: now,
            state: .requested,
            surroundingTextBeforeCursor: VoiceInkCursorTextContextPolicy.boundedSuffix(
                surroundingTextBeforeCursor
            ),
            text: nil,
            shouldLowercase: nil,
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
        exchange.failureMessage = trimmedMessage.isEmpty ? "Transcription failed." : trimmedMessage
        return write(exchange)
    }

    func status(
        for documentIdentifier: UUID,
        now: Date = Date()
    ) -> VoiceInkKeyboardDictationExchangeStatus {
        guard let exchange = read(now: now) else {
            return .none
        }

        guard exchange.documentIdentifier == documentIdentifier else {
            return .waitingForOriginalDocument(requestID: exchange.requestID)
        }

        switch exchange.state {
        case .requested:
            return .requested(requestID: exchange.requestID)
        case .succeeded:
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
        now: Date = Date()
    ) -> VoiceInkKeyboardDictationDelivery? {
        guard let exchange = read(now: now),
              exchange.documentIdentifier == documentIdentifier,
              exchange.state == .succeeded,
              let text = exchange.text else {
            return nil
        }

        defaults?.removeObject(forKey: Self.storageKey)
        return VoiceInkKeyboardDictationDelivery(
            requestID: exchange.requestID,
            text: text,
            shouldLowercase: exchange.shouldLowercase ?? false
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
