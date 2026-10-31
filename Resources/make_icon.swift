// Renders the app icon into an .iconset folder. Usage: swift make_icon.swift <out.iconset>
// With a second argument "ios": full-bleed square PNGs for the iPhone app (iOS rounds
// the corners itself) named AppIcon60x60@2x/@3x.png, written into <out>.
// With "web": the same full-bleed squares for the web version (icon-180/192/512.png).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let web = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "web"
let ios = web || (CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "ios")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    var s = CGFloat(px) / 1024
    if ios {
        // Blow the 824-point tile up to the whole canvas.
        s = CGFloat(px) / 824
        let t = NSAffineTransform()
        t.translateX(by: -100 * s, yBy: -100 * s)
        t.concat()
    }
    let radius = ios ? 0 : 185 * s
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                          xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(red: 0.20, green: 0.24, blue: 0.36, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1))!.draw(in: bg, angle: -90)

    let colors = [NSColor(red: 0.36, green: 0.52, blue: 0.96, alpha: 1),
                  NSColor(red: 0.97, green: 0.62, blue: 0.20, alpha: 1),
                  NSColor(red: 0.25, green: 0.72, blue: 0.45, alpha: 1)]
    let cards = [3, 2, 1]
    for col in 0..<3 {
        let x = (200 + CGFloat(col) * 220) * s
        for row in 0..<cards[col] {
            let y = (700 - CGFloat(row) * 150) * s
            let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 180 * s, height: 120 * s),
                                 xRadius: 24 * s, yRadius: 24 * s)
            colors[col].withAlphaComponent(row == 0 ? 1 : 0.55).setFill()
            r.fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if web {
    for size in [180, 192, 512] { try! render(size).write(to: out.appendingPathComponent("icon-\(size).png")) }
    exit(0)
}
if ios {
    try! render(120).write(to: out.appendingPathComponent("AppIcon60x60@2x.png"))
    try! render(180).write(to: out.appendingPathComponent("AppIcon60x60@3x.png"))
    exit(0)
}
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
