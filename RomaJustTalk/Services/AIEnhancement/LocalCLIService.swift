import Foundation
import RomaCore

final class LocalCLIService {
    private static let shellPathQueue = DispatchQueue(label: "\(RomaAppIdentity.loggingSubsystem).localcli.path")
    private static var cachedInteractiveLoginPATH: String?

    var commandTemplate: String {
        didSet {
            RomaLocalCLIPreference.saveCommandTemplate(commandTemplate)
        }
    }

    var selectedTemplate: RomaLocalCLITemplate {
        didSet {
            RomaLocalCLIPreference.saveSelectedTemplate(selectedTemplate)
        }
    }

    var timeoutSeconds: Double {
        didSet {
            let clamped = RomaLocalCLIPreference.boundedTimeoutSeconds(timeoutSeconds)
            if clamped != timeoutSeconds {
                timeoutSeconds = clamped
                return
            }
            RomaLocalCLIPreference.saveTimeoutSeconds(timeoutSeconds)
        }
    }

    var isConfigured: Bool {
        RomaLocalCLIPreference.isCommandConfigured(commandTemplate)
    }

    init() {
        selectedTemplate = RomaLocalCLIPreference.selectedTemplate()
        commandTemplate = RomaLocalCLIPreference.commandTemplate()
        timeoutSeconds = RomaLocalCLIPreference.timeoutSeconds()
    }

    func loadTemplate(_ template: RomaLocalCLITemplate) {
        selectedTemplate = template
        commandTemplate = template.commandTemplate
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        guard isConfigured else {
            throw RomaLocalCLIExecutionError.commandNotConfigured
        }

        let fullPrompt = RomaLocalCLIPreference.fullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return try await executeCommand(
            commandTemplate: commandTemplate,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            fullPrompt: fullPrompt,
            timeout: timeoutSeconds
        )
    }

    private func executeCommand(
        commandTemplate: String,
        systemPrompt: String,
        userPrompt: String,
        fullPrompt: String,
        timeout: Double
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", commandTemplate]

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = Self.preferredPATH(fallback: environment["PATH"])
                environment["ROMA_SYSTEM_PROMPT"] = systemPrompt
                environment["ROMA_USER_PROMPT"] = userPrompt
                environment["ROMA_FULL_PROMPT"] = fullPrompt
                process.environment = environment

                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: RomaLocalCLIExecutionError.executionFailed(error.localizedDescription))
                    return
                }

                if let inputData = fullPrompt.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                }
                try? inputPipe.fileHandleForWriting.close()

                let semaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    if process.isRunning {
                        process.terminate()
                        _ = semaphore.wait(timeout: .now() + 2)
                    }
                    continuation.resume(throwing: RomaLocalCLIExecutionError.timeout(seconds: timeout))
                    return
                }

                let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = RomaLocalCLIPreference.cleanedOutput(String(data: stdoutData, encoding: .utf8) ?? "")
                let stderr = RomaLocalCLIPreference.cleanedOutput(String(data: stderrData, encoding: .utf8) ?? "")

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: RomaLocalCLIPreference.commandFailureError(
                        terminationStatus: Int(process.terminationStatus),
                        stderr: stderr,
                        commandTemplate: commandTemplate
                    ))
                    return
                }

                guard !stdout.isEmpty else {
                    continuation.resume(throwing: RomaLocalCLIExecutionError.emptyOutput)
                    return
                }

                continuation.resume(returning: stdout)
            }
        }
    }

    private static func preferredPATH(fallback: String?) -> String {
        shellPathQueue.sync {
            if let cachedInteractiveLoginPATH {
                return cachedInteractiveLoginPATH
            }

            if let discovered = discoverPATHFromInteractiveLoginShell() {
                cachedInteractiveLoginPATH = discovered
                return discovered
            }

            return fallback?.isEmpty == false ? fallback! : "/usr/bin:/bin:/usr/sbin:/sbin"
        }
    }

    private static func discoverPATHFromInteractiveLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-ilc",
            "echo __ROMA_PATH_START__; print -r -- $PATH; echo __ROMA_PATH_END__"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        let waitResult = semaphore.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let startMarker = "__ROMA_PATH_START__"
        let endMarker = "__ROMA_PATH_END__"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex)
        else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pathSection.isEmpty else {
            return nil
        }

        return pathSection
    }
}
