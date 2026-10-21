import AppKit
import Foundation

@main
struct AppIconTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("icon.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [root.appendingPathComponent("Scripts/gen-icon.swift").path, output.path]
        process.currentDirectoryURL = temporary
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "icon renderer must work outside the repo cwd")
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output))!
        precondition(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024, "icon must have exact pixel dimensions")
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "icon needs transparent outer padding")

        let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/dsh-logo.svg"))!
        let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mask)
        logo.draw(in: NSRect(x: 200, y: 200, width: 624, height: 624))
        NSGraphicsContext.restoreGraphicsState()
        var compared = 0
        for y in stride(from: 200, to: 824, by: 8) {
            for x in stride(from: 200, to: 824, by: 8) {
                let alpha = mask.colorAt(x: x, y: y)!.alphaComponent
                guard alpha > 0.98 || alpha < 0.02 else { continue }
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let isWhite = min(color.redComponent, color.greenComponent, color.blueComponent) > 0.95
                precondition(isWhite == (alpha > 0.98), "icon must preserve the whale silhouette rather than DS lettering")
                compared += 1
            }
        }
        precondition(compared > 4000, "enough interior samples must be compared")
        print("PASS app icon: exact raster size, transparent padding, preserved whale silhouette")
    }
}
