import Foundation
import Testing
@testable import VoiceInk

struct ElevenLabsAPIKeyErrorTests {
    @Test func explainsKeyIDRejectionWithoutDisplayingResponseMetadata() {
        let response = #"{"detail":{"type":"authentication_error","code":"invalid_api_key","message":"API key ID used as API key - only valid API keys can be used.","status":"api_key_id_used_as_api_key","api_key":"fixture-key-id","param":"api_key","docs_url":"https://elevenlabs.io/docs/api-reference/authentication"}}"#
        let message = ElevenLabsAPIKeyError.message(from: response)

        #expect(message.contains("key ID"))
        #expect(message.contains("sk_"))
        #expect(message.contains("create or rotate"))
        #expect(!message.contains("fixture-key-id"))
        #expect(!message.contains("{"))
    }

    @Test func extractsProviderMessageForOtherFailures() {
        let response = #"{"detail":{"status":"missing_permissions","message":"The API key you used is missing the permission user_read to execute this operation.","api_key":"fixture-key-id"}}"#
        #expect(ElevenLabsAPIKeyError.message(from: response) == "The API key you used is missing the permission user_read to execute this operation.")
    }

    @Test func supportsStringDetails() {
        #expect(ElevenLabsAPIKeyError.message(from: #"{"detail":"Service unavailable"}"#) == "Service unavailable")
    }

    @Test func preservesNetworkErrors() {
        #expect(ElevenLabsAPIKeyError.message(from: "The request timed out.") == "The request timed out.")
    }

    @Test func usesReadableFallbackForMissingOrMalformedDetails() {
        for response in [nil, "", "  ", "{broken JSON", #"{"detail":{"status":"unknown","api_key":"fixture-key-id"}}"#, #"{"detail":[]}"#] as [String?] {
            let message = ElevenLabsAPIKeyError.message(from: response)
            #expect(message == "ElevenLabs could not verify this API key. Try again.")
        }
    }
}
