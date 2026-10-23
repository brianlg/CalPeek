import AppKit
// Builds an overlay that erases third-party menu bar items from a take.
//
//   bar_clean <frame.png> <wall.png> <items.txt> <out.png>
//
// items.txt is what `note_menubar_items` (common.sh) wrote just before the
// take: one `bundleID x width` line per status item, in points. Items that
// are neither Apple's nor CalPeek's capture build get painted over; every
// other pixel of the output is transparent, so cut_video.sh overlays it on
// the whole take as a single still.
//
// The paint is rebuilt menu bar, not a copied column: like compose_scene, it
// fits each row of the bar as a function of the wallpaper under it,
// from a stretch of bar with nothing in it, then evaluates that at every
// patched pixel. A run of icons is a few hundred pixels wide, and a single
// column stretched that far would show as a flat block against the
// wallpaper's gradient.
let a = CommandLine.arguments
guard a.count == 5 else { fputs("usage: bar_clean frame wall items out\n", stderr); exit(2) }
// Raw stored values, read and written with no colour management. ffmpeg
// treats PNG samples as plain numbers, so a patch fitted in a converted space
// (drawing into a DeviceRGB context did) lands visibly darker than the bar
// around it once overlaid.
func pixels(_ path: String) -> (data: [UInt8], w: Int, h: Int) {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path)))!
    precondition(rep.bitsPerSample == 8 && !rep.isPlanar, "\(path): want 8-bit interleaved samples")
    // Stride by bitsPerPixel, not samplesPerPixel: an RGB frame from ffmpeg
    // can be stored padded to 4 bytes a pixel.
    let w = rep.pixelsWide, h = rep.pixelsHigh, stride = rep.bitsPerPixel / 8, bpr = rep.bytesPerRow
    let src = rep.bitmapData!
    var out = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            for ch in 0..<3 { out[(y * w + x) * 4 + ch] = src[y * bpr + x * stride + ch] }
        }
    }
    return (out, w, h)
}
let frame = pixels(a[1]), wall = pixels(a[2])
let barH = 74      // the menu bar at 2x on a notched display, as find_dot
let pad = 5        // points; the countdown's text width nudges items left of the glyph
let capture = "com.briangibson.calpeek.capture"

struct Item { let id: String; let x: Int; let w: Int }
let items = try! String(contentsOfFile: a[3], encoding: .utf8)
    .split(separator: "\n").compactMap { line -> Item? in
        let f = line.split(separator: " ")
        guard f.count == 3, let x = Int(f[1]), let w = Int(f[2]), w > 0 else { return nil }
        return Item(id: String(f[0]), x: x, w: w)
    }
var erase = items.filter { !$0.id.hasPrefix("com.apple.") && $0.id != capture && $0.x >= 0 }

// The empty stretch to fit against: right of the app menus (which end well
// before 600pt with Finder in front), and short of where status items start.
// Capped at 900pt because Control Center hosts items Accessibility can't
// list (third-party Controls among them), so the leftmost listed item isn't
// necessarily the leftmost item.
let leftmost = items.filter { $0.x >= 0 }.map(\.x).min() ?? 0
let sampleLoPt = 600, sampleHiPt = min(900, leftmost - 8)
let sampleLo = sampleLoPt * 2, sampleHi = sampleHiPt * 2
guard sampleHi - sampleLo >= 100 else {
    fputs("no empty stretch of bar to fit against (leftmost item at \(leftmost)pt)\n", stderr); exit(1)
}

// Everything between that stretch and CalPeek's pill goes too, listed or
// not: a Control Center-hosted item has no position to read, but it can only
// be somewhere in that span. Stops 2pt short of the pill: any wider and the
// edge of the neighbouring icon survives as a sliver.
if let glyph = items.first(where: { $0.id == capture }), glyph.x - 2 > sampleHiPt {
    erase.append(Item(id: "everything left of CalPeek", x: sampleHiPt + pad, w: glyph.x - 2 - sampleHiPt - 2 * pad))
}
guard !erase.isEmpty else { print("nothing to erase"); exit(0) }

// Rows are counted from the top in both buffers, as stored in the PNGs.
var out = [UInt8](repeating: 0, count: frame.w * barH * 4)
for row in 0..<barH {
    var coefs = [(Double, Double)]()
    for ch in 0..<3 {
        // A scale through the origin, not slope-plus-offset: the bar is the
        // wallpaper darkened by a near-constant factor, and over a dark ground
        // a channel can vary by only a few levels across the sample, which
        // leaves a free slope at the mercy of dithering noise (green once
        // came out at 136 against a true 20).
        var sxx = 0.0, sxy = 0.0
        for col in stride(from: sampleLo, to: sampleHi, by: 2) {
            let x = Double(wall.data[(row * wall.w + col) * 4 + ch])
            let y = Double(frame.data[(row * frame.w + col) * 4 + ch])
            sxx += x * x; sxy += x * y
        }
        coefs.append((sxx < 1e-6 ? 0 : sxy / sxx, 0))
    }
    for item in erase {
        let lo = max(0, (item.x - pad) * 2), hi = min(frame.w, (item.x + item.w + pad) * 2)
        for col in lo..<hi {
            let o = (row * frame.w + col) * 4
            for ch in 0..<3 {
                let v = coefs[ch].0 * Double(wall.data[(row * wall.w + col) * 4 + ch]) + coefs[ch].1
                out[o + ch] = UInt8(max(0, min(255, v.rounded())))
            }
            out[o + 3] = 255
        }
    }
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: frame.w, pixelsHigh: barH,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: frame.w * 4, bitsPerPixel: 32)!
out.withUnsafeBufferPointer { rep.bitmapData!.update(from: $0.baseAddress!, count: out.count) }
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[4]))
for item in erase { print("erased \(item.id) at \(item.x)pt") }
