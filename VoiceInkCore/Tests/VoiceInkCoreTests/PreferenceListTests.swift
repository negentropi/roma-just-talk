import Foundation
@testable import VoiceInkCore

final class PreferenceListTests: XCTestCase {
    func testRemovingAtOffsetsPreservesRemainingOrder() {
        XCTAssertEqual(
            VoiceInkPreferenceList.removing(at: IndexSet([1, 3]), from: ["zero", "one", "two", "three"]),
            ["zero", "two"]
        )
    }

    func testRemovingAtOffsetsIgnoresOutOfRangeIndexes() {
        XCTAssertEqual(
            VoiceInkPreferenceList.removing(at: IndexSet([1, 9]), from: ["zero", "one", "two"]),
            ["zero", "two"]
        )
    }
}
