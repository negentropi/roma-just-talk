import Foundation

public enum VoiceInkSubscriptionPlanID: String, CaseIterable, Codable, Sendable {
    case freemium
    case italy
    case roma
}

public struct VoiceInkSubscriptionPlan: Equatable, Sendable {
    public let id: VoiceInkSubscriptionPlanID
    public let name: String
    public let monthlyPriceUSD: Int?
    public let weeklyWordLimit: Int?
    public let features: [String]

    public init(
        id: VoiceInkSubscriptionPlanID,
        name: String,
        monthlyPriceUSD: Int?,
        weeklyWordLimit: Int?,
        features: [String]
    ) {
        self.id = id
        self.name = name
        self.monthlyPriceUSD = monthlyPriceUSD
        self.weeklyWordLimit = weeklyWordLimit
        self.features = features
    }

    public var hasUnlimitedAppUsage: Bool {
        weeklyWordLimit == nil
    }
}

public enum VoiceInkSubscriptionCatalog {
    public static let freemiumWeeklyWordLimit = 4_760

    public static let freemium = VoiceInkSubscriptionPlan(
        id: .freemium,
        name: "Freemium",
        monthlyPriceUSD: nil,
        weeklyWordLimit: freemiumWeeklyWordLimit,
        features: ["4,760 words per week"]
    )

    public static let italy = VoiceInkSubscriptionPlan(
        id: .italy,
        name: "Italy",
        monthlyPriceUSD: 8,
        weeklyWordLimit: nil,
        features: ["Unlimited app usage"]
    )

    public static let roma = VoiceInkSubscriptionPlan(
        id: .roma,
        name: "Roma",
        monthlyPriceUSD: 15,
        weeklyWordLimit: nil,
        features: [
            "Everything in Italy",
            "Best cloud inference",
            "Roma harness"
        ]
    )

    public static let plans = [freemium, italy, roma]
    public static let freemiumLearnMoreTitle = "Why 4,760 words?"
    public static let freemiumLearnMoreText = "476 CE is the traditional date used for the fall of the Western Roman Empire."

    public static func plan(id: VoiceInkSubscriptionPlanID) -> VoiceInkSubscriptionPlan {
        switch id {
        case .freemium:
            return freemium
        case .italy:
            return italy
        case .roma:
            return roma
        }
    }
}

public struct VoiceInkWeeklyWordAllowance: Equatable, Sendable {
    public let limit: Int?
    public let used: Int

    public init(plan: VoiceInkSubscriptionPlan, used: Int) {
        self.limit = plan.weeklyWordLimit
        self.used = max(0, used)
    }

    public var remaining: Int? {
        limit.map { max(0, $0 - used) }
    }

    public var canStartTranscription: Bool {
        remaining.map { $0 > 0 } ?? true
    }
}
