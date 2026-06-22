import UIKit
import OSLog
import VoiceInkCore

enum VoiceInkKeyboardURLOpener {
    static func openMainApp(
        url: URL,
        extensionContext: NSExtensionContext?,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        switch VoiceInkKeyboardOpenAppPolicy.initialAction(hasExtensionContext: extensionContext != nil) {
        case .openExtensionContext:
            extensionContext?.open(url) { success in
                applyExtensionContextOpenResult(
                    succeeded: success,
                    url: url,
                    responder: responder,
                    fallback: fallback
                )
            }

        case .openThroughApplicationOrResponderChain:
            VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextUnavailable, privacy: .public)")
            openThroughApplicationOrResponderChain(
                url: url,
                responder: responder,
                fallback: fallback
            )

        case .finish, .showFallback:
            break
        }
    }

    private static func applyExtensionContextOpenResult(
        succeeded: Bool,
        url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        switch VoiceInkKeyboardOpenAppPolicy.actionAfterExtensionContextOpen(succeeded: succeeded) {
        case .finish:
            VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.openedViaExtensionContext, privacy: .public)")

        case .openThroughApplicationOrResponderChain:
            VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextOpenFailed, privacy: .public)")
            DispatchQueue.main.async {
                openThroughApplicationOrResponderChain(
                    url: url,
                    responder: responder,
                    fallback: fallback
                )
            }

        case .openExtensionContext, .showFallback:
            break
        }
    }

    private static func openThroughApplicationOrResponderChain(
        url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        let sharedApp = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication
        switch VoiceInkKeyboardOpenAppPolicy.applicationAction(
            canOpenURL: sharedApp?.canOpenURL(url) == true
        ) {
        case .openViaApplication:
            sharedApp?.open(url, options: [:]) { success in
                applyApplicationOpenResult(succeeded: success, fallback: fallback)
            }

        case .openViaResponderChain:
            openURLViaResponderChain(url, responder: responder, fallback: fallback)
        }
    }

    private static func applyApplicationOpenResult(
        succeeded: Bool,
        fallback: @escaping () -> Void
    ) {
        switch VoiceInkKeyboardOpenAppPolicy.actionAfterApplicationOpen(succeeded: succeeded) {
        case .finish:
            VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.openedViaApplication, privacy: .public)")

        case .showFallback:
            VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.applicationOpenFailed, privacy: .public)")
            showFallback(fallback)

        case .openExtensionContext, .openThroughApplicationOrResponderChain:
            break
        }
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

        switch VoiceInkKeyboardOpenAppPolicy.responderAction(hasResponder: nextResponder != nil) {
        case .performResponderChainOpen:
            if let nextResponder {
                _ = nextResponder.perform(selector, with: url)
                VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.attemptedViaResponderChain, privacy: .public)")
            }

        case .showFallback:
            VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.allMethodsFailed, privacy: .public)")
            showFallback(fallback)
        }
    }

    private static func showFallback(_ fallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            fallback()
        }
    }
}
