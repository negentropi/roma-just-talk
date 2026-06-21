import Foundation

public enum VoiceInkLicensePreference {
    public static let requiresActivationKey = "VoiceInkLicenseRequiresActivation"
    public static let hasLaunchedBeforeKey = "VoiceInkHasLaunchedBefore"
    public static let activationsLimitKey = "VoiceInkActivationsLimit"
    public static let deviceIdentifierKey = "VoiceInkDeviceIdentifier"

    public static func requiresActivation(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: requiresActivationKey)
    }

    public static func saveRequiresActivation(_ requiresActivation: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(requiresActivation, forKey: requiresActivationKey)
    }

    public static func hasLaunchedBefore(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hasLaunchedBeforeKey)
    }

    public static func saveHasLaunchedBefore(_ hasLaunchedBefore: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(hasLaunchedBefore, forKey: hasLaunchedBeforeKey)
    }

    public static func activationsLimit(from defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: activationsLimitKey)
    }

    public static func saveActivationsLimit(_ limit: Int, to defaults: UserDefaults = .standard) {
        defaults.set(limit, forKey: activationsLimitKey)
    }

    public static func deviceIdentifier(
        from defaults: UserDefaults = .standard,
        create: () -> String = { UUID().uuidString }
    ) -> String {
        if let storedId = defaults.string(forKey: deviceIdentifierKey) {
            return storedId
        }

        let newId = create()
        defaults.set(newId, forKey: deviceIdentifierKey)
        return newId
    }

    public static func hasUsableStoredLicense(
        licenseKey: String?,
        activationId: String?,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        guard licenseKey != nil else { return false }
        return activationId != nil || !requiresActivation(from: defaults)
    }
}

public enum VoiceInkLicenseState: Equatable, Sendable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed

    public var canUseApp: Bool {
        switch self {
        case .licensed, .trial:
            return true
        case .trialExpired:
            return false
        }
    }
}

public struct VoiceInkLicenseStartupPlan: Equatable, Sendable {
    public let state: VoiceInkLicenseState
    public let shouldSaveHasLaunchedBefore: Bool
    public let trialStartDateToSave: Date?
    public let shouldPostLicenseStatusChanged: Bool

    public init(
        state: VoiceInkLicenseState,
        shouldSaveHasLaunchedBefore: Bool,
        trialStartDateToSave: Date?,
        shouldPostLicenseStatusChanged: Bool
    ) {
        self.state = state
        self.shouldSaveHasLaunchedBefore = shouldSaveHasLaunchedBefore
        self.trialStartDateToSave = trialStartDateToSave
        self.shouldPostLicenseStatusChanged = shouldPostLicenseStatusChanged
    }
}

public enum VoiceInkLicenseStartupPolicy {
    public static let defaultTrialPeriodDays = 7

    public static func plan(
        hasUsableStoredLicense: Bool,
        hasLaunchedBefore: Bool,
        trialStartDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        trialPeriodDays: Int = defaultTrialPeriodDays
    ) -> VoiceInkLicenseStartupPlan {
        if hasUsableStoredLicense {
            return VoiceInkLicenseStartupPlan(
                state: .licensed,
                shouldSaveHasLaunchedBefore: false,
                trialStartDateToSave: nil,
                shouldPostLicenseStatusChanged: false
            )
        }

        if !hasLaunchedBefore {
            return VoiceInkLicenseStartupPlan(
                state: .trial(daysRemaining: trialPeriodDays),
                shouldSaveHasLaunchedBefore: true,
                trialStartDateToSave: trialStartDate == nil ? now : nil,
                shouldPostLicenseStatusChanged: trialStartDate == nil
            )
        }

        guard let trialStartDate else {
            return VoiceInkLicenseStartupPlan(
                state: .trial(daysRemaining: trialPeriodDays),
                shouldSaveHasLaunchedBefore: false,
                trialStartDateToSave: now,
                shouldPostLicenseStatusChanged: true
            )
        }

        let daysSinceTrialStart = calendar.dateComponents([.day], from: trialStartDate, to: now).day ?? 0
        if daysSinceTrialStart >= trialPeriodDays {
            return VoiceInkLicenseStartupPlan(
                state: .trialExpired,
                shouldSaveHasLaunchedBefore: false,
                trialStartDateToSave: nil,
                shouldPostLicenseStatusChanged: false
            )
        }

        return VoiceInkLicenseStartupPlan(
            state: .trial(daysRemaining: trialPeriodDays - daysSinceTrialStart),
            shouldSaveHasLaunchedBefore: false,
            trialStartDateToSave: nil,
            shouldPostLicenseStatusChanged: false
        )
    }
}

public enum VoiceInkLicenseSecureStorageAccount: String, CaseIterable, Sendable {
    case licenseKey = "voiceink.license.key"
    case trialStartDate = "voiceink.license.trialStartDate"
    case activationId = "voiceink.license.activationId"

    public var key: String {
        rawValue
    }
}

public enum VoiceInkLicenseSecureStoragePolicy {
    public static let isSyncable = false

    public static func trialStartTimestamp(for date: Date) -> String {
        String(date.timeIntervalSince1970)
    }

    public static func trialStartDate(from timestamp: String?) -> Date? {
        guard
            let timestamp,
            let timeInterval = Double(timestamp)
        else {
            return nil
        }

        return Date(timeIntervalSince1970: timeInterval)
    }
}

public enum VoiceInkLicenseOperation {
    case validation
    case activation
}

public enum VoiceInkLicenseError: Error, Equatable {
    case keyNotFound
    case activationLimitReached
    case serverError(Int)
}

public struct VoiceInkLicenseActivationResponse: Codable, Equatable {
    public let id: String
}

public struct VoiceInkLicenseValidationResponse: Codable, Equatable {
    public let status: String
    public let limitActivations: Int?
    public let id: String?
    public let activation: VoiceInkLicenseActivationResponse?

    public var isGranted: Bool {
        VoiceInkLicenseServicePolicy.isGrantedStatus(status)
    }

    public var requiresActivation: Bool {
        VoiceInkLicenseServicePolicy.requiresActivation(limitActivations: limitActivations)
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case limitActivations = "limit_activations"
        case id
        case activation
    }
}

public struct VoiceInkLicenseActivationRequestBody: Codable, Equatable {
    public let key: String
    public let organizationId: String
    public let label: String
    public let meta: [String: String]

    private enum CodingKeys: String, CodingKey {
        case key
        case organizationId = "organization_id"
        case label
        case meta
    }
}

public struct VoiceInkLicenseKeyInfo: Codable, Equatable {
    public let limitActivations: Int?
    public let status: String

    private enum CodingKeys: String, CodingKey {
        case limitActivations = "limit_activations"
        case status
    }
}

public struct VoiceInkLicenseActivationResult: Codable, Equatable {
    public let id: String
    public let licenseKey: VoiceInkLicenseKeyInfo

    private enum CodingKeys: String, CodingKey {
        case id
        case licenseKey = "license_key"
    }
}

public enum VoiceInkLicenseServicePolicy {
    public static let organizationId = "6f3d781d-a630-4435-9dba-058486f2d936"
    public static let apiBaseURLString = "https://api.polar.sh"
    public static let validationEndpoint = "/v1/customer-portal/license-keys/validate"
    public static let activationEndpoint = "/v1/customer-portal/license-keys/activate"
    public static let contentTypeHeaderName = "Content-Type"
    public static let jsonContentType = "application/json"
    public static let activationDeviceIdMetaKey = "device_id"

    public static func requestURL(for operation: VoiceInkLicenseOperation) -> URL {
        let endpoint: String
        switch operation {
        case .validation:
            endpoint = validationEndpoint
        case .activation:
            endpoint = activationEndpoint
        }

        return URL(string: apiBaseURLString + endpoint)!
    }

    public static func validationRequestBody(key: String, activationId: String? = nil) -> [String: String] {
        var body = [
            "key": key,
            "organization_id": organizationId
        ]

        if let activationId {
            body["activation_id"] = activationId
        }

        return body
    }

    public static func activationRequestBody(
        key: String,
        label: String,
        deviceId: String
    ) -> VoiceInkLicenseActivationRequestBody {
        VoiceInkLicenseActivationRequestBody(
            key: key,
            organizationId: organizationId,
            label: label,
            meta: [activationDeviceIdMetaKey: deviceId]
        )
    }

    public static func isGrantedStatus(_ status: String) -> Bool {
        status == "granted"
    }

    public static func requiresActivation(limitActivations: Int?) -> Bool {
        (limitActivations ?? 0) > 0
    }

    public static func error(
        forHTTPStatusCode statusCode: Int,
        operation: VoiceInkLicenseOperation
    ) -> VoiceInkLicenseError? {
        guard !(200...299).contains(statusCode) else { return nil }

        switch (operation, statusCode) {
        case (_, 404):
            return .keyNotFound
        case (.activation, 403):
            return .activationLimitReached
        default:
            return .serverError(statusCode)
        }
    }
}
