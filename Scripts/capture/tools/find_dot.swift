import AppKit
import Foundation
// Locates macOS's screen-recording indicators in a frame of a take, and prints
// one patch rect per indicator: `px pw sx bh`.
//
// These are privacy affordances and nothing can disable them, so every real
// screen recording carries them and they would otherwise sit in the App Store
// preview announcing that the video is a capture. On this macOS there are TWO,
// which is why this prints a list and not a single rect:
//
//   - a small violet dot between Control Center and the clock, and
//   - a purple capsule (a display glyph) to the left of the other status items.
//
// Both move: the capsule's x depends on what else is in the bar, and the dot's
// on the clock's text width -- "9:29 PM" and "8:15 AM" are not the same number
// of pixels. So they are found per take, never hardcoded.
//
// Colour test: the indicators are blue-VIOLET (~75,59,232). Matching on
// blueness alone also caught CalPeek's own system-blue event dot (~10,132,255)
// in the glyph, and taking the bounding box of every match then painted a
// 666px patch across the whole right of the bar, erasing the glyph and every
// system item with it. The discriminator is r > g, which system blue fails.
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let BAR_H = 74                      // menu bar at 2x on a notched display
let w = img.width
var buf = [UInt8](repeating: 0, count: w * BAR_H * 4)
let c = CGContext(data: &buf, width: w, height: BAR_H, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.draw(img, in: CGRect(x: 0, y: CGFloat(BAR_H - img.height), width: CGFloat(w), height: CGFloat(img.height)))

func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(buf[i]), Int(buf[i+1]), Int(buf[i+2]))
}

// Columns containing indicator violet, and columns that are clear bar (no
// bright glyph pixel anywhere in the band) -- the latter are patch sources.
var hit = [Bool](repeating: false, count: w)
var clear = [Bool](repeating: true, count: w)
for x in 0..<w {
    for y in 0..<BAR_H {
        let (r, g, b) = px(x, y)
        if b > 150 && b - g > 80 && r > g { hit[x] = true }
        if r > 130 && g > 130 && b > 130 { clear[x] = false }   // white glyph or text
        if b > 150 && b - g > 80 && r > g { clear[x] = false }
    }
}

// Group hit columns into clusters, splitting on any gap wider than a few px.
var clusters: [(Int, Int)] = []
var lo = -1, hi = -1
for x in 0..<w where hit[x] {
    if lo < 0 { lo = x; hi = x }
    else if x - hi > 8 { clusters.append((lo, hi)); lo = x; hi = x }
    else { hi = x }
}
if lo >= 0 { clusters.append((lo, hi)) }
guard !clusters.isEmpty else { exit(1) }

for (l, r) in clusters {
    let pxs = max(0, l - 8), pw = min(w - pxs, (r + 8) - pxs)
    // An indicator is a dot or a small capsule. Anything wide means the
    // detector matched something it should not have; refuse rather than
    // deface the bar.
    guard pw <= 140 else { fputs("cluster too wide (\(pw)px) -- refusing\n", stderr); exit(1) }
    // Nearest clear-bar column, at least a few px outside the patch, searched
    // outward in both directions. The bar is a smooth horizontal gradient, so
    // the nearest clear column stretched across the patch is invisible.
    var src = -1
    for d in 6..<600 {
        if pxs - d >= 0, clear[pxs - d] { src = pxs - d; break }
        if pxs + pw + d < w, clear[pxs + pw + d] { src = pxs + pw + d; break }
    }
    guard src >= 0 else { fputs("no clear bar near cluster at \(pxs)\n", stderr); exit(1) }
    print("\(pxs) \(pw) \(src) \(BAR_H)")
}
