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
        VoiceInkKeyboardOpenAppPolicy.initialActionPlan(
            hasExtensionContext: extensionContext != nil
        ).applyRuntimeState(
            logNotice: logNotice,
            logError: logError,
            openExtensionContext: {
                extensionContext?.open(url) { success in
                    applyExtensionContextOpenResult(
                        succeeded: success,
                        url: url,
                        responder: responder,
                        fallback: fallback
                    )
                }
            },
            openThroughApplicationOrResponderChain: {
                openThroughApplicationOrResponderChain(
                    url: url,
                    responder: responder,
                    fallback: fallback
                )
            },
            finish: {},
            showFallback: {}
        )
    }

    private static func applyExtensionContextOpenResult(
        succeeded: Bool,
        url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        VoiceInkKeyboardOpenAppPolicy.actionPlanAfterExtensionContextOpen(
            succeeded: succeeded
        ).applyRuntimeState(
            logNotice: logNotice,
            logError: logError,
            openExtensionContext: {},
            openThroughApplicationOrResponderChain: {
                DispatchQueue.main.async {
                    openThroughApplicationOrResponderChain(
                        url: url,
                        responder: responder,
                        fallback: fallback
                    )
                }
            },
            finish: {},
            showFallback: {}
        )
    }

    private static func openThroughApplicationOrResponderChain(
        url: URL,
        responder: UIResponder,
        fallback: @escaping () -> Void
    ) {
        let sharedApp = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication
        VoiceInkKeyboardOpenAppPolicy.applicationAction(
            canOpenURL: sharedApp?.canOpenURL(url) == true
        ).applyRuntimeState(
            openViaApplication: {
                sharedApp?.open(url, options: [:]) { success in
                    applyApplicationOpenResult(succeeded: success, fallback: fallback)
                }
            },
            openViaResponderChain: {
                openURLViaResponderChain(url, responder: responder, fallback: fallback)
            }
        )
    }

    private static func applyApplicationOpenResult(
        succeeded: Bool,
        fallback: @escaping () -> Void
    ) {
        VoiceInkKeyboardOpenAppPolicy.actionPlanAfterApplicationOpen(
            succeeded: succeeded
        ).applyRuntimeState(
            logNotice: logNotice,
            logError: logError,
            openExtensionContext: {},
            openThroughApplicationOrResponderChain: {},
            finish: {},
            showFallback: {
                showFallback(fallback)
            }
        )
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

        VoiceInkKeyboardOpenAppPolicy.responderActionPlan(
            hasResponder: nextResponder != nil
        ).applyRuntimeState(
            logNotice: logNotice,
            logError: logError,
            performResponderChainOpen: {
                if let nextResponder {
                    _ = nextResponder.perform(selector, with: url)
                }
            },
            showFallback: {
                showFallback(fallback)
            }
        )
    }

    private static func showFallback(_ fallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            fallback()
        }
    }

    private static func logNotice(_ message: String) {
        VoiceInkIOSLogger.keyboard.notice("\(message, privacy: .public)")
    }

    private static func logError(_ message: String) {
        VoiceInkIOSLogger.keyboard.error("\(message, privacy: .public)")
    }
}
