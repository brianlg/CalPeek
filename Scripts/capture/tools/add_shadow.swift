import AppKit

// Adds a macOS-window-style drop shadow to a transparent popover capture and
// pads the canvas so the shadow has room. The captures are taken with
// `screencapture -o` (no shadow) because mask_region needs the window's exact
// bounds to composite the vibrancy; the README, though, showed shadowed
// popovers from the first release on, and flat-edged cards read as cut-outs.
//
//   ./add_shadow in.png out.png [blur offsetY alpha padX padTop padBottom]   (px @2x)
let a = CommandLine.arguments
let inPath = a[1], outPath = a[2]
let blur = a.count > 3 ? Double(a[3])! : 36
let offY = a.count > 4 ? Double(a[4])! : 18
let alpha = a.count > 5 ? Double(a[5])! : 0.28
let padX = a.count > 6 ? Int(a[6])! : 40
let padT = a.count > 7 ? Int(a[7])! : 30
let padB = a.count > 8 ? Int(a[8])! : 90

let src = NSImage(contentsOfFile: inPath)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
// Trim the capture's own transparent margin first so padding is measured from
// the popover's real edge, not from wherever the window frame happened to be.
let rep = NSBitmapImageRep(cgImage: src)
var minX = src.width, minY = src.height, maxX = 0, maxY = 0
for y in 0..<src.height { for x in 0..<src.width where rep.colorAt(x: x, y: y)!.alphaComponent > 0.02 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let content = src.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

let W = content.width + padX * 2, H = content.height + padT + padB
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// CG origin is bottom-left: the bottom pad is where the shadow falls.
let dst = CGRect(x: padX, y: padB, width: content.width, height: content.height)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -offY), blur: CGFloat(blur), color: CGColor(gray: 0, alpha: CGFloat(alpha)))
ctx.draw(content, in: dst)
ctx.restoreGState()
// Draw the content once more without the shadow so the shadow never tints the
// popover's own translucent pixels.
ctx.draw(content, in: dst)
let out = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("\(outPath) \(W)x\(H)")
