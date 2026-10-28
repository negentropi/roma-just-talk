import AppKit
import SwiftUI
import VoiceInkCore

// MARK: - Presentation

/// Copy and identifiers for the one guarded Undo of the latest confirmed "Edit selected text" change.
/// The engine and its single controller own every target check; nothing here reads, copies or focuses editor text.
enum UndoLastWritingEditPresentation {
    static let title = VoiceInkShortcutActionPresentation.displayName(for: .undoLastWritingEdit)

    static let scope = "Puts back the text you selected before your latest confirmed Edit selected text change, while that field still shows the result. One step, plain text only, until you quit. Formatting may not come back. Translate, Draft and dictation aren't covered."

    static let availabilityHelp = "Go back to the edited field without changing its text, cursor or selection, then use the shortcut or the menu bar command. Undo won't switch apps or move focus."

    enum AccessibilityID {
        static let menuCommand = "undoLastWritingEdit.menuCommand"
        static let settingsRow = "undoLastWritingEdit.settings.row"
        static let shortcutRecorder = "undoLastWritingEdit.settings.shortcut"
        static let availability = "undoLastWritingEdit.settings.availability"
        static let notice = "undoLastWritingEdit.notice"
    }

    struct Notice: Equatable {
        let kind: VoiceInkAppNotificationKind
        let message: String

        var duration: TimeInterval {
            kind == .success ? VoiceInkAppNotificationKind.defaultDisplayDuration : 5
        }
    }

    static func notice(for outcome: WritingTarget.UndoOutcome) -> Notice {
        switch outcome {
        case .restored:
            return Notice(kind: .success, message: "Restored the original text and selection.")
        case .textRestoredSelectionUnconfirmed:
            return Notice(kind: .success, message: "Restored the original text. The original selection couldn't be confirmed.")
        case .unavailable:
            return Notice(kind: .info, message: "Nothing to undo. Only your latest Edit selected text change can be undone.")
        case .busy:
            return Notice(kind: .info, message: "RJT is busy right now, so Undo didn't replace any text.")
        case .notAttempted(let error):
            return Notice(kind: .warning, message: refusalMessage(for: error))
        case .attemptedUnconfirmed:
            // Text may have changed; never call this a failure or suggest repeating it.
            return Notice(kind: .warning, message: "Undo was sent, but the app didn't confirm the original text. Check the field before editing it again.")
        }
    }

    /// Every case here ended before any Undo text replacement. Forward-edit copy ("result is still available to copy") does not apply.
    private static func refusalMessage(for error: Error) -> String {
        if error is CancellationError {
            return "Undo stopped before replacing any text."
        }
        // Only this closed enum's fixed copy is shown; other error descriptions never reach the notice.
        if let pasteError = error as? CursorPaster.WritingPasteError, let detail = pasteError.errorDescription {
            return "Undo didn't replace any text. \(detail)"
        }
        switch error as? WritingTarget.Failure {
        case .targetChanged?:
            return "The edited field changed or isn't focused, so Undo didn't replace any text."
        case .accessibilityPermission?:
            return "Undo needs Accessibility access. No text was replaced."
        case .protectedField?:
            return "Undo doesn't edit protected fields. No text was replaced."
        case .clipboardChanged?:
            return "The clipboard was busy or changed, so Undo didn't replace any text. Check your clipboard."
        default:
            return "Undo couldn't edit this field. No text was replaced."
        }
    }
}

// MARK: - Shared command

/// The menu command and the global shortcut both call this, which calls the engine's single Undo entry.
@MainActor
enum UndoLastWritingEditCommand {
    static func perform(engine: VoiceInkEngine) async {
        let outcome = await engine.undoLastWritingEdit()
        UndoLastWritingEditNoticePresenter.shared.show(UndoLastWritingEditPresentation.notice(for: outcome))
    }
}

// MARK: - Menu bar command

/// Observes the controller directly: the engine does not forward its nested publisher.
struct UndoLastWritingEditMenuButton: View {
    @ObservedObject private var engine: VoiceInkEngine
    @ObservedObject private var controller: WritingActionUndoController

    init(engine: VoiceInkEngine) {
        self.engine = engine
        self.controller = engine.writingActionUndoController
    }

    var body: some View {
        Button(UndoLastWritingEditPresentation.title) {
            Task { @MainActor in
                await UndoLastWritingEditCommand.perform(engine: engine)
            }
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier(UndoLastWritingEditPresentation.AccessibilityID.menuCommand)
    }

    private var isEnabled: Bool {
        controller.isAvailable && !controller.isBusy && engine.canUndoLastWritingEdit
    }
}

// MARK: - Settings availability

/// Passive status beside the shortcut recorder. It never performs Undo.
struct UndoLastWritingEditAvailabilityLabel: View {
    @EnvironmentObject private var engine: VoiceInkEngine

    var body: some View {
        UndoLastWritingEditAvailabilityContent(engine: engine, controller: engine.writingActionUndoController)
    }
}

private struct UndoLastWritingEditAvailabilityContent: View {
    @ObservedObject var engine: VoiceInkEngine
    @ObservedObject var controller: WritingActionUndoController

    private enum Availability {
        case available, busy, empty
    }

    private var state: Availability {
        if controller.isBusy { return .busy }
        if !controller.isAvailable { return .empty }
        return engine.canUndoLastWritingEdit ? .available : .busy
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(state == .available ? Color.green : Color.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .help(UndoLastWritingEditPresentation.availabilityHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Undo Last Writing Edit: \(text)")
        .accessibilityIdentifier(UndoLastWritingEditPresentation.AccessibilityID.availability)
    }

    private var text: String {
        switch state {
        case .available: "Available"
        case .busy: "Busy"
        case .empty: "Nothing to undo"
        }
    }

    private var symbol: String {
        switch state {
        case .available: "arrow.uturn.backward.circle.fill"
        case .busy: "hourglass"
        case .empty: "minus.circle"
        }
    }
}

// MARK: - Passive notice

/// Shows Undo feedback without activating the app or taking key/main status from the edited field.
/// A dedicated panel is used because the shared notification path calls makeKeyAndOrderFront.
@MainActor
final class UndoLastWritingEditNoticePresenter {
    static let shared = UndoLastWritingEditNoticePresenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ notice: UndoLastWritingEditPresentation.Notice) {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let hostingView = NSHostingView(rootView: UndoLastWritingEditNoticeView(notice: notice))
        let size = hostingView.fittingSize
        let panel = PassiveNoticePanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hostingView
        position(panel)
        panel.alphaValue = 0
        // Ordering only; no key/main change and no app activation.
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: notice.message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )

        dismissTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: UInt64(notice.duration * 1_000_000_000))
            guard !Task.isCancelled, let self, let panel, self.panel === panel else { return }
            self.dismiss(panel)
        }
    }

    private func dismiss(_ panel: NSPanel) {
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 74)
        panel.setFrameOrigin(origin)
    }
}

private final class PassiveNoticePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Stays visible while another app is active and cannot be clicked into focus.
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct UndoLastWritingEditNoticeView: View {
    let notice: UndoLastWritingEditPresentation.Notice

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: notice.kind.systemImageName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 220, maxWidth: 460, minHeight: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.message)
        .accessibilityIdentifier(UndoLastWritingEditPresentation.AccessibilityID.notice)
    }

    private var tint: Color {
        switch notice.kind {
        case .success: .green
        case .warning: .yellow
        case .info: .blue
        case .error: .red
        }
    }
}
