#!/usr/bin/swift
// Renders the Mac Monitor Control app icon as an .iconset directory.
//
// Draws the menu-bar symbol (laptopcomputer or display SF Symbol motif) on a
// white rounded square, using only macOS-native frameworks. No dependencies.
//
// Usage: swift scripts/render-app-icon.swift <output.iconset> [laptop|display]
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: render-app-icon.swift <output.iconset> [laptop|display]\n", stderr)
    exit(1)
}
let outDir = args[1]
let symbol = args.count >= 3 ? args[2] : "laptop"
guard symbol == "laptop" || symbol == "display" else {
    fputs("symbol must be 'laptop' or 'display'\n", stderr)
    exit(1)
}

// Design constants in a 1024-unit space, top-left origin.
let glyphColor = NSColor(red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0, alpha: 1.0)
let borderColor = NSColor(red: 216.0 / 255.0, green: 218.0 / 255.0, blue: 220.0 / 255.0, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fputs("no graphics context\n", stderr)
        exit(1)
    }
    // Work in the 1024-unit design space with a top-left origin.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: size / 1024.0, y: -size / 1024.0)

    // White rounded-square body.
    let body = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
        xRadius: 230, yRadius: 230)
    NSColor.white.setFill()
    body.fill()
    borderColor.setStroke()
    body.lineWidth = 4
    body.stroke()

    if symbol == "display" {
        // Screen outline.
        let screen = NSBezierPath(
            roundedRect: NSRect(x: 250, y: 300, width: 524, height: 320),
            xRadius: 40, yRadius: 40)
        glyphColor.setStroke()
        screen.lineWidth = 44
        screen.stroke()
        // Neck and stand.
        glyphColor.setFill()
        NSBezierPath(rect: NSRect(x: 484, y: 610, width: 56, height: 90)).fill()
        NSBezierPath(
            roundedRect: NSRect(x: 380, y: 690, width: 264, height: 44),
            xRadius: 22, yRadius: 22
        ).fill()
    } else {
        // Base (keyboard deck seen edge-on).
        glyphColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 200, y: 612, width: 624, height: 78),
            xRadius: 39, yRadius: 39
        ).fill()
        // Screen outline sitting on the base.
        let screen = NSBezierPath(
            roundedRect: NSRect(x: 262, y: 330, width: 500, height: 310),
            xRadius: 36, yRadius: 36)
        glyphColor.setStroke()
        screen.lineWidth = 44
        screen.stroke()
    }

    return image
}

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

do {
    try FileManager.default.createDirectory(
        atPath: outDir, withIntermediateDirectories: true, attributes: nil)
    for (name, px) in specs {
        let img = drawIcon(size: px)
        guard let tiff = img.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("failed to render \(name)\n", stderr)
            exit(1)
        }
        try png.write(to: URL(fileURLWithPath: outDir + "/" + name))
    }
    print("wrote iconset to \(outDir)")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
