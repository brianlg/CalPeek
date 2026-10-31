import AppKit
// Composites a normal window (Settings) onto the gradient canvas with a clean
// menu bar. The window's own `-o -l` capture already carries correct colour,
// so it just needs placing at its true screen coordinates.
// Args: wall barEmpty barPtX strip stripPtX winAlpha winPtX winPtY out
let a = CommandLine.arguments
func load(_ p: String) -> CGImage { NSImage(contentsOfFile: p)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func pixels(_ img: CGImage) -> (data: [UInt8], w: Int, h: Int, bpr: Int) {
    let w = img.width, h = img.height, bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h, bpr)
}
let wall = load(a[1]), barEmpty = load(a[2]), barX = Int(a[3])!
let strip = load(a[4]), stripX = Int(a[5])!
let win = load(a[6]), wx = Int(a[7])!, wy = Int(a[8])!
let regionPtX = 360, W = 2880, H = 1800, barH = 76
let wallPx = pixels(wall), barPx = pixels(barEmpty)

var canvas = [UInt8](repeating: 0, count: W * 4 * H)
for row in 0..<H {
    for col in 0..<W {
        let s = row * wallPx.bpr + (regionPtX * 2 + col) * 4, d = row * W * 4 + col * 4
        canvas[d] = wallPx.data[s]; canvas[d+1] = wallPx.data[s+1]
        canvas[d+2] = wallPx.data[s+2]; canvas[d+3] = 255
    }
}
for row in 0..<min(barH, barPx.h) {
    var coefs = [(Double, Double)]()
    for ch in 0..<3 {
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, n = 0.0
        for col in stride(from: 4, to: barPx.w - 4, by: 2) {
            let x = Double(wallPx.data[row * wallPx.bpr + (barX * 2 + col) * 4 + ch])
            let y = Double(barPx.data[row * barPx.bpr + col * 4 + ch])
            sx += x; sy += y; sxx += x*x; sxy += x*y; n += 1
        }
        let dd = n * sxx - sx * sx
        let m = dd.magnitude < 1e-6 ? 0 : (n * sxy - sx * sy) / dd
        coefs.append((m, (sy - m * sx) / n))
    }
    for col in 0..<W {
        let d = row * W * 4 + col * 4
        for ch in 0..<3 {
            let v = coefs[ch].0 * Double(canvas[d + ch]) + coefs[ch].1
            canvas[d + ch] = UInt8(max(0, min(255, v.rounded())))
        }
    }
}
let ctx = CGContext(data: &canvas, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 52, color: CGColor(gray: 0, alpha: 0.28))
ctx.draw(win, in: CGRect(x: CGFloat((wx - regionPtX) * 2),
                         y: CGFloat(H - wy * 2 - win.height),
                         width: CGFloat(win.width), height: CGFloat(win.height)))
ctx.restoreGState()
ctx.draw(strip, in: CGRect(x: CGFloat((stripX - regionPtX) * 2), y: CGFloat(H - strip.height),
                           width: CGFloat(strip.width), height: CGFloat(strip.height)))
let flat = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
try! NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[9]))
print("wrote \(a[9])")
