import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test func writingProviderChecksRejectMissingMeaning() {
        let incomplete: [(WritingProviderFixture, String)] = [
            (.japaneseToEnglish, "RJT-482"),
            (.englishToTraditionalChinese, "RJT-482"),
            (.conciseSelection, "Atlas Mina Friday 10:30 RJT-482.")
        ]
        for (fixture, output) in incomplete {
            let accepted = fixture.checks(output).allSatisfy { $0.passed }
            #expect(!accepted)
        }
        let complete: [(WritingProviderFixture, String)] = [
            (.japaneseToEnglish, "Let's meet at the south exit of Taipei Main Station tomorrow at 3 p.m.; the confirmation code is RJT-482."),
            (.englishToTraditionalChinese, "我們明天下午3點在台北車站南出口見面，確認代碼為RJT-482。"),
            (.conciseSelection, "Mina, the Atlas review moved to Friday at 10:30 at Taipei Main Station; please use ticket RJT-482 when replying.")
        ]
        for (fixture, output) in complete {
            let accepted = fixture.checks(output).allSatisfy { $0.passed }
            #expect(accepted)
        }
    }

    @Test(.enabled(if: WritingProviderEnvironment.isEnabled))
    @MainActor func writingProviderTranslatesJapaneseToEnglish() async throws {
        try await verifyWritingProvider(.japaneseToEnglish)
    }

    @Test(.enabled(if: WritingProviderEnvironment.isEnabled))
    @MainActor func writingProviderTranslatesEnglishToTraditionalChinese() async throws {
        try await verifyWritingProvider(.englishToTraditionalChinese)
    }

    @Test(.enabled(if: WritingProviderEnvironment.isEnabled))
    @MainActor func writingProviderRewritesTheSuppliedSelection() async throws {
        try await verifyWritingProvider(.conciseSelection)
    }

    @MainActor private func verifyWritingProvider(_ fixture: WritingProviderFixture) async throws {
        let environment = try WritingProviderEnvironment()
        let defaults = UserDefaults.standard
        let domain = try #require(Bundle.main.bundleIdentifier)
        let keys = [
            VoiceInkUserDefaultsKey.selectedAIProvider,
            VoiceInkUserDefaultsKey.selectedAIProviderModel(VoiceInkAIEnhancementProviderKind.groq.rawValue),
            VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
            VoiceInkUserDefaultsKey.customPrompts,
            VoiceInkUserDefaultsKey.selectedPromptId,
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout
        ]
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer {
            for key in keys {
                if let value = original[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(VoiceInkAIEnhancementProviderKind.groq.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(VoiceInkAIEnhancementProviderKind.groq.rawValue))
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(45, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)

        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let aiService = AIService()
        aiService.apiKey = environment.apiKey
        aiService.isAPIKeyValid = true
        defer {
            aiService.apiKey = ""
            aiService.isAPIKeyValid = false
        }
        let service = AIEnhancementService(aiService: aiService, modelContext: ModelContext(container))
        try #require(aiService.selectedProvider == .groq)
        try #require(!service.isEnhancementEnabled)
        let provider = try service.providerSnapshot()
        let request = try VoiceInkWritingActionRequest(
            kind: fixture.kind,
            transcript: fixture.transcript,
            selectedText: fixture.selectedText,
            targetLanguage: fixture.targetLanguage
        )

        do {
            let result = try await service.performWritingAction(request, using: provider)
            let output = environment.redacted(result.text)
            let checks = fixture.checks(output)
            let receipt = WritingProviderReceipt(
                fixture: fixture,
                provider: aiService.selectedProvider.rawValue,
                model: result.modelName ?? provider.modelName,
                endpoint: VoiceInkAIEnhancementProviderKind.groq.textEnhancementRequestURLString(),
                ordinaryEnhancementEnabled: service.isEnhancementEnabled,
                output: output,
                checks: checks,
                status: checks.allSatisfy(\.passed) ? "passed" : "failed-semantic-check",
                error: nil
            )
            try environment.save(receipt)
            for check in checks {
                #expect(check.passed, "\(fixture.id): \(check.requirement)")
            }
        } catch {
            let message = environment.redacted(error.localizedDescription)
            try environment.save(WritingProviderReceipt(
                fixture: fixture,
                provider: aiService.selectedProvider.rawValue,
                model: provider.modelName,
                endpoint: VoiceInkAIEnhancementProviderKind.groq.textEnhancementRequestURLString(),
                ordinaryEnhancementEnabled: service.isEnhancementEnabled,
                output: nil,
                checks: [],
                status: "failed-provider-or-evidence",
                error: message
            ))
            throw WritingProviderFailure(message: message)
        }
    }
}

private struct WritingProviderFixture: Codable {
    enum Language: String, Codable { case english, traditionalChinese }

    let id: String
    let kind: VoiceInkWritingActionKind
    let transcript: String
    let selectedText: String
    let targetLanguage: String
    let expectedLanguage: Language
    let exactTerms: [String]
    let alternativeFacts: [[String]]
    let maximumWords: Int?
    let maximumSentences: Int?
    let forbiddenPhrases: [String]

    static let japaneseToEnglish = Self(
        id: "japanese-to-english",
        kind: .translate,
        transcript: "明日の午後3時に台北駅の南口で会いましょう。確認コードは RJT-482 です。",
        selectedText: "",
        targetLanguage: "en",
        expectedLanguage: .english,
        exactTerms: ["RJT-482"],
        alternativeFacts: [
            ["Taipei Main Station", "Taipei Station", "Taipei Railway Station"],
            ["south exit", "southern exit", "south entrance", "southern entrance"],
            ["tomorrow"],
            ["3 p.m.", "3 pm", "3pm", "3:00 p.m.", "3:00 pm", "3:00pm", "15:00", "three in the afternoon", "3 in the afternoon", "three p.m."]
        ],
        maximumWords: nil,
        maximumSentences: nil,
        forbiddenPhrases: ["here is the translation", "here's the translation"]
    )

    static let englishToTraditionalChinese = Self(
        id: "english-to-traditional-chinese",
        kind: .translate,
        transcript: "Meet me at the south exit of Taipei Main Station tomorrow at 3 p.m. The confirmation code is RJT-482.",
        selectedText: "",
        targetLanguage: "zh-Hant",
        expectedLanguage: .traditionalChinese,
        exactTerms: ["RJT-482"],
        alternativeFacts: [
            ["台北車站", "臺北車站", "台北火車站", "臺北火車站"],
            ["南口", "南出口", "南側出口", "南邊出口"],
            ["明天", "明日"],
            ["下午3", "下午 3", "下午三", "午後3", "午後 3", "15:00"],
            ["確認", "代碼", "代號", "編號"]
        ],
        maximumWords: nil,
        maximumSentences: nil,
        forbiddenPhrases: ["车站", "确认", "代码", "见面", "请", "会面"]
    )

    static let conciseSelection = Self(
        id: "concise-selection",
        kind: .rewriteSelection,
        transcript: "Rewrite this as one concise sentence. Preserve who the update is for, what changed, the time and place, and the reply instructions. Do not add a greeting or sign-off.",
        selectedText: "Hello Mina. This is a fairly long update about our Atlas project. I am writing to let you know that we moved the review to Friday at 10:30 at Taipei Main Station. Please use ticket RJT-482 when you reply. Thank you for your patience and understanding.",
        targetLanguage: "",
        expectedLanguage: .english,
        exactTerms: ["Atlas", "Mina", "Friday", "10:30", "Taipei Main Station", "RJT-482"],
        alternativeFacts: [
            ["review"],
            ["moved", "rescheduled", "now scheduled", "now on"],
            ["reply", "replies", "respond", "responding", "response"]
        ],
        maximumWords: 35,
        maximumSentences: 1,
        forbiddenPhrases: ["hello", "dear Mina", "thank you", "patience", "here is", "here's"]
    )

    func checks(_ output: String) -> [WritingProviderCheck] {
        let folded = output.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var checks = [WritingProviderCheck(requirement: "Returns nonempty output", passed: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)]
        checks += exactTerms.map { .init(requirement: "Preserves \($0) exactly", passed: output.contains($0)) }
        checks += alternativeFacts.map { alternatives in
            .init(
                requirement: "Preserves fact: \(alternatives.joined(separator: " or "))",
                passed: alternatives.contains { folded.contains($0.lowercased()) }
            )
        }
        checks += forbiddenPhrases.map { .init(requirement: "Omits \($0)", passed: !folded.contains($0.lowercased())) }
        let hanCount = output.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let kanaCount = output.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) }.count
        switch expectedLanguage {
        case .english:
            checks.append(.init(requirement: "Uses English rather than untranslated Japanese or Chinese", passed: hanCount == 0 && kanaCount == 0 && output.range(of: "[A-Za-z]", options: .regularExpression) != nil))
        case .traditionalChinese:
            checks.append(.init(requirement: "Contains Chinese text", passed: hanCount >= 12 && kanaCount == 0))
        }
        if let maximumWords {
            checks.append(.init(requirement: "Uses at most \(maximumWords) words", passed: output.split(whereSeparator: \.isWhitespace).count <= maximumWords))
        }
        if let maximumSentences {
            let count = output.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            checks.append(.init(requirement: "Uses at most \(maximumSentences) sentence", passed: count <= maximumSentences))
        }
        return checks
    }
}

private struct WritingProviderCheck: Codable {
    let requirement: String
    let passed: Bool
}

private struct WritingProviderReceipt: Encodable {
    let fixture: WritingProviderFixture
    let provider: String
    let model: String
    let endpoint: String
    let ordinaryEnhancementEnabled: Bool
    let output: String?
    let checks: [WritingProviderCheck]
    let status: String
    let error: String?
    let boundary = "Synthetic text through the real writing-action provider service; no microphone, editor delivery, or physical shortcut proof."
}

private struct WritingProviderEnvironment {
    let apiKey: String
    let evidenceDirectory: URL

    static var isEnabled: Bool {
        value("GITHUB_ACTIONS") == "true"
            && value("RJT_WRITING_PROVIDER_CHECKS") == "1"
            && !(value("RJT_WRITING_PROVIDER_API_KEY") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() throws {
        guard Self.isEnabled,
              let apiKey = Self.value("RJT_WRITING_PROVIDER_API_KEY"),
              let path = Self.value("RJT_WRITING_PROVIDER_EVIDENCE"),
              path.hasPrefix("/") else {
            throw WritingProviderFailure(message: "Provider checks require disposable CI, explicit opt-in, an API key, and an absolute evidence directory.")
        }
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        evidenceDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
    }

    private static func value(_ key: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] ?? environment["TEST_RUNNER_\(key)"]
    }

    func redacted(_ text: String) -> String {
        text.replacingOccurrences(of: apiKey, with: "[redacted]")
    }

    func save(_ receipt: WritingProviderReceipt) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: evidenceDirectory.appendingPathComponent("\(receipt.fixture.id).json"), options: .atomic)
    }
}

private struct WritingProviderFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
