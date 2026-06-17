import Foundation
import VoiceInkCore

class PromptDetectionService {
    struct PromptDetectionResult {
        let shouldEnableAI: Bool
        let selectedPromptId: UUID?
        let processedText: String
        let detectedTriggerWord: String?
        let originalEnhancementState: Bool
        let originalPromptId: UUID?
    }
    
    @MainActor
    func analyzeText(_ text: String, with enhancementService: AIEnhancementService) -> PromptDetectionResult {
        let originalEnhancementState = enhancementService.isEnhancementEnabled
        let originalPromptId = enhancementService.selectedPromptId
        let triggers = enhancementService.promptDetectionPrompts.map {
            VoiceInkPromptTrigger(promptId: $0.id, triggerWords: $0.triggerWords)
        }

        if let match = VoiceInkPromptTriggerPolicy.detect(in: text, triggers: triggers) {
            return PromptDetectionResult(
                shouldEnableAI: true,
                selectedPromptId: match.promptId,
                processedText: match.processedText,
                detectedTriggerWord: match.triggerWord,
                originalEnhancementState: originalEnhancementState,
                originalPromptId: originalPromptId
            )
        }

        return PromptDetectionResult(
            shouldEnableAI: false,
            selectedPromptId: nil,
            processedText: text,
            detectedTriggerWord: nil,
            originalEnhancementState: originalEnhancementState,
            originalPromptId: originalPromptId
        )
    }
    
    func applyDetectionResult(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        await MainActor.run {
            if result.shouldEnableAI {
                if !enhancementService.isEnhancementEnabled {
                    enhancementService.isEnhancementEnabled = true
                }
                if let promptId = result.selectedPromptId {
                    enhancementService.selectedPromptId = promptId
                }
            }
        }
    }
    
    func restoreOriginalSettings(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        if result.shouldEnableAI {
            await MainActor.run {
                if enhancementService.isEnhancementEnabled != result.originalEnhancementState {
                    enhancementService.isEnhancementEnabled = result.originalEnhancementState
                }
                if let originalId = result.originalPromptId, enhancementService.selectedPromptId != originalId {
                    enhancementService.selectedPromptId = originalId
                }
            }
        }
    }
}
