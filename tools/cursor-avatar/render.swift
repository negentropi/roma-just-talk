import AppKit
import SwiftUI

@main
struct Render {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("usage: render asset-directory output-directory") }
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var loadedImages: [NSImage] = []
        for style in CursorAvatarStyle.allCases where style != .none {
            for pose in ["greeting", "listening", "working", "worried", "listening-blink"] {
                let name = "CursorAvatar-\(style.rawValue)-\(pose)"
                guard let image = NSImage(contentsOf: assets.appendingPathComponent("\(name).imageset/\(name).png")) else { fatalError("missing asset \(name)") }
                image.setName(name)
                loadedImages.append(image)
            }
        }
        let states: [CaptureFeedback] = [.starting, .listening, .working, .failed("Microphone stopped. Check your input.")]
        for reduced in [false, true] {
            let view = VStack(spacing: 16) {
                ForEach(CursorAvatarStyle.allCases) { style in
                    HStack(spacing: 20) {
                        Text(style.title).frame(width: 80)
                        ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                            CursorAvatarView(style: style, feedback: state, level: 0.5, reducedMotionOverride: reduced, animationDateOverride: Date(timeIntervalSinceReferenceDate: 20), listeningElapsedOverride: 2)
                        }
                    }
                }
            }.padding(24).background(Color(NSColor.windowBackgroundColor))

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { fatalError("render failed") }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(reduced ? "reduced-motion.png" : "all-states.png"))
        }
        let storyboard = VStack(spacing: 16) {
            ForEach(CursorAvatarStyle.allCases.filter { $0 != .none }) { style in
                HStack(spacing: 24) {
                    Text(style.title).frame(width: 80)
                    ForEach([0.0, 0.4, 2.0, 4.35], id: \.self) { elapsed in
                        VStack {
                            CursorAvatarView(style: style, feedback: .listening, level: 0.4,
                                             animationDateOverride: Date(timeIntervalSinceReferenceDate: 20 + elapsed),
                                             listeningElapsedOverride: elapsed)
                            Text("\(elapsed, specifier: "%.2f")s").font(.caption)
                        }
                    }
                }
            }
        }.padding(24).background(Color(NSColor.windowBackgroundColor))
        let animationRenderer = ImageRenderer(content: storyboard)
        animationRenderer.scale = 2
        guard let animationImage = animationRenderer.cgImage else { fatalError("animation render failed") }
        try NSBitmapImageRep(cgImage: animationImage).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("listening-animation.png"))
        withExtendedLifetime(loadedImages) {}
        print("Rendered production avatar views for all styles, states, and Reduced Motion")
    }
}
