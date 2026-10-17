import Foundation
import SwiftUI
import AppKit
import RomaCore

struct EmailSupport {
    static func generateSupportEmailBody() -> String {
        let systemInfo = SystemInfoService.shared.getSystemInfoString()
        return RomaSupportContactPolicy.emailBody(systemInformation: systemInfo)
    }

    static func generateSupportEmailURL() -> URL? {
        RomaSupportContactPolicy.mailtoURL()
    }

    static func openSupportEmail() {
        let body = generateSupportEmailBody()

        if let sharingService = NSSharingService(named: .composeEmail) {
            sharingService.recipients = [RomaSupportContactPolicy.emailAddress]
            sharingService.subject = RomaSupportContactPolicy.emailSubject
            sharingService.perform(withItems: [body])
            return
        }

        SystemInfoService.shared.copySystemInfoToClipboard()

        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
}
