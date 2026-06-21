import Foundation
import AppKit
import os
import VoiceInkCore

@MainActor
class LicenseViewModel: ObservableObject {
    typealias LicenseState = VoiceInkLicenseState

    @Published private(set) var licenseState: LicenseState = .trial(
        daysRemaining: VoiceInkLicenseStartupPolicy.defaultTrialPeriodDays
    )
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 0

    private let polarService = PolarService()
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LicenseViewModel")
    private let userDefaults = UserDefaults.standard
    private let licenseManager = LicenseManager.shared

    init() {
        #if LOCAL_BUILD
        licenseState = .licensed
        #else
        loadLicenseState()
        #endif
    }

    func startTrial() {
        guard licenseManager.trialStartDate == nil else { return }

        let plan = VoiceInkLicenseStartupPolicy.plan(
            hasUsableStoredLicense: false,
            hasLaunchedBefore: true,
            trialStartDate: nil
        )
        applyStartupPlan(plan)
    }

    private func loadLicenseState() {
        let storedLicenseKey = licenseManager.licenseKey
        if let storedLicenseKey {
            self.licenseKey = storedLicenseKey
        }

        let hasUsableStoredLicense = VoiceInkLicensePreference.hasUsableStoredLicense(
            licenseKey: storedLicenseKey,
            activationId: licenseManager.activationId,
            from: userDefaults
        )
        let plan = VoiceInkLicenseStartupPolicy.plan(
            hasUsableStoredLicense: hasUsableStoredLicense,
            hasLaunchedBefore: VoiceInkLicensePreference.hasLaunchedBefore(from: userDefaults),
            trialStartDate: licenseManager.trialStartDate
        )

        applyStartupPlan(plan)

        if case .licensed = plan.state {
            activationsLimit = VoiceInkLicensePreference.activationsLimit(from: userDefaults)
        }
    }

    private func applyStartupPlan(_ plan: VoiceInkLicenseStartupPlan) {
        if plan.shouldSaveHasLaunchedBefore {
            VoiceInkLicensePreference.saveHasLaunchedBefore(true, to: userDefaults)
        }

        if let trialStartDate = plan.trialStartDateToSave {
            licenseManager.trialStartDate = trialStartDate
        }

        licenseState = plan.state

        if plan.shouldPostLicenseStatusChanged {
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }

    var canUseApp: Bool {
        licenseState.canUseApp
    }

    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
            return
        }
    }
    
    func validateLicense() async {
        guard !licenseKey.isEmpty else {
            applyValidationFeedback(VoiceInkLicenseValidationPolicy.emptyKeyFeedback)
            return
        }
        
        isValidating = true
        defer { isValidating = false }
        
        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(licenseKey)
            
            if !licenseCheck.isValid {
                applyValidationFeedback(VoiceInkLicenseValidationPolicy.disabledLicenseFeedback)
                return
            }
            
            // Store the license key
            licenseManager.licenseKey = licenseKey

            // Handle based on whether activation is required
            if licenseCheck.requiresActivation {
                // If we already have an activation ID, try to validate with it first
                if let existingActivationId = licenseManager.activationId {
                    let isValid = (try? await polarService.validateLicenseKeyWithActivation(licenseKey, activationId: existingActivationId)) ?? false
                    if isValid {
                        applyValidationPlan(VoiceInkLicenseValidationPolicy.existingActivationSuccessPlan())
                        return
                    }
                    // Activation is stale (deleted from portal) — clear it and create a new one
                    licenseManager.activationId = nil
                }

                // Need to create a new activation
                let (newActivationId, limit) = try await polarService.activateLicenseKey(licenseKey)

                // Store activation details
                applyValidationPlan(VoiceInkLicenseValidationPolicy.activatedLicenseSuccessPlan(
                    activationId: newActivationId,
                    activationsLimit: limit
                ))

            } else {
                // This license doesn't require activation (unlimited devices)
                applyValidationPlan(VoiceInkLicenseValidationPolicy.unlimitedLicenseSuccessPlan(
                    activationsLimit: licenseCheck.activationsLimit
                ))
                return
            }

        } catch let licenseError as VoiceInkLicenseError {
            applyValidationFeedback(VoiceInkLicenseValidationPolicy.failureFeedback(for: licenseError))
        } catch let urlError as URLError {
            logger.error("🔑 License network error: \(urlError.localizedDescription, privacy: .public)")
            applyValidationFeedback(VoiceInkLicenseValidationPolicy.networkFailureFeedback)
        } catch {
            logger.error("🔑 Unexpected license error: \(error, privacy: .public)")
            applyValidationFeedback(VoiceInkLicenseValidationPolicy.unexpectedFailureFeedback)
        }
    }

    private func applyValidationPlan(_ plan: VoiceInkLicenseValidationApplicationPlan) {
        if plan.shouldClearActivationId {
            licenseManager.activationId = nil
        }

        if let activationId = plan.activationIdToSave {
            licenseManager.activationId = activationId
        }

        if let requiresActivation = plan.requiresActivationToSave {
            VoiceInkLicensePreference.saveRequiresActivation(requiresActivation, to: userDefaults)
        }

        if let activationsLimit = plan.activationsLimitToSave {
            self.activationsLimit = activationsLimit
            VoiceInkLicensePreference.saveActivationsLimit(activationsLimit, to: userDefaults)
        }

        licenseState = plan.state
        applyValidationFeedback(plan.feedback)

        if plan.shouldPostLicenseStatusChanged {
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }

    private func applyValidationFeedback(_ feedback: VoiceInkLicenseValidationFeedback) {
        validationSuccess = feedback.isSuccess
        validationMessage = feedback.message
    }
    
    func removeLicense() {
        // Remove all license data from Keychain
        licenseManager.removeAll()

        // Reset UserDefaults flags
        VoiceInkLicensePreference.saveRequiresActivation(false, to: userDefaults)
        VoiceInkLicensePreference.saveHasLaunchedBefore(false, to: userDefaults)  // Allow trial to restart
        VoiceInkLicensePreference.saveActivationsLimit(0, to: userDefaults)

        licenseState = .trial(daysRemaining: VoiceInkLicenseStartupPolicy.defaultTrialPeriodDays)
        licenseKey = ""
        validationMessage = nil
        activationsLimit = 0
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        loadLicenseState()
    }
}
