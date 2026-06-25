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
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkMacOSLogCategory.licenseViewModel)
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

        if plan.isLicensedState {
            activationsLimit = VoiceInkLicensePreference.activationsLimit(from: userDefaults)
        }
    }

    private func applyStartupPlan(_ plan: VoiceInkLicenseStartupPlan) {
        plan.applyRuntimeState(
            saveHasLaunchedBefore: { VoiceInkLicensePreference.saveHasLaunchedBefore($0, to: userDefaults) },
            saveTrialStartDate: { licenseManager.trialStartDate = $0 },
            setLicenseState: { licenseState = $0 },
            postLicenseStatusChanged: postLicenseStatusChanged
        )
    }

    var canUseApp: Bool {
        licenseState.canUseApp
    }

    func openPurchaseLink() {
        NSWorkspace.shared.open(VoiceInkLicenseLinks.purchaseURL)
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
        plan.applyRuntimeState(
            clearActivationId: { licenseManager.activationId = nil },
            saveActivationId: { licenseManager.activationId = $0 },
            saveRequiresActivation: { VoiceInkLicensePreference.saveRequiresActivation($0, to: userDefaults) },
            setActivationsLimit: { activationsLimit = $0 },
            saveActivationsLimit: { VoiceInkLicensePreference.saveActivationsLimit($0, to: userDefaults) },
            setLicenseState: { licenseState = $0 },
            applyFeedback: applyValidationFeedback,
            postLicenseStatusChanged: postLicenseStatusChanged
        )
    }

    private func applyValidationFeedback(_ feedback: VoiceInkLicenseValidationFeedback) {
        validationSuccess = feedback.isSuccess
        validationMessage = feedback.message
    }
    
    func removeLicense() {
        // Remove all license data from Keychain
        licenseManager.removeAll()
        let plan = VoiceInkLicenseRemovalPolicy.plan()

        plan.applyRuntimeState(
            saveRequiresActivation: { VoiceInkLicensePreference.saveRequiresActivation($0, to: userDefaults) },
            saveHasLaunchedBefore: { VoiceInkLicensePreference.saveHasLaunchedBefore($0, to: userDefaults) },
            saveActivationsLimit: { VoiceInkLicensePreference.saveActivationsLimit($0, to: userDefaults) },
            setLicenseState: { licenseState = $0 },
            clearLicenseKey: { licenseKey = "" },
            clearValidationMessage: { validationMessage = nil },
            setActivationsLimit: { activationsLimit = $0 },
            postLicenseStatusChanged: postLicenseStatusChanged,
            reloadStartupState: loadLicenseState
        )
    }

    private func postLicenseStatusChanged() {
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
}
