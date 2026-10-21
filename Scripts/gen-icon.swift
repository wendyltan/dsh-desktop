import AppKit
import Foundation

// Keep the Dock icon and the menu-bar mark on the same whale silhouette.
let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard let whale = NSImage(contentsOf: root.appendingPathComponent("Resources/dsh-logo.svg")),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("cannot load whale asset or create icon bitmap\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedRed: 77 / 255, green: 107 / 255, blue: 254 / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192).fill()
let mark = NSImage(size: NSSize(width: 624, height: 624), flipped: false) { rect in
    whale.draw(in: rect)
    NSColor.white.setFill()
    rect.fill(using: .sourceIn)
    return true
}
mark.draw(in: NSRect(x: 200, y: 200, width: 624, height: 624))
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon encoding failed\n".utf8))
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : root.appendingPathComponent("bin/icon.png")
do {
    try png.write(to: out, options: .atomic)
    print("wrote \(out.path)")
} catch {
    FileHandle.standardError.write(Data("icon write failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
