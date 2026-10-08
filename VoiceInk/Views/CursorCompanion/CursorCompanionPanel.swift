import SwiftUI
import AppKit

class CursorCompanionPanel: NSPanel {
    // Larger than the art so the glow and pulse ring never clip.
    static let contentSize = CGSize(width: 200, height: 200)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(controller: CursorCompanionController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: CursorCompanionPanelContent(controller: controller))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.contentSize)
        contentView = hostingView
    }
}

private struct CursorCompanionPanelContent: View {
    @ObservedObject var controller: CursorCompanionController

    var body: some View {
        CursorCompanionView(style: controller.style, pose: controller.pose, phase: controller.phase)
            .frame(width: CursorCompanionPanel.contentSize.width, height: CursorCompanionPanel.contentSize.height)
    }
}
