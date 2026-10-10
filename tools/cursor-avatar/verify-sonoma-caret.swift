import AppKit
import ApplicationServices

@main
struct VerifySonomaCaret {
    static func main() {
        // Captured from TextEdit on Sonoma 14.8.9 through the running app's AX connection.
        let unavailable = CGRect(x: 0, y: 800, width: 0, height: 0)
        let first = CGRect(x: 123, y: 142, width: 9.333984, height: 14)
        let final = CGRect(x: 322.447266, y: 170, width: 3.333984, height: 14)
        for (location, expected) in [(0, CGRect(x: 123, y: 142, width: 0, height: 14)),
                                     (75, CGRect(x: 325.78125, y: 170, width: 0, height: 14))] {
            let result = CursorAvatarPlacement.caretBounds(at: location, characterCount: 75, read: { range in
                if range.length == 0 { return unavailable }
                if range.location == 0 { return first }
                if range.location == 1 { return CGRect(x: 132.333984, y: 142, width: 6.673828, height: 14) }
                if range.location == 73 { return CGRect(x: 315.773438, y: 170, width: 6.673828, height: 14) }
                if range.location == 74 { return final }
                return nil
            })
            assert(result == expected, "Sonoma zero-height caret must stay at the drawn insertion point at \(location): \(String(describing: result))")
        }
        #if !ZERO_CARET_BASELINE
        let blank = CGRect(x: 123, y: 156, width: 576, height: 14)
        let trailing = CursorAvatarPlacement.caretBounds(at: 39, characterCount: 39, read: { range in
            range.length == 0 ? unavailable : range.location == 38 ? blank : nil
        }, precedingLineBreak: { true }, previousLineStart: { blank })
        assert(trailing == CGRect(x: 123, y: 170, width: 0, height: 14), "a trailing newline keeps the companion on the new empty line")
        let between = CursorAvatarPlacement.caretBounds(at: 38, characterCount: 75, read: { range in
            range.length == 0 ? unavailable : range.location == 38 ? blank : nil
        }, previousLineStart: { CGRect(x: 123, y: 142, width: 0, height: 14) })
        assert(between == CGRect(x: 123, y: 156, width: 0, height: 14), "an existing blank line uses its newline glyph geometry")
        let rtlGlyphs = [CGRect(x: 18.952, y: 200, width: 8.914, height: 14),
                         CGRect(x: 10.694, y: 200, width: 8.258, height: 14),
                         CGRect(x: 5, y: 200, width: 5.694, height: 14)]
        for (location, x) in [(0, 27.866), (1, 18.952), (3, 5.0)] {
            let rtl = CursorAvatarPlacement.caretBounds(at: location, characterCount: 3, read: { range in
                range.length == 0 ? unavailable : rtlGlyphs[range.location]
            })
            assert(abs((rtl?.minX ?? -1) - x) < 0.001, "RTL insertion uses the logical glyph edge at \(location)")
        }
        let ambiguous = CursorAvatarPlacement.caretBounds(at: 0, characterCount: 1, read: { range in
            range.length == 0 ? unavailable : first
        })
        assert(ambiguous == nil, "a single glyph with no insertion direction must not fabricate a caret")
        let bidiGlyphs = [CGRect(x: 0, y: 100, width: 10, height: 14),
                          CGRect(x: 30, y: 100, width: 10, height: 14),
                          CGRect(x: 20, y: 100, width: 10, height: 14)]
        let bidi = CursorAvatarPlacement.caretBounds(at: 1, characterCount: 3, read: { range in
            range.length == 0 ? unavailable : bidiGlyphs[range.location]
        })
        assert(bidi == nil, "a bidi boundary with unknown insertion affinity must not fabricate a caret")
        #endif
        print("PASS Sonoma TextEdit zero-height caret at document start, end, existing blank line and trailing newline")
    }
}
