import AppKit

// A simple, code-drawn utility icon using Apple's lightbulb symbol.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [[String: String]] = []
for (size, scale) in sizes {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let inset = rect.insetBy(dx: Double(pixels) * 0.05, dy: Double(pixels) * 0.05)
    NSColor(srgbRed: 0.16, green: 0.19, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: inset, xRadius: Double(pixels) * 0.2, yRadius: Double(pixels) * 0.2).fill()
    let configuration = NSImage.SymbolConfiguration(pointSize: Double(pixels) * 0.54, weight: .regular)
        .applying(.init(paletteColors: [NSColor(srgbRed: 1, green: 0.79, blue: 0.4, alpha: 1)]))
    let bulb = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(configuration)!
    let ratio = min(Double(pixels) * 0.5 / bulb.size.width, Double(pixels) * 0.6 / bulb.size.height)
    let w = bulb.size.width * ratio, h = bulb.size.height * ratio
    bulb.draw(in: NSRect(x: (Double(pixels) - w) / 2, y: (Double(pixels) - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
    entries.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
