import AppKit
import CoreImage
import Vision

// usage: process <raw.png> <out.png> <targetHeightPx>
// prints JSON: bbox, caret bar center x (normalized in output image), seat point guess
let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let targetHeight = Int(args[3]) ?? 288

guard let src = NSImage(contentsOf: input)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load \(input.path)")
}
let w = src.width, h = src.height
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
let corners = [at(2, 2), at(w - 3, 2), at(2, h - 3), at(w - 3, h - 3)]
let hasAlpha = corners.allSatisfy { px[$0 + 3] < 10 }
let magenta = corners.allSatisfy { px[$0] > 200 && px[$0 + 1] < 60 && px[$0 + 2] > 200 }

func unpremultiply() {
    for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 0 && px[i + 3] < 255 {
        let a = Double(px[i + 3]) / 255
        for c in 0..<3 { px[i + c] = UInt8(min(255, Double(px[i + c]) / a)) }
    }
}
unpremultiply()

if magenta {
    for i in stride(from: 0, to: px.count, by: 4) {
        let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
        let key = min(r, b) - g
        if key > 120 { px[i + 3] = 0 } else if key > 40 {
            px[i + 3] = UInt8(255 * (120 - key) / 80)
            px[i] = UInt8(min(r, g + 40)); px[i + 2] = UInt8(min(b, g + 40))
        }
    }
} else if !hasAlpha {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: src)
    try handler.perform([request])
    guard let result = request.results?.first else { fatalError("no foreground") }
    let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    let base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: Float.self)
    let stride = CVPixelBufferGetBytesPerRow(mask) / 4
    for y in 0..<h { for x in 0..<w {
        px[at(x, y) + 3] = UInt8(max(0, min(255, base[y * stride + x] * 255)))
    } }
    CVPixelBufferUnlockBaseAddress(mask, .readOnly)
}

// Green caret placeholder: remove and record its columns.
var greenColumns = [Int](repeating: 0, count: w)
for y in 0..<h { for x in 0..<w {
    let i = at(x, y)
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    if px[i + 3] > 0 && g > 150 && g - max(r, b) > 70 {
        px[i + 3] = 0; greenColumns[x] += 1
    } else if px[i + 3] > 0 && g - max(r, b) > 30 && g > 120 {
        px[i + 1] = UInt8(max(r, b))
    }
} }

let barColumns = greenColumns.enumerated().filter { $0.element > h / 4 }.map(\.offset)
if let lo = barColumns.min(), let hi = barColumns.max() {
    for y in 0..<h { for x in max(0, lo - 6)...min(w - 1, hi + 6) {
        let i = at(x, y)
        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
        if g - max(r, b) > 40 { px[i + 3] = 0 } else if g > max(r, b) { px[i + 1] = UInt8(max(r, b)) }
    } }
}

var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where px[at(x, y) + 3] > 24 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let margin = Int(Double(max(maxX - minX, maxY - minY)) * 0.03)
minX = max(0, minX - margin); minY = max(0, minY - margin)
maxX = min(w - 1, maxX + margin); maxY = min(h - 1, maxY + margin)
let cw = maxX - minX + 1, ch = maxY - minY + 1

// premultiply back for CGImage
for i in stride(from: 0, to: px.count, by: 4) {
    let a = Double(px[i + 3]) / 255
    for c in 0..<3 { px[i + c] = UInt8(Double(px[i + c]) * a) }
}
let full = ctx.makeImage()!
// CGContext rows are bottom-up in drawing coords but memory is top-down; crop uses top-left origin
let cropped = full.cropping(to: CGRect(x: minX, y: minY, width: cw, height: ch))!
let outH = targetHeight
let outW = Int((Double(cw) / Double(ch) * Double(outH)).rounded())
let octx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
octx.interpolationQuality = .high
octx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
let rep = NSBitmapImageRep(cgImage: octx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: output)

let barCols = greenColumns.enumerated().filter { $0.element > h / 4 }.map(\.offset)
let barX = barCols.isEmpty ? nil : Double(barCols.reduce(0, +)) / Double(barCols.count)
let barNorm = barX.map { ($0 - Double(minX)) / Double(cw) }
let barWidth = barCols.isEmpty ? 0 : Double(barCols.count) / Double(cw)
print("{\"file\":\"\(output.lastPathComponent)\",\"bg\":\"\(hasAlpha ? "alpha" : magenta ? "magenta" : "vision")\",\"size\":[\(outW),\(outH)],\"aspect\":\(Double(outW)/Double(outH)),\"caretBarX\":\(barNorm.map { String(format: "%.3f", $0) } ?? "null"),\"caretBarWidth\":\(String(format: "%.3f", barWidth))}")
