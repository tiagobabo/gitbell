// Renders Resources/AppIcon.icns: the GitHub mark on a dark squircle with a notification dot.
// Usage: swift scripts/make-icon.swift
import AppKit

let markSVG = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M10.226 17.284c-2.965-.36-5.054-2.493-5.054-5.256 0-1.123.404-2.336 1.078-3.144-.292-.741-.247-2.314.09-2.965.898-.112 2.111.36 2.83 1.01.853-.269 1.752-.404 2.853-.404 1.1 0 1.999.135 2.807.382.696-.629 1.932-1.1 2.83-.988.315.606.36 2.179.067 2.942.72.854 1.101 2 1.101 3.167 0 2.763-2.089 4.852-5.098 5.234.763.494 1.28 1.572 1.28 2.807v2.336c0 .674.561 1.056 1.235.786 4.066-1.55 7.255-5.615 7.255-10.646C23.5 6.188 18.334 1 11.978 1 5.62 1 .5 6.188.5 12.545c0 4.986 3.167 9.12 7.435 10.669.606.225 1.19-.18 1.19-.786V20.63a2.9 2.9 0 0 1-1.078.224c-1.483 0-2.359-.808-2.987-2.313-.247-.607-.517-.966-1.034-1.033-.27-.023-.359-.135-.359-.27 0-.27.45-.471.898-.471.652 0 1.213.404 1.797 1.235.45.651.921.943 1.483.943.561 0 .92-.202 1.437-.719.382-.381.674-.718.944-.943"/></svg>"#
let mark = NSImage(data: Data(markSVG.replacingOccurrences(of: "<path ", with: "<path fill=\"#FFFFFF\" ").utf8))!

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // Apple's icon grid: 824pt body inset 100pt, corner radius ~185pt.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.27, blue: 0.33, alpha: 1),
                        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1)])!
        .draw(in: squircle, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    squircle.lineWidth = 3 * s
    squircle.stroke()

    mark.draw(in: NSRect(x: 252 * s, y: 236 * s, width: 520 * s, height: 520 * s))

    // Notification dot, knocked out of the body colour.
    let dot = NSRect(x: 694 * s, y: 694 * s, width: 150 * s, height: 150 * s)
    NSColor(srgbRed: 0.215, green: 0.24, blue: 0.295, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot.insetBy(dx: -18 * s, dy: -18 * s)).fill()
    NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.70, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.31, green: 0.50, blue: 0.91, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: dot), angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appending(path: "icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appending(path: "icon_\(size)x\(size)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "build/AppIcon-preview.png"))
