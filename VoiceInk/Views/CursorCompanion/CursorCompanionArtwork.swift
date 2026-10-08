import AppKit
import VoiceInkCore

struct CursorCompanionArtwork {
    let assetName: String
    /// Unit point in the image (origin top-left) that lands on the target point.
    let anchor: CGPoint
    let displayHeight: CGFloat
    /// Hole in the hug art, in unit image width, where the caret bar is drawn.
    let caretBar: CaretBar?

    struct CaretBar {
        let x: CGFloat
        let width: CGFloat
    }

    /// Where the perch anchor sits relative to the pointer tip, in screen points (x right, y down),
    /// so the mascot rides the arrow's back instead of covering the hotspot.
    static let perchOffsetFromPointerTip = CGSize(width: 6, height: 14)

    private struct Geometry {
        let anchor: CGPoint
        let caretBar: CaretBar?
    }

    private static let displayHeights: [VoiceInkCursorCompanionPose: CGFloat] = [
        .perch: 88,
        .hug: 80,
        .oops: 88
    ]

    // Measured from the processed assets by Tools/CursorCompanionArt/process.swift: perch anchor is the
    // seat, hug anchor sits on the hole left by the removed caret placeholder bar.
    private static let geometry: [VoiceInkCursorCompanionStyle: [VoiceInkCursorCompanionPose: Geometry]] = [
        .cartoon: [
            .perch: Geometry(anchor: CGPoint(x: 0.68, y: 0.78), caretBar: nil),
            .hug: Geometry(anchor: CGPoint(x: 0.783, y: 0.42), caretBar: CaretBar(x: 0.783, width: 0.144)),
            .oops: Geometry(anchor: CGPoint(x: 0.30, y: 0.97), caretBar: nil)
        ],
        .storybook: [
            .perch: Geometry(anchor: CGPoint(x: 0.66, y: 0.77), caretBar: nil),
            .hug: Geometry(anchor: CGPoint(x: 0.814, y: 0.42), caretBar: CaretBar(x: 0.814, width: 0.110)),
            .oops: Geometry(anchor: CGPoint(x: 0.30, y: 0.97), caretBar: nil)
        ],
        .anime: [
            .perch: Geometry(anchor: CGPoint(x: 0.66, y: 0.76), caretBar: nil),
            .hug: Geometry(anchor: CGPoint(x: 0.769, y: 0.42), caretBar: CaretBar(x: 0.769, width: 0.106)),
            .oops: Geometry(anchor: CGPoint(x: 0.30, y: 0.97), caretBar: nil)
        ]
    ]

    static func artwork(
        style: VoiceInkCursorCompanionStyle,
        pose: VoiceInkCursorCompanionPose
    ) -> CursorCompanionArtwork? {
        guard let geometry = geometry[style]?[pose],
              let displayHeight = displayHeights[pose] else {
            return nil
        }
        return CursorCompanionArtwork(
            assetName: "companion-\(style.rawValue)-\(pose.rawValue)",
            anchor: geometry.anchor,
            displayHeight: displayHeight,
            caretBar: geometry.caretBar
        )
    }

    /// Image and its rendered size, or nil when the asset is not in the bundle.
    var rendition: (image: NSImage, size: CGSize)? {
        guard let image = NSImage(named: assetName),
              image.size.height > 0 else {
            return nil
        }
        return (image, CGSize(
            width: displayHeight * image.size.width / image.size.height,
            height: displayHeight
        ))
    }
}
