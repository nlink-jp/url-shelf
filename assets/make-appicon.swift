#!/usr/bin/env swift
// make-appicon.swift — render assets/AppIcon-1024.png, the source image the
// build pipeline turns into AppIcon.icns (scripts/make-icns.sh).
//
//   swift assets/make-appicon.swift
//
// Draws the macOS "squircle" with a gradient and the same SF Symbol the status
// item uses, so the app icon and the menu bar read as one identity.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Clip to the squircle (Apple's app-icon corner radius ≈ 0.2237 × side).
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.2237
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

// Diagonal teal gradient: distinct at a glance from the other menu bar apps in
// the series, which are blue.
let colors = [
    NSColor(srgbRed: 0.13, green: 0.66, blue: 0.62, alpha: 1).cgColor,
    NSColor(srgbRed: 0.06, green: 0.35, blue: 0.42, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// Centered white shelf glyph — the status item's symbol.
let symbolName = "books.vertical.fill"
let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
   let symbol = base.withSymbolConfiguration(config) {
    let s = symbol.size
    // Tint the symbol white in its own layer so we don't flood the background.
    let white = NSImage(size: s)
    white.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    white.unlockFocus()

    let dest = NSRect(x: (size - s.width) / 2,
                      y: (size - s.height) / 2 - size * 0.01,
                      width: s.width, height: s.height)
    white.draw(in: dest)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}

let output = URL(fileURLWithPath: "assets/AppIcon-1024.png")
try png.write(to: output)
print("[make-appicon] wrote \(output.path)")
