import Foundation

enum ElevenLabsAPIKeyError {
    static func message(from response: String?) -> String {
        let fallback = "ElevenLabs could not verify this API key. Try again."
        guard let response = response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else { return fallback }

        guard let object = try? JSONSerialization.jsonObject(with: Data(response.utf8)) else {
            // Keep transport errors readable, but never show a broken JSON response.
            return response.hasPrefix("{") || response.hasPrefix("[") ? fallback : response
        }
        guard let payload = object as? [String: Any] else { return fallback }
        if let detail = payload["detail"] as? [String: Any] {
            if detail["status"] as? String == "api_key_id_used_as_api_key" {
                return "This is an ElevenLabs key ID. Open ElevenLabs API keys, create or rotate a key, and copy the secret API key starting with sk_."
            }
            return nonemptyMessage(detail["message"]) ?? fallback
        }
        return nonemptyMessage(payload["detail"]) ?? fallback
    }

    private static func nonemptyMessage(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let message = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}
