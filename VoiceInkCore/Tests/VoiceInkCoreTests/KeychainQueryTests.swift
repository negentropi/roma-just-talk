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

    private func booleanValue(_ value: Any?) -> Bool? {
        value as? Bool
    }
}
