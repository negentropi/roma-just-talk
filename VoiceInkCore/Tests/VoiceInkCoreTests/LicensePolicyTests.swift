import Foundation
@testable import VoiceInkCore

final class LicensePolicyTests: XCTestCase {
    private enum LicenseStartupRuntimeEvent: Equatable {
        case saveHasLaunchedBefore(Bool)
        case saveTrialStartDate(Date)
        case setState(VoiceInkLicenseState)
        case postStatusChanged
    }

    private enum LicenseValidationRuntimeEvent: Equatable {
        case clearActivationId
        case saveActivationId(String)
        case saveRequiresActivation(Bool)
        case setActivationsLimit(Int)
        case saveActivationsLimit(Int)
        case setState(VoiceInkLicenseState)
        case applyFeedback(VoiceInkLicenseValidationFeedback)
        case postStatusChanged
    }

    private enum LicenseRemovalRuntimeEvent: Equatable {
        case saveRequiresActivation(Bool)
        case saveHasLaunchedBefore(Bool)
        case saveActivationsLimit(Int)
        case setState(VoiceInkLicenseState)
        case clearLicenseKey
        case clearValidationMessage
        case setActivationsLimit(Int)
        case postStatusChanged
        case reloadStartupState
    }

    func testLicensePreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkLicensePreference.requiresActivationKey, "VoiceInkLicenseRequiresActivation")
        XCTAssertEqual(VoiceInkLicensePreference.hasLaunchedBeforeKey, "VoiceInkHasLaunchedBefore")
        XCTAssertEqual(VoiceInkLicensePreference.activationsLimitKey, "VoiceInkActivationsLimit")
        XCTAssertEqual(VoiceInkLicensePreference.deviceIdentifierKey, "VoiceInkDeviceIdentifier")
    }

    func testLicenseStatusChangeRequestPreservesMacOSNotificationName() {
        XCTAssertEqual(VoiceInkLicenseStatusChangeRequest.notificationName, Notification.Name("licenseStatusChanged"))
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

    func testLicenseStartupPolicyPlansStoredLicenseAndTrialLifecycle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let trialStart = Date(timeIntervalSince1970: 1_700_000_000)
        let now = calendar.date(byAdding: .day, value: 3, to: trialStart)!
        let later = calendar.date(byAdding: .day, value: 7, to: trialStart)!

        XCTAssertEqual(
            licenseStartupEvents(for: VoiceInkLicenseStartupPolicy.plan(
                hasUsableStoredLicense: true,
                hasLaunchedBefore: true,
                trialStartDate: trialStart,
                now: now,
                calendar: calendar
            )),
            [.setState(.licensed)]
        )

        XCTAssertEqual(
            licenseStartupEvents(for: VoiceInkLicenseStartupPolicy.plan(
                hasUsableStoredLicense: false,
                hasLaunchedBefore: false,
                trialStartDate: nil,
                now: now,
                calendar: calendar
            )),
            [
                .saveHasLaunchedBefore(true),
                .saveTrialStartDate(now),
                .setState(.trial(daysRemaining: VoiceInkLicenseStartupPolicy.defaultTrialPeriodDays)),
                .postStatusChanged
            ]
        )

        XCTAssertEqual(
            licenseStartupEvents(for: VoiceInkLicenseStartupPolicy.plan(
                hasUsableStoredLicense: false,
                hasLaunchedBefore: true,
                trialStartDate: nil,
                now: now,
                calendar: calendar
            )),
            [
                .saveTrialStartDate(now),
                .setState(.trial(daysRemaining: VoiceInkLicenseStartupPolicy.defaultTrialPeriodDays)),
                .postStatusChanged
            ]
        )

        XCTAssertEqual(
            licenseStartupEvents(for: VoiceInkLicenseStartupPolicy.plan(
                hasUsableStoredLicense: false,
                hasLaunchedBefore: true,
                trialStartDate: trialStart,
                now: now,
                calendar: calendar
            )),
            [.setState(.trial(daysRemaining: 4))]
        )

        XCTAssertEqual(
            licenseStartupEvents(for: VoiceInkLicenseStartupPolicy.plan(
                hasUsableStoredLicense: false,
                hasLaunchedBefore: true,
                trialStartDate: trialStart,
                now: later,
                calendar: calendar
            )),
            [.setState(.trialExpired)]
        )
        XCTAssertTrue(VoiceInkLicenseState.trial(daysRemaining: 1).canUseApp)
        XCTAssertTrue(VoiceInkLicenseState.licensed.canUseApp)
        XCTAssertFalse(VoiceInkLicenseState.trialExpired.canUseApp)
    }

    func testLicenseValidationPolicyPreservesMacOSFeedbackMessages() {
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.emptyKeyFeedback,
            VoiceInkLicenseValidationFeedback(isSuccess: false, message: "Please enter a license key")
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.disabledLicenseFeedback,
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "This license has been revoked or disabled. Please contact support."
            )
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.failureFeedback(for: .keyNotFound),
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "License key not found. Please double-check your key and try again."
            )
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.failureFeedback(for: .activationLimitReached),
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "This license has reached its device limit. Visit the License Management Portal to deactivate other devices."
            )
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.failureFeedback(for: .serverError(503)),
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "Server error (503). Please try again later or contact support."
            )
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.networkFailureFeedback,
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "Could not reach the server. Please check your internet connection and try again."
            )
        )
        XCTAssertEqual(
            VoiceInkLicenseValidationPolicy.unexpectedFailureFeedback,
            VoiceInkLicenseValidationFeedback(
                isSuccess: false,
                message: "An unexpected error occurred. Please try again or contact support at support@tryvoiceink.com"
            )
        )
    }

    func testLicenseValidationApplicationPlansPreserveMacOSStorageWritesAndSuccessCopy() {
        XCTAssertEqual(
            licenseValidationEvents(for: VoiceInkLicenseValidationPolicy.existingActivationSuccessPlan()),
            [
                .setState(.licensed),
                .applyFeedback(VoiceInkLicenseValidationFeedback(
                    isSuccess: true,
                    message: "License activated successfully!"
                )),
                .postStatusChanged
            ]
        )

        XCTAssertEqual(
            licenseValidationEvents(for: VoiceInkLicenseValidationPolicy.activatedLicenseSuccessPlan(
                activationId: "activation-id",
                activationsLimit: 3
            )),
            [
                .saveActivationId("activation-id"),
                .saveRequiresActivation(true),
                .setActivationsLimit(3),
                .saveActivationsLimit(3),
                .setState(.licensed),
                .applyFeedback(VoiceInkLicenseValidationFeedback(
                    isSuccess: true,
                    message: "License activated successfully!"
                )),
                .postStatusChanged
            ]
        )

        XCTAssertEqual(
            licenseValidationEvents(for: VoiceInkLicenseValidationPolicy.unlimitedLicenseSuccessPlan(activationsLimit: nil)),
            [
                .clearActivationId,
                .saveRequiresActivation(false),
                .setActivationsLimit(0),
                .saveActivationsLimit(0),
                .setState(.licensed),
                .applyFeedback(VoiceInkLicenseValidationFeedback(
                    isSuccess: true,
                    message: "License validated successfully!"
                )),
                .postStatusChanged
            ]
        )
    }

    func testLicenseLinksPreservePurchaseAndManagementDestinations() {
        XCTAssertEqual(VoiceInkLicenseLinks.purchaseURLString, "https://tryvoiceink.com/buy")
        XCTAssertEqual(VoiceInkLicenseLinks.purchaseDisplayURLString, "tryvoiceink.com/buy")
        XCTAssertEqual(VoiceInkLicenseLinks.purchaseURL.absoluteString, "https://tryvoiceink.com/buy")
        XCTAssertEqual(
            VoiceInkLicenseLinks.managementPortalURLString,
            "https://polar.sh/beingpax/portal/request"
        )
        XCTAssertEqual(
            VoiceInkLicenseLinks.managementPortalURL.absoluteString,
            "https://polar.sh/beingpax/portal/request"
        )
    }

    func testLicenseManagementPresentationPreservesMacOSCopyAndResources() {
        XCTAssertEqual(VoiceInkLicenseManagementPresentation.appVersionFallback, "Unknown")
        XCTAssertEqual(VoiceInkLicenseManagementPresentation.heroSystemImageName, "checkmark.seal.fill")
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.heroTitle(for: .licensed),
            "VoiceInk Pro"
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.heroTitle(for: .trial(daysRemaining: 3)),
            "Upgrade to Pro"
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.heroSubtitle(for: .licensed),
            "Thank you for supporting VoiceInk"
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.heroSubtitle(for: .trialExpired),
            "Transcribe what you say to text instantly with AI"
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.appVersionText("1.2.3"),
            "v1.2.3"
        )

        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.licensedResourceLinks,
            [
                VoiceInkLicenseManagementResourceLink(
                    id: .changelog,
                    title: "Changelog",
                    systemImageName: "list.bullet.clipboard.fill",
                    urlString: "https://github.com/Beingpax/VoiceInk/releases"
                ),
                VoiceInkLicenseManagementResourceLink(
                    id: .discord,
                    title: "Discord",
                    systemImageName: "bubble.left.and.bubble.right.fill",
                    urlString: "https://discord.gg/xryDy57nYD"
                ),
                VoiceInkLicenseManagementResourceLink(
                    id: .emailSupport,
                    title: "Email Support",
                    systemImageName: "envelope.fill",
                    urlString: nil
                ),
                VoiceInkLicenseManagementResourceLink(
                    id: .docs,
                    title: "Docs",
                    systemImageName: "book.fill",
                    urlString: "https://tryvoiceink.com/docs"
                ),
                VoiceInkLicenseManagementResourceLink(
                    id: .tipJar,
                    title: "Tip Jar",
                    systemImageName: "heart.fill",
                    urlString: "https://buymeacoffee.com/beingpax"
                )
            ]
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.purchaseFeatures.map(\.title),
            ["Priority Support", "Lifetime Access", "Free Updates", "Multiple Devices"]
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.purchaseFeatures.map(\.systemImageName),
            [
                "bubble.left.and.bubble.right.fill",
                "infinity.circle.fill",
                "arrow.up.circle.fill",
                "macbook.and.iphone"
            ]
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.activeLicenseDeviceLimitText(activationsLimit: 3),
            "This license can be activated on up to 3 devices"
        )
        XCTAssertEqual(
            VoiceInkLicenseManagementPresentation.activeLicenseDeviceLimitText(activationsLimit: 0),
            "You can use VoiceInk Pro on all your personal devices"
        )
    }

    func testLicenseTrialBannerPresentationPreservesMacOSCopyAndThreshold() {
        XCTAssertEqual(VoiceInkLicenseTrialBannerPresentation.warningThresholdDaysRemaining, 2)
        XCTAssertEqual(VoiceInkLicenseTrialBannerPresentation.trialMessage(daysRemaining: 4), "You have 4 days left in your trial")

        XCTAssertEqual(
            VoiceInkLicenseTrialBannerPresentation.banner(for: .trial(daysRemaining: 4)),
            VoiceInkLicenseTrialBanner(
                tone: .info,
                title: "Trial Active",
                message: "You have 4 days left in your trial",
                systemImageName: "info.circle.fill",
                enterLicenseButtonTitle: "Enter License",
                purchaseButtonTitle: "Buy License"
            )
        )

        XCTAssertEqual(
            VoiceInkLicenseTrialBannerPresentation.banner(for: .trial(daysRemaining: 2)),
            VoiceInkLicenseTrialBanner(
                tone: .warning,
                title: "Trial Ending Soon",
                message: "You have 2 days left in your trial",
                systemImageName: "exclamationmark.triangle.fill",
                enterLicenseButtonTitle: "Enter License",
                purchaseButtonTitle: "Buy License"
            )
        )

        XCTAssertEqual(
            VoiceInkLicenseTrialBannerPresentation.banner(for: .trialExpired),
            VoiceInkLicenseTrialBanner(
                tone: .expired,
                title: "Trial Expired",
                message: "Your trial has expired. Upgrade to continue using VoiceInk",
                systemImageName: "xmark.circle.fill",
                enterLicenseButtonTitle: "Enter License",
                purchaseButtonTitle: "Buy License"
            )
        )

        XCTAssertNil(VoiceInkLicenseTrialBannerPresentation.banner(for: .licensed))
    }

    func testLicenseRemovalPolicyPreservesMacOSResetPlan() {
        XCTAssertEqual(
            licenseRemovalEvents(for: VoiceInkLicenseRemovalPolicy.plan()),
            [
                .saveRequiresActivation(false),
                .saveHasLaunchedBefore(false),
                .saveActivationsLimit(0),
                .setState(.trial(daysRemaining: VoiceInkLicenseStartupPolicy.defaultTrialPeriodDays)),
                .clearLicenseKey,
                .clearValidationMessage,
                .setActivationsLimit(0),
                .postStatusChanged,
                .reloadStartupState
            ]
        )
        XCTAssertEqual(
            licenseRemovalEvents(for: VoiceInkLicenseRemovalPolicy.plan(trialPeriodDays: 14)).contains(
                .setState(.trial(daysRemaining: 14))
            ),
            true
        )
    }

    func testLicenseSecureStoragePolicyPreservesDeviceLocalAccountsAndTrialDateCodec() {
        XCTAssertEqual(
            VoiceInkLicenseSecureStorageAccount.allCases.map(\.key),
            [
                "voiceink.license.key",
                "voiceink.license.trialStartDate",
                "voiceink.license.activationId"
            ]
        )
        XCTAssertFalse(VoiceInkLicenseSecureStoragePolicy.isSyncable)

        let trialStartDate = Date(timeIntervalSince1970: 1_700_000_000.25)
        let timestamp = VoiceInkLicenseSecureStoragePolicy.trialStartTimestamp(for: trialStartDate)

        XCTAssertEqual(timestamp, "1700000000.25")
        XCTAssertEqual(
            VoiceInkLicenseSecureStoragePolicy.trialStartDate(from: timestamp),
            trialStartDate
        )
        XCTAssertNil(VoiceInkLicenseSecureStoragePolicy.trialStartDate(from: nil))
        XCTAssertNil(VoiceInkLicenseSecureStoragePolicy.trialStartDate(from: "not-a-timestamp"))
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

    func testLicenseServicePolicyPreservesPolarResponseTextFallbacks() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: VoiceInkLicenseServicePolicy.requestURL(for: .validation),
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        ))

        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.errorResponseText(data: Data("denied".utf8)),
            "denied"
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.errorResponseText(data: Data([0xff])),
            VoiceInkLicenseServicePolicy.unknownErrorResponseText
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.successResponseText(data: Data("ok".utf8)),
            "ok"
        )
        XCTAssertEqual(
            VoiceInkLicenseServicePolicy.successResponseText(data: Data([0xff])),
            VoiceInkLicenseServicePolicy.undecodableSuccessResponseText
        )
        XCTAssertEqual(VoiceInkLicenseServicePolicy.httpStatusCode(from: response), 204)
    }

    private func licenseStartupEvents(
        for plan: VoiceInkLicenseStartupPlan
    ) -> [LicenseStartupRuntimeEvent] {
        var events: [LicenseStartupRuntimeEvent] = []

        plan.applyRuntimeState(
            saveHasLaunchedBefore: { events.append(.saveHasLaunchedBefore($0)) },
            saveTrialStartDate: { events.append(.saveTrialStartDate($0)) },
            setLicenseState: { events.append(.setState($0)) },
            postLicenseStatusChanged: { events.append(.postStatusChanged) }
        )

        return events
    }

    private func licenseValidationEvents(
        for plan: VoiceInkLicenseValidationApplicationPlan
    ) -> [LicenseValidationRuntimeEvent] {
        var events: [LicenseValidationRuntimeEvent] = []

        plan.applyRuntimeState(
            clearActivationId: { events.append(.clearActivationId) },
            saveActivationId: { events.append(.saveActivationId($0)) },
            saveRequiresActivation: { events.append(.saveRequiresActivation($0)) },
            setActivationsLimit: { events.append(.setActivationsLimit($0)) },
            saveActivationsLimit: { events.append(.saveActivationsLimit($0)) },
            setLicenseState: { events.append(.setState($0)) },
            applyFeedback: { events.append(.applyFeedback($0)) },
            postLicenseStatusChanged: { events.append(.postStatusChanged) }
        )

        return events
    }

    private func licenseRemovalEvents(
        for plan: VoiceInkLicenseRemovalPlan
    ) -> [LicenseRemovalRuntimeEvent] {
        var events: [LicenseRemovalRuntimeEvent] = []

        plan.applyRuntimeState(
            saveRequiresActivation: { events.append(.saveRequiresActivation($0)) },
            saveHasLaunchedBefore: { events.append(.saveHasLaunchedBefore($0)) },
            saveActivationsLimit: { events.append(.saveActivationsLimit($0)) },
            setLicenseState: { events.append(.setState($0)) },
            clearLicenseKey: { events.append(.clearLicenseKey) },
            clearValidationMessage: { events.append(.clearValidationMessage) },
            setActivationsLimit: { events.append(.setActivationsLimit($0)) },
            postLicenseStatusChanged: { events.append(.postStatusChanged) },
            reloadStartupState: { events.append(.reloadStartupState) }
        )

        return events
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LicensePolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
