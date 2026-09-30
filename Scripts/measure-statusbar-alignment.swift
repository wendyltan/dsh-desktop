#!/usr/bin/env swift
// Run from the checkout: swift Scripts/measure-statusbar-alignment.swift Resources/dsh-logo.svg Sources/AppStore.swift
// Measures actual title ink and verifies the requested optical lift; centroids alone do not prove perceived alignment.
import AppKit

let logo = NSImage(contentsOfFile: CommandLine.arguments[1])!
let source = try! String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
let lift: CGFloat = 0.5
assert(source.contains("private let statusBarLogoOpticalLift: CGFloat = 0.5"), "Source optical lift differs from measured value")

let tintedLogo = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
    logo.draw(in: rect)
    NSColor.systemRed.setFill()
    rect.fill(using: .sourceIn)
    return true
}
let scale = 8
func centers(lift: CGFloat) -> (Double, Double) {
    let attachment = NSTextAttachment()
    attachment.image = tintedLogo
    attachment.bounds = NSRect(x: 0, y: (font.capHeight - 15) / 2 + lift, width: 15, height: 15)
    let title = NSMutableAttributedString(attachment: attachment)
    title.append(NSAttributedString(string: " ¥", attributes: [.font: font, .foregroundColor: NSColor.systemBlue]))
    title.append(NSAttributedString(string: "123.45", attributes: [.font: font, .foregroundColor: NSColor.systemGreen]))

    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100 * scale, pixelsHigh: 40 * scale,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                  bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    title.draw(at: NSPoint(x: 2, y: 10))
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    var logoWeight = 0.0, logoY = 0.0, digitWeight = 0.0, digitY = 0.0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let red = color.redComponent, green = color.greenComponent, blue = color.blueComponent
            let redInk = max(0, red - max(green, blue)) * color.alphaComponent
            let greenInk = max(0, green - max(red, blue)) * color.alphaComponent
            if redInk > 0.01 { logoWeight += redInk; logoY += redInk * Double(y) }
            if greenInk > 0.01 { digitWeight += greenInk; digitY += greenInk * Double(y) }
        }
    }
    assert(logoWeight > 0 && digitWeight > 0, "Could not measure rendered title")
    return (logoY / logoWeight / Double(scale), digitY / digitWeight / Double(scale))
}

let (originalWhale, originalDigits) = centers(lift: 0)
let (liftedWhale, digits) = centers(lift: lift)
let baselineGap = originalWhale - originalDigits
let liftedGap = liftedWhale - digits
print(String(format: "digit ink center before: %.3f pt; after: %.3f pt (image y increases downward)", originalDigits, digits))
print(String(format: "whale center before lift: %.3f pt; after %.1f pt lift: %.3f pt", originalWhale, lift, liftedWhale))
print(String(format: "center gap before: %.3f pt; after: %.3f pt", baselineGap, liftedGap))
assert(liftedWhale < originalWhale, "Configured lift did not move the rendered whale upward")
