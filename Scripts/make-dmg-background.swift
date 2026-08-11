#!/usr/bin/env swift
//
// Draws the disk image window background used by Scripts/release-direct.sh and
// writes it to Scripts/dmg-background.tiff as a two-representation (1x + 2x)
// TIFF, which is how Finder picks up a Retina background.
//
// The generated file is committed, so a release does not depend on running
// this. Re-run it only to change the artwork:
//
//   swift Scripts/make-dmg-background.swift
//
// The design deliberately stays quiet: CalPeek's icon is near-white, so the
// canvas is a faint warm gray that lets the icon read without competing with
// it, and the only mark is the arrow the window needs to explain itself.
// Finder draws its own "CalPeek" and "Applications" labels under the icons, so
// there is no text here to duplicate them.

import AppKit

// Matches the window content size and icon centers in release-direct.sh.
// Coordinates below are top-left origin, like the AppleScript that positions
// the icons; drawing flips them at the end.
let size = CGSize(width: 640, height: 400)
let appIcon = CGPoint(x: 170, y: 185)
let applicationsIcon = CGPoint(x: 470, y: 185)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixels.width),
        pixelsHigh: Int(pixels.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    // Leave rep.size in pixels while drawing. AppKit derives the context's
    // scale from rep.size, so tagging the point size here would compound with
    // the transform below and push everything off the canvas.
    rep.size = pixels

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext

    // A top-left origin makes the numbers above line up with the AppleScript.
    cg.translateBy(x: 0, y: pixels.height)
    cg.scaleBy(x: scale, y: -scale)

    // Canvas: a barely-there vertical gradient, lighter at the top so the
    // window reads as lit from above like every other Mac surface.
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.973, green: 0.969, blue: 0.961, alpha: 1),
        ending: NSColor(srgbRed: 0.925, green: 0.918, blue: 0.906, alpha: 1)
    )!
    // The context is flipped, so +90 paints the start color at the top.
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // Arrow: a flat bar and head from the app icon toward Applications, in a
    // gray light enough to guide without becoming the focal point.
    let ink = NSColor(srgbRed: 0.63, green: 0.62, blue: 0.60, alpha: 1)
    ink.setFill()

    let midY = appIcon.y
    let shaftStart = appIcon.x + 92
    let shaftEnd = applicationsIcon.x - 92
    let headLength: CGFloat = 20
    let headHalfHeight: CGFloat = 13
    let shaftHalfHeight: CGFloat = 3.5

    let shaft = NSBezierPath(
        roundedRect: NSRect(
            x: shaftStart,
            y: midY - shaftHalfHeight,
            width: shaftEnd - headLength - shaftStart,
            height: shaftHalfHeight * 2
        ),
        xRadius: shaftHalfHeight,
        yRadius: shaftHalfHeight
    )
    shaft.fill()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: shaftEnd, y: midY))
    head.line(to: NSPoint(x: shaftEnd - headLength, y: midY - headHalfHeight))
    head.line(to: NSPoint(x: shaftEnd - headLength, y: midY + headHalfHeight))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// One representation at 2x pixels, tagged 144 dpi, rather than a two-scale
// tiffutil -cathidpicheck bundle. Finder ignores the hidpi markup on a
// multi-representation background: it picks the 2x page and draws it at 1x, so
// the window shows only the top-left quarter of the artwork and the arrow
// falls off the right edge. Point size comes from the resolution tag, which
// Finder does honor, so this renders sharp on Retina and correctly sized
// everywhere.
let rep = render(scale: 2)
rep.size = size

let output = URL(fileURLWithPath: "Scripts/dmg-background.tiff")
guard let data = rep.representation(using: .tiff, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode the TIFF\n".utf8))
    exit(1)
}
try data.write(to: output)
print("wrote \(output.path)")
