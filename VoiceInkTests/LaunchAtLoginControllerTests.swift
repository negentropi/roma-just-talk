import Testing
@testable import VoiceInk

struct LaunchAtLoginControllerTests {
    @Test @MainActor
    func cachesStatusInsteadOfReadingItDuringViewUpdates() {
        var readCount = 0
        var writes: [Bool] = []
        let controller = LaunchAtLoginController(
            readEnabled: {
                readCount += 1
                return true
            },
            writeEnabled: { writes.append($0) }
        )

        #expect(controller.isEnabled)
        #expect(controller.isEnabled)
        #expect(readCount == 1)

        controller.isEnabled = false
        controller.isEnabled = false

        #expect(writes == [false])
        #expect(readCount == 1)
    }
}
