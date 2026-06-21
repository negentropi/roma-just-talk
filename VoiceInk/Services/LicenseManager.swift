import Foundation
import VoiceInkCore

/// Manages license data using secure Keychain storage (non-syncable, device-local).
final class LicenseManager {
    static let shared = LicenseManager()

    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - License Key

    var licenseKey: String? {
        get {
            keychain.getString(
                forKey: VoiceInkLicenseSecureStorageAccount.licenseKey.key,
                syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
            )
        }
        set {
            if let value = newValue {
                keychain.save(
                    value,
                    forKey: VoiceInkLicenseSecureStorageAccount.licenseKey.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            } else {
                keychain.delete(
                    forKey: VoiceInkLicenseSecureStorageAccount.licenseKey.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            }
        }
    }

    // MARK: - Trial Start Date

    var trialStartDate: Date? {
        get {
            VoiceInkLicenseSecureStoragePolicy.trialStartDate(
                from: keychain.getString(
                    forKey: VoiceInkLicenseSecureStorageAccount.trialStartDate.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            )
        }
        set {
            if let date = newValue {
                keychain.save(
                    VoiceInkLicenseSecureStoragePolicy.trialStartTimestamp(for: date),
                    forKey: VoiceInkLicenseSecureStorageAccount.trialStartDate.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            } else {
                keychain.delete(
                    forKey: VoiceInkLicenseSecureStorageAccount.trialStartDate.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            }
        }
    }

    // MARK: - Activation ID

    var activationId: String? {
        get {
            keychain.getString(
                forKey: VoiceInkLicenseSecureStorageAccount.activationId.key,
                syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
            )
        }
        set {
            if let value = newValue {
                keychain.save(
                    value,
                    forKey: VoiceInkLicenseSecureStorageAccount.activationId.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            } else {
                keychain.delete(
                    forKey: VoiceInkLicenseSecureStorageAccount.activationId.key,
                    syncable: VoiceInkLicenseSecureStoragePolicy.isSyncable
                )
            }
        }
    }

    /// Removes all license data (for license removal/reset).
    func removeAll() {
        licenseKey = nil
        trialStartDate = nil
        activationId = nil
    }
}
