import AppKit
// Renders one caption as a transparent 1920x1080 PNG, for ffmpeg to overlay on
// the recorded take. Drawn here rather than with ffmpeg's drawtext so the
// captions keep real SF Pro semibold and proper line spacing, matching what
// the composited cut used.
//
//   ./caption out.png "Your month.\nOne click away."
let a = CommandLine.arguments
let W = 1920, H = 1080
let text = a[2].replacingOccurrences(of: "\\n", with: "\n")
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let para = NSMutableParagraphStyle(); para.lineSpacing = 10
let s = NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
    // The ground is a dark plum. A dark ink here is not merely low contrast,
    // it is invisible.
    .foregroundColor: NSColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1),
    // A soft drop shadow keeps the ink legible where the gradient lightens.
    .shadow: { let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.45)
               sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -2); return sh }(),
    .paragraphStyle: para,
])
s.draw(at: NSPoint(x: 108, y: CGFloat(H) * 0.46 - s.size().height / 2))
NSGraphicsContext.restoreGraphicsState()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[1]))
