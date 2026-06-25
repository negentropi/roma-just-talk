import Foundation
import Security
@testable import VoiceInkCore

final class KeychainQueryTests: XCTestCase {
    func testBaseQueryPreservesSharedAppServiceAndAccount() {
        let query = VoiceInkKeychainQuery.base(account: "groqAPIKey")

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, VoiceInkAppIdentity.bundleIdentifier)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "groqAPIKey")
        XCTAssertEqual(booleanValue(query[kSecUseDataProtectionKeychain as String]), true)
        XCTAssertEqual(booleanValue(query[kSecAttrSynchronizable as String]), true)
    }

    func testBaseQueryCanDisableSyncableForMacOSCallers() {
        let query = VoiceInkKeychainQuery.base(account: "provider", syncable: false)

        XCTAssertNil(query[kSecAttrSynchronizable as String])
    }

    func testAddQueryAddsValueData() {
        let data = Data("secret".utf8)
        let query = VoiceInkKeychainQuery.add(data: data, account: "provider")

        XCTAssertEqual(query[kSecValueData as String] as? Data, data)
    }

    func testCopyDataQueryRequestsOneDataResult() {
        let query = VoiceInkKeychainQuery.copyData(account: "provider")

        XCTAssertEqual(booleanValue(query[kSecReturnData as String]), true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }

    func testDeleteQueryUsesBaseLookupShape() {
        let query = VoiceInkKeychainQuery.delete(account: "provider", syncable: false)

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, VoiceInkAppIdentity.bundleIdentifier)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "provider")
        XCTAssertEqual(booleanValue(query[kSecUseDataProtectionKeychain as String]), true)
        XCTAssertNil(query[kSecAttrSynchronizable as String])
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecReturnData as String])
        XCTAssertNil(query[kSecMatchLimit as String])
    }

    func testExistsQuerySuppressesDataReturn() {
        let query = VoiceInkKeychainQuery.exists(account: "provider")

        XCTAssertEqual(booleanValue(query[kSecReturnData as String]), false)
    }

    func testLoadResultReportsSuccessStatus() {
        let data = Data("secret".utf8)

        XCTAssertTrue(VoiceInkKeychainLoadResult(status: errSecSuccess, data: data).isSuccess)
        XCTAssertFalse(VoiceInkKeychainLoadResult(status: errSecItemNotFound, data: nil).isSuccess)
    }

    func testStringLoadResultDecodesUTF8Values() {
        let data = Data("secret".utf8)
        let result = VoiceInkKeychainStringLoadResult(status: errSecSuccess, data: data)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.value, "secret")
    }

    func testStringLoadResultRejectsInvalidUTF8DataButKeepsStatus() {
        let result = VoiceInkKeychainStringLoadResult(status: errSecSuccess, data: Data([0xff]))

        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.value)
    }

    func testValueStoreStringEncodingAndDeleteStatusPolicy() {
        XCTAssertEqual(
            VoiceInkKeychainValueStore.data(forString: "secret"),
            Data("secret".utf8)
        )
        XCTAssertEqual(
            VoiceInkKeychainValueStore.string(from: Data("secret".utf8)),
            "secret"
        )
        XCTAssertNil(VoiceInkKeychainValueStore.string(from: nil))
        XCTAssertTrue(VoiceInkKeychainValueStore.isSuccessfulDeleteStatus(errSecSuccess))
        XCTAssertTrue(VoiceInkKeychainValueStore.isSuccessfulDeleteStatus(errSecItemNotFound))
        XCTAssertFalse(VoiceInkKeychainValueStore.isSuccessfulDeleteStatus(errSecAuthFailed))
    }

    func testKeychainDiagnosticsPreserveMacOSAdapterLogCopy() {
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.valueEncodingFailureMessage(key: "groqAPIKey"),
            "Failed to convert value to data for key: groqAPIKey"
        )
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.itemLoadFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to retrieve keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.itemDeleteSuccessMessage(key: "groqAPIKey"),
            "Successfully deleted keychain item for key: groqAPIKey"
        )
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.itemDeleteFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to delete keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.itemSaveSuccessMessage(key: "groqAPIKey"),
            "Successfully saved keychain item for key: groqAPIKey"
        )
        XCTAssertEqual(
            VoiceInkKeychainDiagnostics.itemSaveFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to save keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        value as? Bool
    }
}
