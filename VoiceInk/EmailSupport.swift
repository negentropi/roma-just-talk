import Foundation
import SwiftUI
import AppKit
import VoiceInkCore

struct EmailSupport {
    static func generateSupportEmailBody() -> String {
        let systemInfo = SystemInfoService.shared.getSystemInfoString()
        return VoiceInkSupportContactPolicy.emailBody(systemInformation: systemInfo)
    }

    static func generateSupportEmailURL() -> URL? {
        VoiceInkSupportContactPolicy.mailtoURL()
    }

    static func openSupportEmail() {
        let body = generateSupportEmailBody()

        if let sharingService = NSSharingService(named: .composeEmail) {
            sharingService.recipients = [VoiceInkSupportContactPolicy.emailAddress]
            sharingService.subject = VoiceInkSupportContactPolicy.emailSubject
            sharingService.perform(withItems: [body])
            return
        }

        SystemInfoService.shared.copySystemInfoToClipboard()

        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
}
