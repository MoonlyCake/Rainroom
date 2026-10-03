import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(calibratedRed: 0.98, green: 0.35, blue: 0.47, alpha: 1), ending: NSColor(calibratedRed: 0.74, green: 0.10, blue: 0.27, alpha: 1))!.draw(in: background, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .regular)
if let symbol = NSImage(systemSymbolName: "cloud.rain.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let white = NSImage(size: symbol.size)
    white.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    white.unlockFocus()
    let ratio = 530 / white.size.width
    let h = white.size.height * ratio
    white.draw(in: NSRect(x: 247, y: (1024 - h) / 2, width: 530, height: h))
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
