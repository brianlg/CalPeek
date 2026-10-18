import AppKit

// Prints the centre of every row glyph in a day-list capture -- the blue
// calendar dots and the reminder ring -- as "x y" in points, top-down, one per
// row. Capture scripts click and hover rows from these rather than from an
// estimated row pitch: a 40pt row forgives a 12pt guess, a 12pt ring does not.
//
//   ./find_glyph vid/day.png
let img = NSImage(contentsOfFile: CommandLine.arguments[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let rep = NSBitmapImageRep(cgImage: img)
let w = img.width, h = img.height
// Blue: the calendar tint the glyphs share (the ring is stroked in the same
// colour). Generous, so it survives the popover's vibrancy.
func isBlue(_ x: Int, _ y: Int) -> Bool {
    guard let c = rep.colorAt(x: x, y: y) else { return false }
    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
    return b > 0.6 && b > r + 0.3 && b > g + 0.15 && c.alphaComponent > 0.5
}
// Row bands: any raster row containing blue pixels; consecutive rows merge.
var bands: [(Int, Int, [Int])] = []   // (y0, y1, xs)
for y in 0..<h {
    var xs: [Int] = []
    for x in 0..<w where isBlue(x, y) { xs.append(x) }
    guard !xs.isEmpty else { continue }
    if let last = bands.last, y == last.1 + 1 { bands[bands.count - 1] = (last.0, y, last.2 + xs) }
    else { bands.append((y, y, xs)) }
}
// A glyph is a compact blob; the month grid's dots are tiny (< 8px tall) and
// the banner's video icon is red, so height 14–40px (7–20pt) isolates rows.
for (y0, y1, xs) in bands where (y1 - y0) >= 14 && (y1 - y0) <= 40 {
    // Leftmost cluster only: the row's glyph, not a blue Save button or the
    // colour picker that sits at the far right of a form.
    let sorted = xs.sorted()
    var cluster: [Int] = [sorted[0]]
    for x in sorted.dropFirst() { if x - cluster.last! <= 3 { cluster.append(x) } else { break } }
    let cx = Double(cluster.min()! + cluster.max()!) / 2 / 2   // px -> pt
    let cy = Double(y0 + y1) / 2 / 2
    print(String(format: "%.1f %.1f", cx, cy))
}
