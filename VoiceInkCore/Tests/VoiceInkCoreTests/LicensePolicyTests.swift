import Foundation
@testable import VoiceInkCore

final class LicensePolicyTests: XCTestCase {
    func testLicensePreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkLicensePreference.requiresActivationKey, "VoiceInkLicenseRequiresActivation")
        XCTAssertEqual(VoiceInkLicensePreference.hasLaunchedBeforeKey, "VoiceInkHasLaunchedBefore")
        XCTAssertEqual(VoiceInkLicensePreference.activationsLimitKey, "VoiceInkActivationsLimit")
        XCTAssertEqual(VoiceInkLicensePreference.deviceIdentifierKey, "VoiceInkDeviceIdentifier")
    }

    func testLicensePreferenceStorageRoundTripsNonSensitiveFlags() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkLicensePreference.requiresActivation(from: defaults))
            XCTAssertFalse(VoiceInkLicensePreference.hasLaunchedBefore(from: defaults))
            XCTAssertEqual(VoiceInkLicensePreference.activationsLimit(from: defaults), 0)

            VoiceInkLicensePreference.saveRequiresActivation(true, to: defaults)
            VoiceInkLicensePreference.saveHasLaunchedBefore(true, to: defaults)
            VoiceInkLicensePreference.saveActivationsLimit(3, to: defaults)

            XCTAssertTrue(VoiceInkLicensePreference.requiresActivation(from: defaults))
            XCTAssertTrue(VoiceInkLicensePreference.hasLaunchedBefore(from: defaults))
            XCTAssertEqual(VoiceInkLicensePreference.activationsLimit(from: defaults), 3)
        }
    }

    func testDeviceIdentifierReusesStoredValueBeforeCreatingFallback() {
        withIsolatedDefaults { defaults in
            defaults.set("stored-device-id", forKey: VoiceInkLicensePreference.deviceIdentifierKey)

            let storedId = VoiceInkLicensePreference.deviceIdentifier(from: defaults) {
                XCTFail("should not create a fallback when a stored device identifier exists")
                return "new-device-id"
            }

            XCTAssertEqual(storedId, "stored-device-id")
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkLicensePreference.deviceIdentifierKey),
                Optional("stored-device-id")
            )
        }
    }

    func testDeviceIdentifierCreatesAndStoresFallbackWhenMissing() {
        withIsolatedDefaults { defaults in
            let createdId = VoiceInkLicensePreference.deviceIdentifier(from: defaults) {
                "created-device-id"
            }

            XCTAssertEqual(createdId, "created-device-id")
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkLicensePreference.deviceIdentifierKey),
                Optional("created-device-id")
            )
        }
    }

    func testStoredLicenseAccessPreservesExistingActivationRequirementPolicy() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: nil,
                activationId: "activation-id",
                from: defaults
            ))

            XCTAssertTrue(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: nil,
                from: defaults
            ))

            VoiceInkLicensePreference.saveRequiresActivation(true, to: defaults)

            XCTAssertFalse(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: nil,
                from: defaults
            ))
            XCTAssertTrue(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: "activation-id",
                from: defaults
            ))
        }
    }

    func testLicenseServicePolicyPreservesPolarEndpointsAndHeaders() {
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.organizationId,
            "6f3d781d-a630-4435-9dba-058486f2d936"
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.requestURL(for: .validation).absoluteString,
            "https://api.polar.sh/v1/customer-portal/license-keys/validate"
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.requestURL(for: .activation).absoluteString,
            "https://api.polar.sh/v1/customer-portal/license-keys/activate"
        )
        XCTAssertEqual(VoiceInkLicenseServicePolicy.contentTypeHeaderName, "Content-Type")
        XCTAssertEqual(VoiceInkLicenseServicePolicy.jsonContentType, "application/json")
    }

    func testLicenseValidationRequestBodiesPreservePolarFieldNames() {
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.validationRequestBody(key: "license-key"),
            [
                "key": "license-key",
                "organization_id": VoiceInkLicenseServicePolicy.organizationId
            ]
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.validationRequestBody(
                key: "license-key",
                activationId: "activation-id"
            ),
            [
                "key": "license-key",
                "organization_id": VoiceInkLicenseServicePolicy.organizationId,
                "activation_id": "activation-id"
            ]
        )
    }

    func testLicenseActivationRequestBodyEncodesPolarFieldNames() throws {
        let body = VoiceInkLicenseServicePolicy.activationRequestBody(
            key: "license-key",
            label: "Felix Mac",
            deviceId: "device-id"
        )
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["key"] as? String, Optional("license-key"))
        XCTAssertEqual(object["organization_id"] as? String, Optional(VoiceInkLicenseServicePolicy.organizationId))
        XCTAssertEqual(object["label"] as? String, Optional("Felix Mac"))
        XCTAssertEqual(
            (object["meta"] as? [String: String])?[VoiceInkLicenseServicePolicy.activationDeviceIdMetaKey],
            Optional("device-id")
        )
    }

    func testLicenseValidationResponseDecodingOwnsGrantedAndActivationPolicy() throws {
        let data = try XCTUnwrap("""
        {
          "status": "granted",
          "limit_activations": 2,
          "id": "license-id",
          "activation": { "id": "activation-id" }
        }
        """.data(using: .utf8))

        let response = try JSONDecoder().decode(VoiceInkLicenseValidationResponse.self, from: data)

        XCTAssertEqual(response.status, "granted")
        XCTAssertEqual(response.limitActivations, Optional(2))
        XCTAssertEqual(response.id, Optional("license-id"))
        XCTAssertEqual(response.activation?.id, Optional("activation-id"))
        XCTAssertTrue(response.isGranted)
        XCTAssertTrue(response.requiresActivation)
        XCTAssertFalse(VoiceInkLicenseServicePolicy.requiresActivation(limitActivations: nil))
        XCTAssertFalse(VoiceInkLicenseServicePolicy.requiresActivation(limitActivations: 0))
    }

    func testLicenseActivationResultDecodingPreservesPolarFieldNames() throws {
        let data = try XCTUnwrap("""
        {
          "id": "activation-id",
          "license_key": {
            "limit_activations": 3,
            "status": "granted"
          }
        }
        """.data(using: .utf8))

        let result = try JSONDecoder().decode(VoiceInkLicenseActivationResult.self, from: data)

        XCTAssertEqual(result.id, "activation-id")
        XCTAssertEqual(result.licenseKey.limitActivations, Optional(3))
        XCTAssertEqual(result.licenseKey.status, "granted")
    }

    func testLicenseHTTPStatusPolicyPreservesMacOSErrorMapping() {
        XCTAssertNil(VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 200, operation: .validation))
        XCTAssertNil(VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 299, operation: .activation))
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 404, operation: .validation),
            Optional(.keyNotFound)
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 403, operation: .activation),
            Optional(.activationLimitReached)
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 403, operation: .validation),
            Optional(.serverError(403))
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: 500, operation: .activation),
            Optional(.serverError(500))
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LicensePolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
