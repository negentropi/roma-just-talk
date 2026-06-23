import Foundation
@testable import VoiceInkCore

final class SystemArchitectureTests: XCTestCase {
    func testSystemArchitecturePreservesMacOSDisplayNameForCompileTarget() {
        #if arch(arm64)
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Apple Silicon (ARM64)")
        #elseif arch(x86_64)
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Intel (x86_64)")
        #else
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Unknown")
        #endif
    }

    func testSystemArchitectureIntelMacPredicateMatchesCompileTarget() {
        #if os(macOS) && arch(x86_64)
        XCTAssertTrue(VoiceInkSystemArchitecture.isIntelMac)
        #else
        XCTAssertFalse(VoiceInkSystemArchitecture.isIntelMac)
        #endif
    }
}
