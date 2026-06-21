import UIKit
import OSLog

enum VoiceInkKeyboardURLOpener {
    static func openMainApp(
        url: URL,
        extensionContext: NSExtensionContext?,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        guard let extensionContext else {
            VoiceInkIOSLogger.keyboard.error("extensionContext unavailable, trying alternative methods")
            openThroughApplicationOrResponderChain(
                url: url,
                responder: responder,
                fallback: fallback
            )
            return
        }

        extensionContext.open(url) { success in
            if success {
                VoiceInkIOSLogger.keyboard.notice("Opened main app via extensionContext")
            } else {
                VoiceInkIOSLogger.keyboard.error("extensionContext.open failed, trying alternative methods")
                DispatchQueue.main.async {
                    openThroughApplicationOrResponderChain(
                        url: url,
                        responder: responder,
                        fallback: fallback
                    )
                }
            }
        }
    }

    private static func openThroughApplicationOrResponderChain(
        url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        if let sharedApp = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication,
           sharedApp.canOpenURL(url) {
            sharedApp.open(url, options: [:]) { success in
                if success {
                    VoiceInkIOSLogger.keyboard.notice("Opened main app via UIApplication.open")
                } else {
                    VoiceInkIOSLogger.keyboard.error("UIApplication.open failed")
                    showFallback(fallback)
                }
            }
            return
        }

        openURLViaResponderChain(url, responder: responder, fallback: fallback)
    }

    private static func openURLViaResponderChain(
        _ url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        var nextResponder: UIResponder? = responder
        let selector = sel_registerName("openURL:")

        while let currentResponder = nextResponder, !currentResponder.responds(to: selector) {
            nextResponder = currentResponder.next
        }

        if let nextResponder {
            _ = nextResponder.perform(selector, with: url)
            VoiceInkIOSLogger.keyboard.notice("Attempted to open main app via responder chain")
        } else {
            VoiceInkIOSLogger.keyboard.error("All URL opening methods failed")
            showFallback(fallback)
        }
    }

    private static func showFallback(_ fallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            fallback()
        }
    }
}
