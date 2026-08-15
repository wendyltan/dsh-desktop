import AppKit
import Foundation

// 生成 1024x1024 的应用图标 PNG：渐变圆角方块 + "DS"。
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 40
let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.45, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.55, alpha: 1),
])!
gradient.draw(in: path, angle: -90)

let text = "DS" as NSString
let font = NSFont.systemFont(ofSize: 430, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let tSize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (CGFloat(size) - tSize.width) / 2, y: (CGFloat(size) - tSize.height) / 2), withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dsh-icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
