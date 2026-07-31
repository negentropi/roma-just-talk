import Foundation
import RuntimeE2ECore

struct RuntimeLatencyLogSnapshot: Codable {
    let rawMessages: [String]
    let traces: [RuntimeLatencyTrace]
}

enum RuntimeLatencyLogReader {
    static func recent(last: String = "2m") throws -> RuntimeLatencyLogSnapshot {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--last", last,
            "--style", "compact",
            "--predicate", "subsystem == \"com.negentropi.RomaJustTalk\" && category == \"LatencyTrace\""
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeLatencyLogReaderError.processFailed(process.terminationStatus)
        }
        let output = String(decoding: data, as: UTF8.self)
        let messages = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.contains("[LATENCY]") }
        return RuntimeLatencyLogSnapshot(
            rawMessages: messages,
            traces: RuntimeLatencyTrace.parseAll(messages: messages)
        )
    }
}

enum RuntimeLatencyLogReaderError: Error, CustomStringConvertible {
    case processFailed(Int32)

    var description: String {
        switch self {
        case .processFailed(let status):
            return "Unified log query failed with status \(status)"
        }
    }
}
