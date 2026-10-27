import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct ClarityProviderTests {
        @Test @MainActor func clarityPreservesLiteralProviderJSONAndCodeUnits() async throws {
            try await withClarityProviderFixture { fixture in
                let literal = " \t<think>literal think</think>\n<thinking>literal thinking</thinking>\n<reasoning>literal reasoning</reasoning>\ne\u{0301} て\u{3099}\n{\"codex_follow_up\":true,\"text\":\"literal content\"}\n "
                let command = try fixture.command("literal", output: fixture.envelope(literal))
                let service = try fixture.service(command: command.template)
                let request = try VoiceInkClarityRequest(transcript: "Keep the literal text.", style: .natural)
                let result = try await service.performClarity(request: request, using: service.providerSnapshot())

                #expect(result.text.utf8.elementsEqual(literal.utf8))
                #expect(result.text.utf16.elementsEqual(literal.utf16))
                #expect(VoiceInkAIEnhancementRequestPayload.enhancedText(from: literal) == "e\u{0301} て\u{3099}")
                #expect(try Data(contentsOf: command.inputURL).elementsEqual(fixture.fullPrompt(request).utf8))
            }
        }

        @Test @MainActor func claritySameOutputRetainsCapturedRequestMetadata() async throws {
            try await withClarityProviderFixture { fixture in
                let transcript = "Same e\u{0301} text, RJT-482."
                let command = try fixture.command("same-output", output: fixture.envelope(transcript), held: true)
                let service = try fixture.service(command: command.template, timeout: 10)
                let request = try VoiceInkClarityRequest(transcript: transcript, style: .casual)
                let snapshot = try service.providerSnapshot()
                let work = fixture.request { try await service.performClarity(request: request, using: snapshot) }
                try await fixture.waitForReady(command)

                let other = try fixture.command("other-request", output: "Other request completed.")
                fixture.configure(command: other.template)
                let otherRequest = try VoiceInkWritingActionRequest(kind: .draft, transcript: "Write another message.")
                let otherResult = try await service.performWritingAction(otherRequest, using: service.providerSnapshot())
                #expect(otherResult.text == "Other request completed.")
                #expect(service.lastSystemMessageSent == otherRequest.systemMessage)
                #expect(service.lastUserMessageSent == otherRequest.userMessage)

                try fixture.release(command)
                let result = try await work.value
                #expect(result.text.utf8.elementsEqual(transcript.utf8))
                #expect(result.text.utf16.elementsEqual(transcript.utf16))
                #expect(result.modelName == "local-cli")
                #expect(result.promptName == nil)
                #expect(result.duration >= 0)
                #expect(result.requestSystemMessage?.utf8.elementsEqual(request.systemMessage.utf8) == true)
                #expect(result.requestUserMessage?.utf8.elementsEqual(request.userMessage.utf8) == true)
                #expect(try Data(contentsOf: command.inputURL).elementsEqual(fixture.fullPrompt(request).utf8))
            }
        }

        @Test @MainActor func clarityRejectsMalformedAndBlankProviderResponses() async throws {
            try await withClarityProviderFixture { fixture in
                let request = try VoiceInkClarityRequest(transcript: "Nonblank input.", style: .formal)
                let cases: [(String, VoiceInkClarityError)] = [
                    ("plain text", .invalidResponse),
                    ("", .invalidResponse),
                    ("{\"text\":\" \\n\\t\"}", .emptyOutput),
                    ("{\"text\":\"ok\",\"extra\":true}", .invalidResponse)
                ]
                for (index, item) in cases.enumerated() {
                    let command = try fixture.command("invalid-\(index)", output: item.0)
                    let service = try fixture.service(command: command.template)
                    let snapshot = try service.providerSnapshot()
                    await #expect(throws: item.1) {
                        try await service.performClarity(request: request, using: snapshot)
                    }
                }
            }
        }

        @Test @MainActor func claritySnapshotKeepsCapturedCLICommandAndProvider() async throws {
            try await withClarityProviderFixture { fixture in
                let captured = try fixture.command("captured", output: fixture.envelope("Captured route."))
                let originalService = try fixture.service(command: captured.template)
                let snapshot = try originalService.providerSnapshot()
                let changed = try fixture.command("changed", output: fixture.envelope("Changed route."))
                fixture.configure(command: changed.template, timeout: 30)
                fixture.defaults.set(VoiceInkLocalCLITemplate.codex.rawValue, forKey: VoiceInkLocalCLIPreference.selectedTemplateKey)
                let laterService = try fixture.service(command: changed.template, timeout: 30, provider: .ollama)
                #expect(laterService.getAIService().selectedProvider == .ollama)
                let request = try VoiceInkClarityRequest(transcript: "Keep this request.", style: .natural)

                let heldResult = try await laterService.performClarity(request: request, using: snapshot)
                #expect(heldResult.text == "Captured route.")
                #expect(heldResult.modelName == "local-cli")
                #expect(!FileManager.default.fileExists(atPath: changed.inputURL.path))
                #expect(try Data(contentsOf: captured.inputURL).elementsEqual(fixture.fullPrompt(request).utf8))

                let freshService = try fixture.service(command: changed.template, timeout: 30)
                let freshResult = try await freshService.performClarity(request: request, using: freshService.providerSnapshot())
                #expect(freshResult.text == "Changed route.")
            }
        }

        @Test @MainActor func claritySnapshotKeepsCapturedCLITimeout() async throws {
            try await withClarityProviderFixture { fixture in
                try await fixture.warmPATH()
                let command = try fixture.command("captured-timeout", body: "exec /bin/sleep 10")
                let service = try fixture.service(command: command.template, timeout: 5)
                let snapshot = try service.providerSnapshot()
                fixture.configure(command: command.template, timeout: 30)
                let request = try VoiceInkClarityRequest(transcript: "Wait for the configured timeout.", style: .natural)
                let started = ProcessInfo.processInfo.systemUptime

                await #expect(throws: VoiceInkAIEnhancementError.customError("Local CLI command timed out after 5 seconds.")) {
                    try await service.performClarity(request: request, using: snapshot)
                }
                #expect(ProcessInfo.processInfo.systemUptime - started < 8)
                #expect(FileManager.default.fileExists(atPath: command.readyURL.path))
            }
        }

        @Test @MainActor func writingActionsRetainLegacyFilteringAndEmptyPolicies() async throws {
            try await withClarityProviderFixture { fixture in
                let raw = " \n<think>hidden think</think><thinking>hidden thinking</thinking><reasoning>hidden reasoning</reasoning>kept e\u{0301}\n{\"codex_follow_up\":true,\"text\":\"discarded\"}\n "
                let command = try fixture.command("legacy-filter", output: raw)
                let service = try fixture.service(command: command.template)
                let request = try VoiceInkWritingActionRequest(kind: .draft, transcript: "Draft the supplied message.")
                let result = try await service.performWritingAction(request, using: service.providerSnapshot())
                #expect(result.text.utf8.elementsEqual("kept e\u{0301}".utf8))
                #expect(result.promptName == request.promptName)

                let empty = try fixture.command("legacy-empty", output: " \n\t ")
                fixture.configure(command: empty.template)
                let emptySnapshot = try service.providerSnapshot()
                await #expect(throws: VoiceInkAIEnhancementError.customError("Local CLI command returned empty output.")) {
                    try await service.performWritingAction(request, using: emptySnapshot)
                }

                let filteredEmpty = try fixture.command("legacy-filtered-empty", output: "<think>hidden</think>")
                fixture.configure(command: filteredEmpty.template)
                let filteredSnapshot = try service.providerSnapshot()
                await #expect(throws: VoiceInkWritingActionError.emptyOutput) {
                    try await service.performWritingAction(request, using: filteredSnapshot)
                }
            }
        }

        @Test @MainActor func clarityCancellationDoesNotReturnLateOutput() async throws {
            try await withClarityProviderFixture { fixture in
                let command = try fixture.command("canceled", output: fixture.envelope("Late output."), held: true)
                let service = try fixture.service(command: command.template, timeout: 10)
                let request = try VoiceInkClarityRequest(transcript: "Cancel this request.", style: .natural)
                let snapshot = try service.providerSnapshot()
                let work = fixture.request { try await service.performClarity(request: request, using: snapshot) }
                try await fixture.waitForReady(command)
                work.cancel()
                try fixture.release(command)

                switch await work.result {
                case .failure(let error): #expect(error is CancellationError)
                case .success: Issue.record("Canceled Clarity must not publish a successful late result.")
                }
            }
        }
    }
}

@MainActor
private func withClarityProviderFixture(_ operation: (ClarityProviderFixture) async throws -> Void) async throws {
    let fixture = try ClarityProviderFixture()
    do {
        try await operation(fixture)
        await fixture.close()
    } catch {
        await fixture.close()
        throw error
    }
}

@MainActor
private final class ClarityProviderFixture {
    struct Command {
        let template: String
        let inputURL: URL
        let readyURL: URL
        let releaseURL: URL?
    }

    let defaults = UserDefaults.standard
    private let directory: URL
    private let saved: [String: Any]
    private var commands: [Command] = []
    private var requests: [Task<VoiceInkAIEnhancementResult, Error>] = []
    private static let keys = [
        VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled,
        VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId,
        VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout,
        VoiceInkUserDefaultsKey.ollamaBaseURL,
        VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.selectedTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey
    ]

    init() throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Clarity-Provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func configure(command: String, timeout: Double = 5) {
        defaults.set(command, forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(timeout, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
    }

    func service(
        command: String,
        timeout: Double = 5,
        provider: VoiceInkAIEnhancementProviderKind = .localCLI
    ) throws -> AIEnhancementService {
        configure(command: command, timeout: timeout)
        defaults.set(provider.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        if provider == .ollama {
            defaults.set("http://[", forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
        }
        let schema = Schema([VocabularyWord.self])
        let configuration = ModelConfiguration(
            "RJT-Clarity-Provider-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let aiService = AIService()
        try #require(aiService.selectedProvider == provider)
        try #require(aiService.isAPIKeyValid)
        return AIEnhancementService(aiService: aiService, modelContext: ModelContext(container))
    }

    func warmPATH() async throws {
        let output = try await LocalCLIService.execute(
            systemPrompt: "system", userPrompt: "user",
            configuration: .init(commandTemplate: "/bin/cat >/dev/null; printf '%s' path-ready", timeoutSeconds: 5)
        )
        try #require(output == "path-ready")
    }

    func envelope(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["text": text], options: [.sortedKeys]), as: UTF8.self)
    }

    func fullPrompt(_ request: VoiceInkClarityRequest) -> String {
        "<SYSTEM_PROMPT>\n" + request.systemMessage + "\n</SYSTEM_PROMPT>\n\n<USER_PROMPT>\n" + request.userMessage + "\n</USER_PROMPT>"
    }

    func command(_ name: String, output: String, held: Bool = false) throws -> Command {
        let outputURL = directory.appendingPathComponent(name + ".output")
        try Data(output.utf8).write(to: outputURL)
        return try command(name, body: "/bin/cat " + quote(outputURL.path), held: held)
    }

    func command(_ name: String, body: String, held: Bool = false) throws -> Command {
        let scriptURL = directory.appendingPathComponent(name + ".sh")
        let inputURL = directory.appendingPathComponent(name + ".stdin")
        let readyURL = directory.appendingPathComponent(name + ".ready")
        let releaseURL = held ? directory.appendingPathComponent(name + ".release") : nil
        var script = "#!/bin/sh\n/bin/cat > " + quote(inputURL.path) + "\n: > " + quote(readyURL.path) + "\n"
        if let releaseURL {
            script += "count=0\nwhile [ ! -f " + quote(releaseURL.path) + " ] && [ \"$count\" -lt 500 ]; do\n/bin/sleep 0.01\ncount=$((count + 1))\ndone\n"
        }
        script += body + "\n"
        try Data(script.utf8).write(to: scriptURL)
        let command = Command(template: "exec /bin/sh " + quote(scriptURL.path), inputURL: inputURL, readyURL: readyURL, releaseURL: releaseURL)
        commands.append(command)
        return command
    }

    func request(_ operation: @escaping @MainActor () async throws -> VoiceInkAIEnhancementResult) -> Task<VoiceInkAIEnhancementResult, Error> {
        let work = Task { try await operation() }
        requests.append(work)
        return work
    }

    func waitForReady(_ command: Command) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while !FileManager.default.fileExists(atPath: command.readyURL.path), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try #require(FileManager.default.fileExists(atPath: command.readyURL.path), "The finite Local CLI fixture did not receive its request.")
    }

    func release(_ command: Command) throws {
        if let releaseURL = command.releaseURL { try Data().write(to: releaseURL) }
    }

    func close() async {
        for work in requests { work.cancel() }
        for command in commands { try? release(command) }
        for work in requests { _ = await work.result }
        requests.removeAll()
        for key in Self.keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove the owned Clarity fixture directory: \(error)") }
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
