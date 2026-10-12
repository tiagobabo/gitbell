import AppKit

public enum GitHubMark {
    // Octicons mark-github-24, MIT licensed.
    public static let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M10.226 17.284c-2.965-.36-5.054-2.493-5.054-5.256 0-1.123.404-2.336 1.078-3.144-.292-.741-.247-2.314.09-2.965.898-.112 2.111.36 2.83 1.01.853-.269 1.752-.404 2.853-.404 1.1 0 1.999.135 2.807.382.696-.629 1.932-1.1 2.83-.988.315.606.36 2.179.067 2.942.72.854 1.101 2 1.101 3.167 0 2.763-2.089 4.852-5.098 5.234.763.494 1.28 1.572 1.28 2.807v2.336c0 .674.561 1.056 1.235.786 4.066-1.55 7.255-5.615 7.255-10.646C23.5 6.188 18.334 1 11.978 1 5.62 1 .5 6.188.5 12.545c0 4.986 3.167 9.12 7.435 10.669.606.225 1.19-.18 1.19-.786V20.63a2.9 2.9 0 0 1-1.078.224c-1.483 0-2.359-.808-2.987-2.313-.247-.607-.517-.966-1.034-1.033-.27-.023-.359-.135-.359-.27 0-.27.45-.471.898-.471.652 0 1.213.404 1.797 1.235.45.651.921.943 1.483.943.561 0 .92-.202 1.437-.719.382-.381.674-.718.944-.943"/></svg>"#

    public static func image(size: CGFloat) -> NSImage {
        let source = NSImage(data: Data(svg.utf8)) ?? NSImage()
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    // Menu bar icon, always 18pt wide so the menu bar never shifts. Without a badge it's a template
    // image and the system tints it. With one, the mark is drawn in the menu bar's label colour at draw
    // time (so it follows light and dark menu bars) and gets a blue dot cut out of its corner.
    public static func menuBarImage(badge: Bool) -> NSImage {
        let source = NSImage(data: Data(svg.utf8)) ?? NSImage()
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            source.draw(in: rect.insetBy(dx: 1, dy: 1))
            guard badge else { return true }

            NSColor.labelColor.setFill()
            rect.fill(using: .sourceIn)

            let dot = NSRect(x: 11, y: 11, width: 7, height: 7)
            context.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            context.compositingOperation = .sourceOver
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = !badge
        return image
    }
}
