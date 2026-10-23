import AppKit
// Cuts a window group out of the scene using its `screencapture -o -l` alpha,
// keeping the scene's correct vibrancy tint. Args: scene regionPtX alpha ptX ptY out
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
let scene = pixels(load(a[1])), regionPtX = Int(a[2])!
let al = pixels(load(a[3]))
let ux = (Int(a[4])! - regionPtX) * 2, uy = Int(a[5])! * 2
var out = [UInt8](repeating: 0, count: al.bpr * al.h)
for y in 0..<al.h {
    for x in 0..<al.w {
        let av = al.data[y * al.bpr + x * 4 + 3]
        let sy = y + uy, sx = x + ux
        guard sy >= 0, sy < scene.h, sx >= 0, sx < scene.w else { continue }
        let d = y * al.bpr + x * 4, sp = sy * scene.bpr + sx * 4
        let f = Double(av) / 255
        for ch in 0..<3 { out[d + ch] = UInt8(Double(scene.data[sp + ch]) * f) }
        out[d + 3] = av
    }
}
let c = CGContext(data: &out, width: al.w, height: al.h, bitsPerComponent: 8, bytesPerRow: al.bpr,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[6]))
print("wrote \(a[6]) \(al.w)x\(al.h)")
