import Foundation
import Security
@testable import VoiceInkCore

final class ProviderAPIKeyStorageTests: XCTestCase {
    func testAccountUsesSharedProviderAccessRequirement() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyStorage.account(for: .groq),
            VoiceInkProviderAPIKeyAccount.groq
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyStorage.account(for: .elevenLabs),
            VoiceInkProviderAPIKeyAccount.elevenLabs
        )
        XCTAssertNil(VoiceInkProviderAPIKeyStorage.account(for: .localWhisper))
        XCTAssertNil(VoiceInkProviderAPIKeyStorage.account(for: .voiceInk))
    }

    func testStoredKeyLoadsThroughProviderAccountAndDefaultsToEmpty() {
        var requestedAccounts: [String] = []
        let storedKey = VoiceInkProviderAPIKeyStorage.storedKey(for: .elevenLabs) { account in
            requestedAccounts.append(account)
            return "$ELEVENLABS_API_KEY"
        }

        XCTAssertEqual(storedKey, "$ELEVENLABS_API_KEY")
        XCTAssertEqual(requestedAccounts, [VoiceInkProviderAPIKeyAccount.elevenLabs])

        let missingKey = VoiceInkProviderAPIKeyStorage.storedKey(for: .groq) { _ in nil }
        XCTAssertEqual(missingKey, "")
    }

    func testStoredKeySkipsProvidersWithoutUserKeyAccounts() {
        var didLoad = false
        let storedKey = VoiceInkProviderAPIKeyStorage.storedKey(for: .localWhisper) { _ in
            didLoad = true
            return "should-not-load"
        }

        XCTAssertEqual(storedKey, "")
        XCTAssertFalse(didLoad)
    }

    func testSaveStoredKeyTargetsProviderAccountAndReportsFailureStatus() {
        var savedValues: [(key: String, account: String)] = []
        let success = VoiceInkProviderAPIKeyStorage.saveStoredKey("secret", for: .groq) { key, account in
            savedValues.append((key, account))
            return errSecSuccess
        }

        XCTAssertEqual(savedValues.count, 1)
        XCTAssertEqual(savedValues.first?.key, "secret")
        XCTAssertEqual(savedValues.first?.account, VoiceInkProviderAPIKeyAccount.groq)
        XCTAssertEqual(success.account, VoiceInkProviderAPIKeyAccount.groq)
        XCTAssertEqual(success.status, errSecSuccess)
        XCTAssertFalse(success.shouldReportFailure)

        let failure = VoiceInkProviderAPIKeyStorage.saveStoredKey("secret", for: .groq) { _, _ in
            errSecAuthFailed
        }
        XCTAssertTrue(failure.shouldReportFailure)
    }

    func testSaveAndDeleteSkipProvidersWithoutUserKeyAccounts() {
        var didSave = false
        let saveResult = VoiceInkProviderAPIKeyStorage.saveStoredKey("secret", for: .voiceInk) { _, _ in
            didSave = true
            return errSecSuccess
        }
        XCTAssertNil(saveResult.account)
        XCTAssertNil(saveResult.status)
        XCTAssertFalse(didSave)

        var didDelete = false
        let deleteResult = VoiceInkProviderAPIKeyStorage.deleteStoredKey(for: .localWhisper) { _ in
            didDelete = true
            return errSecSuccess
        }
        XCTAssertNil(deleteResult.account)
        XCTAssertNil(deleteResult.status)
        XCTAssertFalse(didDelete)
    }

    func testProviderAPIKeyStorageDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyStorageDiagnostics.saveFailureMessage(status: errSecAuthFailed),
            "Error saving API key to keychain: \(errSecAuthFailed)"
        )
    }
}
