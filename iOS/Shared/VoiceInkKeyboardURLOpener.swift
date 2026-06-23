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
        VoiceInkKeyboardOpenAppPolicy.initialAction(
            hasExtensionContext: extensionContext != nil
        ).applyRuntimeState(
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
                VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextUnavailable, privacy: .public)")
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
        VoiceInkKeyboardOpenAppPolicy.actionAfterExtensionContextOpen(
            succeeded: succeeded
        ).applyRuntimeState(
            openExtensionContext: {},
            openThroughApplicationOrResponderChain: {
                VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextOpenFailed, privacy: .public)")
                DispatchQueue.main.async {
                    openThroughApplicationOrResponderChain(
                        url: url,
                        responder: responder,
                        fallback: fallback
                    )
                }
            },
            finish: {
                VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.openedViaExtensionContext, privacy: .public)")
            },
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
        VoiceInkKeyboardOpenAppPolicy.actionAfterApplicationOpen(
            succeeded: succeeded
        ).applyRuntimeState(
            openExtensionContext: {},
            openThroughApplicationOrResponderChain: {},
            finish: {
                VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.openedViaApplication, privacy: .public)")
            },
            showFallback: {
                VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.applicationOpenFailed, privacy: .public)")
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

        VoiceInkKeyboardOpenAppPolicy.responderAction(
            hasResponder: nextResponder != nil
        ).applyRuntimeState(
            performResponderChainOpen: {
                if let nextResponder {
                    _ = nextResponder.perform(selector, with: url)
                    VoiceInkIOSLogger.keyboard.notice("\(VoiceInkKeyboardOpenAppDiagnostics.attemptedViaResponderChain, privacy: .public)")
                }
            },
            showFallback: {
                VoiceInkIOSLogger.keyboard.error("\(VoiceInkKeyboardOpenAppDiagnostics.allMethodsFailed, privacy: .public)")
                showFallback(fallback)
            }
        )
    }

    private static func showFallback(_ fallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            fallback()
        }
    }
}
