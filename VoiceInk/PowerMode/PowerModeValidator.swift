import Foundation
import SwiftUI
import VoiceInkCore

typealias PowerModeValidationError = VoiceInkPowerModeValidationError

struct PowerModeValidator {
    private let powerModeManager: PowerModeManager
    
    init(powerModeManager: PowerModeManager) {
        self.powerModeManager = powerModeManager
    }
    
    func validateForSave(config: PowerModeConfig, mode: ConfigurationMode) -> [PowerModeValidationError] {
        VoiceInkPowerModePolicy.validateForSave(
            candidate: config.powerModePolicyRule,
            mode: mode.powerModeSaveMode,
            existing: powerModeManager.configurations.powerModePolicyRules
        )
    }
}

private extension ConfigurationMode {
    var powerModeSaveMode: VoiceInkPowerModeSaveMode {
        switch self {
        case .add:
            return .add
        case .edit(let config):
            return .edit(config.id)
        }
    }
}

extension View {
    func powerModeValidationAlert(
        errors: [PowerModeValidationError],
        isPresented: Binding<Bool>
    ) -> some View {
        self.alert(
            "Cannot Save Power Mode", 
            isPresented: isPresented,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                if let firstError = errors.first {
                    Text(firstError.localizedDescription)
                } else {
                    Text("Please fix the validation errors before saving.")
                }
            }
        )
    }
}
