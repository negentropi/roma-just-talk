import Testing
struct Probe {
 enum Phase: String { case seed; case oldReopen = "old-reopen"; case currentRead = "current-read" }
 let phase: Phase
 static func value(_ key: String) -> String? { nil }
 init() throws {
        let phaseValue = try #require(Self.value("RJT_STORE_PHASE"))
        phase = try #require(Phase(rawValue: phaseValue))
 }
}
