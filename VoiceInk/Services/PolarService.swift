import Foundation
import IOKit
import os
import VoiceInkCore

class PolarService {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "PolarService")

    private func createRequest(operation: VoiceInkLicenseOperation, method: String = "POST") -> URLRequest {
        var request = URLRequest(url: VoiceInkLicenseServicePolicy.requestURL(for: operation))
        request.httpMethod = method
        request.setValue(
            VoiceInkLicenseServicePolicy.jsonContentType,
            forHTTPHeaderField: VoiceInkLicenseServicePolicy.contentTypeHeaderName
        )
        return request
    }
    
    private func getDeviceIdentifier() -> String {
        if let serialNumber = getMacSerialNumber() {
            return serialNumber
        }

        return VoiceInkLicensePreference.deviceIdentifier()
    }

    private func getMacSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        if platformExpert == 0 { return nil }

        defer { IOObjectRelease(platformExpert) }

        if let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        ) {
            return (serialNumber.takeRetainedValue() as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
    
    // Check if a license key requires activation
    func checkLicenseRequiresActivation(_ key: String) async throws -> (isValid: Bool, requiresActivation: Bool, activationsLimit: Int?) {
        var request = createRequest(operation: .validation)

        request.httpBody = try JSONSerialization.data(
            withJSONObject: VoiceInkLicenseServicePolicy.validationRequestBody(key: key)
        )

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = httpResponse as? HTTPURLResponse {
            if let error = VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: httpResponse.statusCode, operation: .validation) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License validation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                throw error
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let validationResponse = try JSONDecoder().decode(VoiceInkLicenseValidationResponse.self, from: data)

        return (
            isValid: validationResponse.isGranted,
            requiresActivation: validationResponse.requiresActivation,
            activationsLimit: validationResponse.limitActivations
        )
    }
    
    // Activate a license key on this device
    func activateLicenseKey(_ key: String) async throws -> (activationId: String, activationsLimit: Int) {
        var request = createRequest(operation: .activation)
        
        let deviceId = getDeviceIdentifier()
        let hostname = Host.current().localizedName ?? "Unknown Mac"
        
        let activationRequest = VoiceInkLicenseServicePolicy.activationRequestBody(
            key: key,
            label: hostname,
            deviceId: deviceId
        )
        
        request.httpBody = try JSONEncoder().encode(activationRequest)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            if let error = VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: httpResponse.statusCode, operation: .activation) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                throw error
            }
        }
        
        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let activationResult = try JSONDecoder().decode(VoiceInkLicenseActivationResult.self, from: data)
        
        return (activationId: activationResult.id, activationsLimit: activationResult.licenseKey.limitActivations ?? 0)
    }
    
    // Validate a license key with an activation ID
    func validateLicenseKeyWithActivation(_ key: String, activationId: String) async throws -> Bool {
        var request = createRequest(operation: .validation)
        
        request.httpBody = try JSONSerialization.data(
            withJSONObject: VoiceInkLicenseServicePolicy.validationRequestBody(
                key: key,
                activationId: activationId
            )
        )
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            if let error = VoiceInkLicenseServicePolicy.error(forHTTPStatusCode: httpResponse.statusCode, operation: .validation) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License validation with activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                throw error
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation with activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let validationResponse = try JSONDecoder().decode(VoiceInkLicenseValidationResponse.self, from: data)
        
        return validationResponse.isGranted
    }
}
