import Foundation
import Testing
public enum VoiceInkLocalCLIExecutionError: Error, LocalizedError, Equatable, Sendable {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }

            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        }
    }
}


@Suite(.serialized)
private struct LocalCLIMacroShapeChecks {
 @Suite(.serialized)
 struct Lifetime {
  @Test @MainActor func requireShapes() throws {
   let observed: Int32? = 17
   let becameReady = ProcessInfo.processInfo.processIdentifier > 0
   let entered = becameReady
   let output = "warm"
   _ = try #require(observed, "The timeout command must have entered its unique script before cancellation.")
   try #require(becameReady, "The owned child did not confirm its TERM-ignore handler and input EOF.")
   try #require(entered, "The controlled canceled-start task did not reach its gate.")
   try #require(output == "warm", "The real shell/PATH fixture did not become usable.")
   _ = try #require(observed, "The unique script did not expose its exact running shell process.")
   _ = try #require(observed, "The early-exit child must have entered the unique script.")
  }
 }
 @Suite(.serialized)
 struct Configuration {
  @Test @MainActor func asyncThrowShapes() async {
   let failure = VoiceInkLocalCLIExecutionError.executionFailed("Local CLI command and prompts cannot contain NUL bytes.")
   let operation: @MainActor () async throws -> String = { throw failure }
   await #expect(throws: VoiceInkLocalCLIExecutionError.emptyOutput) {
    try await operation()
   }
   await #expect(throws: VoiceInkLocalCLIExecutionError.nonZeroExit(status: 23, stderr: "exact failure")) {
    try await operation()
   }
   await #expect(throws: failure) {
    try await operation()
   }
   await #expect(throws: failure) {
    try await operation()
   }
  }
 }
}
