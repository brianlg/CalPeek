import AppKit

// Locates the accent-coloured regions in a popover capture and prints them as
//   <centre-x-pt> <centre-y-pt> <width-pt> <height-pt> <pixels>
// one per line, largest first, in points relative to the image's top-left.
//
// Why: the old scripts reached day cells with hardcoded arithmetic
// (`MX + 13 + 16 + 3.5*(268/7)`), which silently aims at the wrong cell the
// moment the month starts on a different weekday or the week-number column is
// switched on. Today's marker and the Join button are the two things drawn in
// the accent colour, so finding them by colour is both shorter and stable.
//
// Args: <capture.png> [scale]   scale defaults to 2 (Retina)

let args = CommandLine.arguments
guard args.count >= 2,
      let img = NSImage(contentsOfFile: args[1])?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("usage: find_accent <capture.png> [scale]") }
let scale = args.count >= 3 ? Double(args[2])! : 2.0

let w = img.width, h = img.height, bpr = w * 4
var buf = [UInt8](repeating: 0, count: bpr * h)
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

/// Strongly saturated warm pixels: the marker fill and the Join button. Kept
/// deliberately loose so a user-chosen accent preset still matches, while the
/// blue/green event dots (which are cooler and where blue dominates) do not.
func isAccent(_ o: Int) -> Bool {
    let r = Int(buf[o]), g = Int(buf[o + 1]), b = Int(buf[o + 2]), a = Int(buf[o + 3])
    guard a > 200 else { return false }
    let mx = max(r, g, b), mn = min(r, g, b)
    guard mx > 90, mx - mn > 60 else { return false }   // saturated, not grey
    return r == mx && b < r - 40                        // warm: red/orange/pink
}

// Flood fill into connected components.
var seen = [Bool](repeating: false, count: w * h)
struct Blob { var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, n = 0 }
var blobs: [Blob] = []

for y in 0..<h {
    for x in 0..<w where !seen[y * w + x] && isAccent(y * bpr + x * 4) {
        var blob = Blob()
        var stack = [(x, y)]
        seen[y * w + x] = true
        while let (cx, cy) = stack.popLast() {
            blob.minX = min(blob.minX, cx); blob.maxX = max(blob.maxX, cx)
            blob.minY = min(blob.minY, cy); blob.maxY = max(blob.maxY, cy)
            blob.n += 1
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h, !seen[ny * w + nx],
                      isAccent(ny * bpr + nx * 4) else { continue }
                seen[ny * w + nx] = true
                stack.append((nx, ny))
            }
        }
        // Ignore antialiasing specks and the small event dots.
        if blob.n > 200 { blobs.append(blob) }
    }
}

for b in blobs.sorted(by: { $0.n > $1.n }) {
    let cx = Double(b.minX + b.maxX) / 2 / scale
    let cy = Double(b.minY + b.maxY) / 2 / scale
    let bw = Double(b.maxX - b.minX + 1) / scale
    let bh = Double(b.maxY - b.minY + 1) / scale
    print(String(format: "%.1f %.1f %.1f %.1f %d", cx, cy, bw, bh, b.n))
}
