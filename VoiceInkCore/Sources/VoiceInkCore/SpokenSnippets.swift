import Foundation

/// A spoken phrase and the exact plain text it inserts. Content is never trimmed.
public struct VoiceInkSpokenSnippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var trigger: String
    public var content: String
    public var enabled: Bool

    public init(id: UUID = UUID(), trigger: String, content: String, enabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.enabled = enabled
    }
}

public enum VoiceInkSpokenSnippetValidationIssue: Error, Equatable, Sendable, LocalizedError {
    case emptyTrigger
    case emptyContent
    case triggerTooLong
    case contentTooLong
    case duplicateTrigger
    case duplicateIdentifier
    case tooManySnippets

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger: return "Enter a spoken trigger."
        case .emptyContent: return "Enter the text this snippet should insert."
        case .triggerTooLong: return "Keep the trigger within 60 characters."
        case .contentTooLong: return "Keep the snippet within 4,000 characters."
        case .duplicateTrigger: return "A snippet already uses this trigger."
        case .duplicateIdentifier: return "Two snippets have the same identifier."
        case .tooManySnippets: return "Keep the library within 1,000 snippets."
        }
    }
}

public struct VoiceInkSpokenSnippetImportIssue: Equatable, Sendable {
    public let row: Int
    public let message: String

    public init(row: Int, message: String) {
        self.row = row
        self.message = message
    }
}

public struct VoiceInkSpokenSnippetImportPreview: Equatable, Sendable {
    public let snippets: [VoiceInkSpokenSnippet]
    public let rowIssues: [VoiceInkSpokenSnippetImportIssue]
    public let duplicateTriggers: [String]

    public var canImport: Bool { rowIssues.isEmpty && !snippets.isEmpty }

    public init(
        snippets: [VoiceInkSpokenSnippet],
        rowIssues: [VoiceInkSpokenSnippetImportIssue],
        duplicateTriggers: [String]
    ) {
        self.snippets = snippets
        self.rowIssues = rowIssues
        self.duplicateTriggers = duplicateTriggers
    }
}

public enum VoiceInkSpokenSnippetConflictPolicy: Sendable {
    case keepExisting
    case replaceExisting
    case reject
}

public enum VoiceInkSpokenSnippetImportError: Error, Equatable, Sendable, LocalizedError {
    case invalidPreview
    case duplicateTrigger(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPreview: return "Fix the CSV issues before importing."
        case .duplicateTrigger(let trigger): return "A snippet already uses the trigger \"\(trigger)\"."
        }
    }
}

public struct VoiceInkSpokenSnippetExpansion: Equatable, Sendable {
    public let text: String
    /// True even when the saved content happens to equal the spoken trigger.
    /// Delivery uses this to bypass cleanup that could alter saved content.
    public let didExpand: Bool

    public init(text: String, didExpand: Bool) {
        self.text = text
        self.didExpand = didExpand
    }
}

/// Shared persistence, literal matching and CSV import. No AI is involved in expansion.
public enum VoiceInkSpokenSnippets {
    public enum LoadError: Error, Equatable, Sendable, LocalizedError {
        case unreadableLibrary

        public var errorDescription: String? {
            "Saved snippets couldn't be read. Restore a valid settings backup before making changes."
        }
    }

    public static let userDefaultsKey = "VoiceInkSpokenSnippets"
    public static let maximumTriggerCharacters = 60
    public static let maximumContentCharacters = 4_000
    public static let maximumSnippetCount = 1_000
    public static let maximumCSVBytes = 3_000_000

    public static func normalizedTrigger(_ trigger: String) -> String {
        trigger.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
    }

    public static func validate(
        _ snippet: VoiceInkSpokenSnippet,
        among existing: [VoiceInkSpokenSnippet] = []
    ) -> VoiceInkSpokenSnippetValidationIssue? {
        let trigger = normalizedTrigger(snippet.trigger)
        if trigger.isEmpty { return .emptyTrigger }
        if snippet.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyContent }
        if trigger.count > maximumTriggerCharacters { return .triggerTooLong }
        if snippet.content.count > maximumContentCharacters { return .contentTooLong }
        if existing.contains(where: { $0.id != snippet.id && triggerKey($0.trigger) == triggerKey(trigger) }) {
            return .duplicateTrigger
        }
        return nil
    }

    public static func load(from defaults: UserDefaults = .standard) -> [VoiceInkSpokenSnippet] {
        (try? loadForMutation(from: defaults)) ?? []
    }

    /// A failed read must stop a write, rather than replace saved snippets with a new library.
    public static func loadForMutation(from defaults: UserDefaults = .standard) throws -> [VoiceInkSpokenSnippet] {
        guard let stored = defaults.object(forKey: userDefaultsKey) else { return [] }
        guard let data = stored as? Data else {
            throw LoadError.unreadableLibrary
        }
        do {
            return try validated(JSONDecoder().decode([VoiceInkSpokenSnippet].self, from: data))
        } catch {
            throw LoadError.unreadableLibrary
        }
    }

    /// Validate and encode everything before touching the previous stored library.
    public static func save(_ snippets: [VoiceInkSpokenSnippet], to defaults: UserDefaults = .standard) throws {
        let valid = try validated(snippets)
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: userDefaultsKey)
    }

    public static func expand(_ text: String, using snippets: [VoiceInkSpokenSnippet]) -> String {
        expansion(of: text, using: snippets).text
    }

    public static func entireSnippet(
        for text: String,
        using snippets: [VoiceInkSpokenSnippet]
    ) -> VoiceInkSpokenSnippet? {
        let active = snippets.filter { $0.enabled && validate($0) == nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = active.first(where: { triggerKey($0.trigger) == triggerKey(trimmed) }) {
            return exact
        }
        var bare = trimmed
        while let last = bare.last, ".!?,;:。！？、；：".contains(last) {
            bare.removeLast()
            bare = bare.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = active.first(where: { triggerKey($0.trigger) == triggerKey(bare) }) {
                return exact
            }
        }
        return nil
    }

    public static func expansion(
        of text: String,
        using snippets: [VoiceInkSpokenSnippet]
    ) -> VoiceInkSpokenSnippetExpansion {
        let active = snippets.filter { $0.enabled && validate($0) == nil }
        guard !active.isEmpty, !text.isEmpty else { return .init(text: text, didExpand: false) }
        if let exact = entireSnippet(for: text, using: active) {
            return .init(text: exact.content, didExpand: true)
        }

        struct Match {
            let range: Range<String.Index>
            let content: String
            let length: Int
            let order: Int
        }
        var matches: [Match] = []
        for (order, snippet) in active.enumerated() {
            let words = normalizedTrigger(snippet.trigger).split(separator: " ")
            let bounded = needsWordBoundaries(snippet.trigger)
            // Advance one character after a match's start, so overlapping phrases
            // compete before replacements are chosen; expansions are never scanned.
            var cursor = text.startIndex
            while cursor < text.endIndex {
                if let end = matchEnd(words, in: text, from: cursor) {
                    let previous = cursor > text.startIndex ? text[text.index(before: cursor)] : nil
                    let next = end < text.endIndex ? text[end] : nil
                    if !bounded || (!isWordCharacter(previous) && !isWordCharacter(next)) {
                        let range = cursor..<end
                        matches.append(Match(range: range, content: snippet.content, length: normalizedTrigger(snippet.trigger).count, order: order))
                    }
                }
                cursor = text.index(after: cursor)
            }
        }
        matches.sort {
            if $0.length != $1.length { return $0.length > $1.length }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.order < $1.order
        }
        var chosen: [Match] = []
        for match in matches where !chosen.contains(where: { $0.range.overlaps(match.range) }) {
            chosen.append(match)
        }
        chosen.sort { $0.range.lowerBound < $1.range.lowerBound }
        var output = ""
        var cursor = text.startIndex
        for match in chosen {
            output += text[cursor..<match.range.lowerBound]
            output += match.content
            cursor = match.range.upperBound
        }
        output += text[cursor...]
        return .init(text: output, didExpand: !chosen.isEmpty)
    }

    public static func csvString(for snippets: [VoiceInkSpokenSnippet]) -> String {
        let rows = snippets.map {
            [normalizedTrigger($0.trigger), $0.content, $0.enabled ? "true" : "false"]
                .map(csvField).joined(separator: ",")
        }
        return (["trigger,content,enabled"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    public static func previewImport(
        _ csv: String,
        existing: [VoiceInkSpokenSnippet] = []
    ) -> VoiceInkSpokenSnippetImportPreview {
        func failure(_ row: Int, _ message: String) -> VoiceInkSpokenSnippetImportPreview {
            .init(snippets: [], rowIssues: [.init(row: row, message: message)], duplicateTriggers: [])
        }
        guard csv.utf8.count <= maximumCSVBytes else { return failure(1, "Keep the CSV within 3 MB.") }
        let parsed = parseCSV(csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv)
        var issues = parsed.issue.map { [$0] } ?? []
        guard let header = parsed.rows.first else { return failure(1, "The CSV needs a trigger,content header.") }
        let columns = header.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard columns.count == 2 || columns.count == 3,
              Set(columns).count == columns.count,
              let triggerIndex = columns.firstIndex(of: "trigger"),
              let contentIndex = columns.firstIndex(of: "content"),
              columns.count == 2 || columns.contains("enabled") else {
            return failure(header.line, "Use the CSV header trigger,content with an optional enabled column.")
        }
        let enabledIndex = columns.firstIndex(of: "enabled")
        var snippets: [VoiceInkSpokenSnippet] = []
        var seen = Set(existing.map { triggerKey($0.trigger) })
        var duplicateKeys = Set<String>()
        var duplicateTriggers: [String] = []
        for row in parsed.rows.dropFirst() {
            guard row.fields.count == columns.count else {
                issues.append(.init(row: row.line, message: "Expected \(columns.count) CSV columns."))
                continue
            }
            var enabled = true
            if let enabledIndex {
                switch row.fields[enabledIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true": enabled = true
                case "false": enabled = false
                default:
                    issues.append(.init(row: row.line, message: "Enabled must be true or false."))
                    continue
                }
            }
            let snippet = VoiceInkSpokenSnippet(
                trigger: normalizedTrigger(row.fields[triggerIndex]),
                content: row.fields[contentIndex],
                enabled: enabled
            )
            if let problem = validate(snippet) {
                issues.append(.init(row: row.line, message: problem.localizedDescription))
                continue
            }
            let key = triggerKey(snippet.trigger)
            if !seen.insert(key).inserted && duplicateKeys.insert(key).inserted {
                duplicateTriggers.append(snippet.trigger)
            }
            snippets.append(snippet)
        }
        if snippets.count > maximumSnippetCount {
            issues.append(.init(row: 1, message: "Import at most 1,000 snippets at once."))
        }
        if snippets.isEmpty && issues.isEmpty {
            issues.append(.init(row: 1, message: "The CSV has no snippets to import."))
        }
        return .init(snippets: snippets, rowIssues: issues, duplicateTriggers: duplicateTriggers)
    }

    /// Resolve every conflict before returning a complete library. Call save once
    /// with the result; a rejected import never applies a partial set of rows.
    public static func merged(
        _ preview: VoiceInkSpokenSnippetImportPreview,
        with existing: [VoiceInkSpokenSnippet],
        policy: VoiceInkSpokenSnippetConflictPolicy
    ) throws -> [VoiceInkSpokenSnippet] {
        guard preview.canImport else { throw VoiceInkSpokenSnippetImportError.invalidPreview }
        var result = try validated(existing)
        for source in preview.snippets {
            if let issue = validate(source) { throw issue }
            var snippet = source
            snippet.trigger = normalizedTrigger(source.trigger)
            if let index = result.firstIndex(where: { triggerKey($0.trigger) == triggerKey(snippet.trigger) }) {
                switch policy {
                case .keepExisting: continue
                case .replaceExisting:
                    snippet.id = result[index].id
                    result[index] = snippet
                case .reject: throw VoiceInkSpokenSnippetImportError.duplicateTrigger(snippet.trigger)
                }
            } else {
                result.append(snippet)
            }
        }
        return try validated(result)
    }

    /// Pure preflight for backup/import callers before they mutate other settings.
    public static func validated(_ snippets: [VoiceInkSpokenSnippet]) throws -> [VoiceInkSpokenSnippet] {
        guard snippets.count <= maximumSnippetCount else { throw VoiceInkSpokenSnippetValidationIssue.tooManySnippets }
        var ids = Set<UUID>()
        var triggers = Set<String>()
        return try snippets.map { source in
            if let issue = validate(source) { throw issue }
            guard ids.insert(source.id).inserted else { throw VoiceInkSpokenSnippetValidationIssue.duplicateIdentifier }
            guard triggers.insert(triggerKey(source.trigger)).inserted else { throw VoiceInkSpokenSnippetValidationIssue.duplicateTrigger }
            var snippet = source
            snippet.trigger = normalizedTrigger(source.trigger)
            return snippet
        }
    }

    private static func triggerKey(_ trigger: String) -> String {
        normalizedTrigger(trigger).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func matchEnd(_ words: [Substring], in text: String, from start: String.Index) -> String.Index? {
        var cursor = start
        for (index, word) in words.enumerated() {
            if index > 0 {
                let beforeWhitespace = cursor
                while cursor < text.endIndex, text[cursor].isWhitespace { cursor = text.index(after: cursor) }
                guard cursor > beforeWhitespace else { return nil }
            }
            guard cursor < text.endIndex,
                  let range = text.range(
                    of: word,
                    options: [.caseInsensitive, .anchored],
                    range: cursor..<text.endIndex,
                    locale: Locale(identifier: "en_US_POSIX")
                  ) else { return nil }
            cursor = range.upperBound
        }
        return cursor
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" || $0 == "\r\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func needsWordBoundaries(_ trigger: String) -> Bool {
        !trigger.unicodeScalars.contains {
            switch $0.value {
            case 0x0E00...0x0E7F, 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF: return true
            default: return false
            }
        }
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "_" || character.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }
    }

    private struct CSVRow {
        let line: Int
        let fields: [String]
    }

    private static func parseCSV(_ text: String) -> (rows: [CSVRow], issue: VoiceInkSpokenSnippetImportIssue?) {
        enum State: Equatable { case start, unquoted, quoted, afterQuote }
        var state = State.start
        var rows: [CSVRow] = []
        var fields: [String] = []
        var field = ""
        var line = 1
        var rowLine = 1
        func finishRow() {
            fields.append(field)
            if fields != [""] { rows.append(CSVRow(line: rowLine, fields: fields)) }
            fields = []
            field = ""
            state = .start
        }
        for character in text {
            let newline = character == "\n" || character == "\r" || character == "\r\n"
            switch state {
            case .start:
                if character == "\"" { state = .quoted }
                else if character == "," { fields.append("") }
                else if newline { finishRow() }
                else { field.append(character); state = .unquoted }
            case .unquoted:
                if character == "\"" {
                    return (rows, .init(row: line, message: "A quote inside a field must be escaped in a quoted field."))
                } else if character == "," {
                    fields.append(field); field = ""; state = .start
                } else if newline { finishRow() }
                else { field.append(character) }
            case .quoted:
                if character == "\"" { state = .afterQuote }
                else { field.append(character) }
            case .afterQuote:
                if character == "\"" { field.append(character); state = .quoted }
                else if character == "," { fields.append(field); field = ""; state = .start }
                else if newline { finishRow() }
                else { return (rows, .init(row: line, message: "Unexpected text after a closing quote.")) }
            }
            if newline {
                line += 1
                if state != .quoted { rowLine = line }
            }
        }
        if state == .quoted { return (rows, .init(row: rowLine, message: "The quoted field has no closing quote.")) }
        if !field.isEmpty || !fields.isEmpty || state == .afterQuote { finishRow() }
        return (rows, nil)
    }
}
