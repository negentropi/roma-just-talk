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
            validationSuccess = false
            validationMessage = "Please enter a license key"
            return
        }
        
        isValidating = true
        
        do {
            // First, check if the license is valid and if it requires activation
            let licenseCheck = try await polarService.checkLicenseRequiresActivation(licenseKey)
            
            if !licenseCheck.isValid {
                validationSuccess = false
                validationMessage = "This license has been revoked or disabled. Please contact support."
                isValidating = false
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
                        licenseState = .licensed
                        validationSuccess = true
                        validationMessage = "License activated successfully!"
                        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
                        isValidating = false
                        return
                    }
                    // Activation is stale (deleted from portal) — clear it and create a new one
                    licenseManager.activationId = nil
                }

                // Need to create a new activation
                let (newActivationId, limit) = try await polarService.activateLicenseKey(licenseKey)

                // Store activation details
                licenseManager.activationId = newActivationId
                VoiceInkLicensePreference.saveRequiresActivation(true, to: userDefaults)
                self.activationsLimit = limit
                VoiceInkLicensePreference.saveActivationsLimit(limit, to: userDefaults)

            } else {
                // This license doesn't require activation (unlimited devices)
                licenseManager.activationId = nil
                VoiceInkLicensePreference.saveRequiresActivation(false, to: userDefaults)
                self.activationsLimit = licenseCheck.activationsLimit ?? 0
                VoiceInkLicensePreference.saveActivationsLimit(licenseCheck.activationsLimit ?? 0, to: userDefaults)

                // Update the license state for unlimited license
                licenseState = .licensed
                validationSuccess = true
                validationMessage = "License validated successfully!"
                NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
                isValidating = false
                return
            }
            
            // Update the license state for activated license
            licenseState = .licensed
            validationSuccess = true
            validationMessage = "License activated successfully!"
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)

        } catch VoiceInkLicenseError.keyNotFound {
            validationSuccess = false
            validationMessage = "License key not found. Please double-check your key and try again."
        } catch VoiceInkLicenseError.activationLimitReached {
            validationSuccess = false
            validationMessage = "This license has reached its device limit. Visit the License Management Portal to deactivate other devices."
        } catch VoiceInkLicenseError.serverError(let code) {
            validationSuccess = false
            validationMessage = "Server error (\(code)). Please try again later or contact support."
        } catch let urlError as URLError {
            validationSuccess = false
            logger.error("🔑 License network error: \(urlError.localizedDescription, privacy: .public)")
            validationMessage = "Could not reach the server. Please check your internet connection and try again."
        } catch {
            validationSuccess = false
            logger.error("🔑 Unexpected license error: \(error, privacy: .public)")
            validationMessage = "An unexpected error occurred. Please try again or contact support at support@tryvoiceink.com"
        }
        
        isValidating = false
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
