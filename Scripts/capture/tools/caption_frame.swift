import AppKit
// Lays the App Store marketing copy over a finished 2880x1800 frame.
//
//   ./caption_frame in.png out.png <align> <xFrac> <yFrac> <wFrac> "Headline" "Sub head"
//
// align is left|right|center and describes the text's own alignment; x/y/w are
// fractions of the frame, x being the block's leading edge (its trailing edge
// when right-aligned, its centre when centred) and y the block's vertical
// centre. Positions are passed in rather than fixed because the art sits in a
// different corner in each frame, and copy laid over the popover is the one
// mistake that cannot be fixed in review.
//
// Type matches the 1.0 set: SF Pro Display heavy for the headline, regular for
// the sub head, white on a muted blue-grey.
let a = CommandLine.arguments
guard a.count >= 9 else { fputs("usage: caption_frame in out align x y w headline sub\n", stderr); exit(2) }
let img = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = img.width, H = img.height
let align = a[3], xF = Double(a[4])!, yF = Double(a[5])!, wF = Double(a[6])!
// Literal \n in the arguments is a real line break: a headline that wraps
// wherever the box happens to end ("Your calendar. One / click away.") breaks
// the phrase in the wrong place, and the break is a typographic decision.
let headline = a[7].replacingOccurrences(of: "\\n", with: "\n")
let sub = a[8].replacingOccurrences(of: "\\n", with: "\n")

// Sized against the 1.0 frames at 2880 wide, and scaled from there so the tool
// still holds if the frame size ever changes.
let s = CGFloat(W) / 2880
let HEAD_SIZE: CGFloat = 108 * s, SUB_SIZE: CGFloat = 42 * s
let GAP: CGFloat = 34 * s

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let para = NSMutableParagraphStyle()
para.alignment = align == "center" ? .center : (align == "right" ? .right : .left)
para.lineSpacing = 12 * s

let subPara = NSMutableParagraphStyle()
subPara.alignment = para.alignment
subPara.lineSpacing = 16 * s

let headAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: HEAD_SIZE, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
]
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: SUB_SIZE, weight: .regular),
    .foregroundColor: NSColor(srgbRed: 0.64, green: 0.67, blue: 0.75, alpha: 1),
    .paragraphStyle: subPara,
]

let boxW = CGFloat(W) * CGFloat(wF)
let hs = NSAttributedString(string: headline, attributes: headAttrs)
let ss = NSAttributedString(string: sub, attributes: subAttrs)
let hRect = hs.boundingRect(with: NSSize(width: boxW, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
let sRect = ss.boundingRect(with: NSSize(width: boxW, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
let total = hRect.height + GAP + sRect.height

// x is the block's leading edge, or its trailing edge / centre per alignment.
var x = CGFloat(W) * CGFloat(xF)
if align == "right" { x -= boxW } else if align == "center" { x -= boxW / 2 }
// y is the block's vertical centre, measured from the TOP of the frame.
let topY = CGFloat(H) * CGFloat(yF) - total / 2
let flip = { (yFromTop: CGFloat, h: CGFloat) in CGFloat(H) - yFromTop - h }

hs.draw(with: NSRect(x: x, y: flip(topY, hRect.height), width: boxW, height: hRect.height),
        options: [.usesLineFragmentOrigin, .usesFontLeading])
ss.draw(with: NSRect(x: x, y: flip(topY + hRect.height + GAP, sRect.height), width: boxW, height: sRect.height),
        options: [.usesLineFragmentOrigin, .usesFontLeading])

NSGraphicsContext.restoreGraphicsState()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[2]))
print("wrote \(a[2])")
