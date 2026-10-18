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
// fits each row of the bar as a linear function of the wallpaper under it,
// from a stretch of bar with nothing in it, then evaluates that at every
// patched pixel. A run of icons is a few hundred pixels wide, and a single
// column stretched that far would show as a flat block against the
// wallpaper's gradient.
let a = CommandLine.arguments
guard a.count == 5 else { fputs("usage: bar_clean frame wall items out\n", stderr); exit(2) }
func pixels(_ path: String) -> (data: [UInt8], w: Int, h: Int) {
    let img = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h)
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
let erase = items.filter { !$0.id.hasPrefix("com.apple.") && $0.id != capture && $0.x >= 0 }
guard !erase.isEmpty else { print("nothing to erase"); exit(0) }

// The empty stretch: right of the app menus (which end well before 600pt
// with Finder in front) and left of the leftmost status item of any kind.
let leftmost = items.filter { $0.x >= 0 }.map(\.x).min() ?? 0
let sampleLo = 600 * 2, sampleHi = (leftmost - 8) * 2
guard sampleHi - sampleLo >= 100 else {
    fputs("no empty stretch of bar to fit against (leftmost item at \(leftmost)pt)\n", stderr); exit(1)
}

// Rows are counted from the top in both buffers: CGContext's bitmap memory
// starts at the image's top row.
var out = [UInt8](repeating: 0, count: frame.w * barH * 4)
for row in 0..<barH {
    var coefs = [(Double, Double)]()
    for ch in 0..<3 {
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, n = 0.0
        for col in stride(from: sampleLo, to: sampleHi, by: 2) {
            let x = Double(wall.data[(row * wall.w + col) * 4 + ch])
            let y = Double(frame.data[(row * frame.w + col) * 4 + ch])
            sx += x; sy += y; sxx += x * x; sxy += x * y; n += 1
        }
        let d = n * sxx - sx * sx
        let m = d.magnitude < 1e-6 ? 0 : (n * sxy - sx * sy) / d
        coefs.append((m, (sy - m * sx) / n))
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
let ctx = CGContext(data: &out, width: frame.w, height: barH, bitsPerComponent: 8, bytesPerRow: frame.w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[4]))
for item in erase { print("erased \(item.id) at \(item.x)pt") }
