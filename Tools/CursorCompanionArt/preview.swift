// Renders every style × pose through the production CursorCompanionView over time:
// arrive at 0.5 s, listening at 1.9 s, stalled/failed at 5 s.
import AppKit
import SwiftUI

public enum VoiceInkRecordingState: Equatable, Sendable { case idle, starting, recording, transcribing, enhancing, busy }

let assets = CommandLine.arguments[1]
let outputDirectory = CommandLine.arguments[2]
for dir in (try? FileManager.default.contentsOfDirectory(atPath: assets)) ?? [] where dir.hasPrefix("companion-") {
    let name = String(dir.dropLast(".imageset".count))
    if let image = NSImage(contentsOfFile: "\(assets)/\(dir)/\(name).png") { image.setName(name) }
}

struct Arrow: Shape {
    func path(in r: CGRect) -> Path {
        let p: [CGPoint] = [.init(x: 0, y: 0), .init(x: 0, y: 0.8), .init(x: 0.28, y: 0.62), .init(x: 0.5, y: 1), .init(x: 0.68, y: 0.93), .init(x: 0.47, y: 0.56), .init(x: 1, y: 0.56)]
        var path = Path(); path.addLines(p.map { CGPoint(x: $0.x * r.width, y: $0.y * r.height) }); path.closeSubpath(); return path
    }
}

struct Tile: View {
    let style: VoiceInkCursorCompanionStyle
    let pose: VoiceInkCursorCompanionPose
    let phase: VoiceInkCursorCompanionPhase
    static let target = CGPoint(x: 90, y: 110)
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.96)
            Text("The quick brown fox").font(.system(size: 15)).foregroundColor(.black).offset(x: 8, y: Tile.target.y - 9).opacity(pose == .hug ? 1 : 0)
            if pose == .hug {
                Rectangle().fill(Color.black).frame(width: 1.5, height: 18).offset(x: Tile.target.x - 0.75, y: Tile.target.y - 9)
            } else {
                Arrow().fill(Color.black).overlay(Arrow().stroke(Color.white, lineWidth: 1)).frame(width: 12, height: 19).offset(x: Tile.target.x, y: Tile.target.y)
            }
            let off = pose == .hug ? CGSize.zero : CursorCompanionArtwork.perchOffsetFromPointerTip
            CursorCompanionView(style: style, pose: pose, phase: phase)
                .frame(width: 200, height: 200)
                .position(x: Tile.target.x + off.width, y: Tile.target.y + off.height)
        }
        .frame(width: 180, height: 180).clipped()
    }
}

struct Board: View {
    @State var phase: VoiceInkCursorCompanionPhase = .hidden
    var body: some View {
        VStack(spacing: 6) {
            ForEach([VoiceInkCursorCompanionStyle.cartoon, .storybook, .anime], id: \.self) { style in
                HStack(spacing: 6) {
                    Tile(style: style, pose: .perch, phase: phase == .failed ? .hidden : phase)
                    Tile(style: style, pose: .hug, phase: phase == .failed ? .hidden : phase)
                    Tile(style: style, pose: .oops, phase: phase == .failed ? .failed : .hidden)
                }
            }
        }
        .padding(6).background(Color.gray)
        .onAppear {
            let steps: [(Double, VoiceInkCursorCompanionPhase)] = [(0.5, .arriving), (1.9, .listening), (5.0, .failed)]
            for (t, p) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t) { phase = p } }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 570, height: 570), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "companion-harness"
window.contentView = NSHostingView(rootView: Board())
window.orderFrontRegardless()

for t in [0.56, 0.62, 0.7, 0.8, 1.0, 1.5, 3.6, 5.1, 5.2, 5.35, 5.55, 7.5] {
    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
        let v = window.contentView!
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("frame-\(t)s.png"))
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
app.run()
