import AppKit
// Rebuilds the menu bar of a full-scene capture so only CalPeek's status item
// appears, then flattens (App Store screenshots must carry no alpha).
// Args: scene wall barEmpty barEmptyPtX strip stripPtX out
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
let scene0 = load(a[1]), wall = load(a[2]), barEmpty = load(a[3])
let barX = Int(a[4])!, strip = load(a[5]), stripX = Int(a[6])!
let regionPtX = 360, W = 2880, H = 1800, barH = 76
let wallPx = pixels(wall), barPx = pixels(barEmpty)
var s = pixels(scene0)
for row in 0..<min(barH, barPx.h) {
    var coefs = [(Double, Double)]()
    for ch in 0..<3 {
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, n = 0.0
        for col in stride(from: 4, to: barPx.w - 4, by: 2) {
            let x = Double(wallPx.data[row * wallPx.bpr + (barX * 2 + col) * 4 + ch])
            let y = Double(barPx.data[row * barPx.bpr + col * 4 + ch])
            sx += x; sy += y; sxx += x*x; sxy += x*y; n += 1
        }
        let d = n * sxx - sx * sx
        let m = d.magnitude < 1e-6 ? 0 : (n * sxy - sx * sy) / d
        coefs.append((m, (sy - m * sx) / n))
    }
    for col in 0..<W {
        let dst = row * s.bpr + col * 4, src = row * wallPx.bpr + (regionPtX * 2 + col) * 4
        for ch in 0..<3 {
            let v = coefs[ch].0 * Double(wallPx.data[src + ch]) + coefs[ch].1
            s.data[dst + ch] = UInt8(max(0, min(255, v.rounded())))
        }
        s.data[dst + 3] = 255
    }
}
let ctx = CGContext(data: &s.data, width: W, height: H, bitsPerComponent: 8, bytesPerRow: s.bpr,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(strip, in: CGRect(x: CGFloat((stripX - regionPtX) * 2), y: CGFloat(H - strip.height),
                           width: CGFloat(strip.width), height: CGFloat(strip.height)))
let flat = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
try! NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[7]))
print("wrote \(a[7])")
