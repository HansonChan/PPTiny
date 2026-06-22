import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetDir = root.appendingPathComponent("Assets/AppIcon", isDirectory: true)
let iconsetDir = assetDir.appendingPathComponent("PPTiny.iconset", isDirectory: true)
let previewURL = assetDir.appendingPathComponent("PPTiny-icon-preview.png")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let paper = NSColor(calibratedRed: 0.957, green: 0.933, blue: 0.875, alpha: 1)
let ink = NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.067, alpha: 1)
let red = NSColor(calibratedRed: 0.843, green: 0.2, blue: 0.165, alpha: 1)
let blue = NSColor(calibratedRed: 0.122, green: 0.373, blue: 0.667, alpha: 1)
let yellow = NSColor(calibratedRed: 0.949, green: 0.788, blue: 0.298, alpha: 1)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = size / 1024
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let body = bounds.insetBy(dx: 64 * scale, dy: 64 * scale)
    let radius = 190 * scale
    let bg = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    paper.setFill()
    bg.fill()

    ink.setStroke()
    bg.lineWidth = 20 * scale
    bg.stroke()

    let page = CGRect(x: 238 * scale, y: 234 * scale, width: 384 * scale, height: 560 * scale)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 34 * scale, yRadius: 34 * scale)
    NSColor.white.withAlphaComponent(0.92).setFill()
    pagePath.fill()
    ink.setStroke()
    pagePath.lineWidth = 16 * scale
    pagePath.stroke()

    let fold = NSBezierPath()
    fold.move(to: CGPoint(x: page.maxX - 110 * scale, y: page.maxY))
    fold.line(to: CGPoint(x: page.maxX, y: page.maxY - 110 * scale))
    fold.line(to: CGPoint(x: page.maxX - 110 * scale, y: page.maxY - 110 * scale))
    fold.close()
    yellow.setFill()
    fold.fill()
    ink.setStroke()
    fold.lineWidth = 10 * scale
    fold.stroke()

    red.setFill()
    NSBezierPath(ovalIn: CGRect(x: 292 * scale, y: 580 * scale, width: 124 * scale, height: 124 * scale)).fill()

    blue.setFill()
    NSBezierPath(rect: CGRect(x: 292 * scale, y: 418 * scale, width: 248 * scale, height: 120 * scale)).fill()

    yellow.setFill()
    NSBezierPath(rect: CGRect(x: 292 * scale, y: 330 * scale, width: 172 * scale, height: 44 * scale)).fill()

    let compression = NSBezierPath()
    compression.move(to: CGPoint(x: 654 * scale, y: 610 * scale))
    compression.line(to: CGPoint(x: 790 * scale, y: 512 * scale))
    compression.line(to: CGPoint(x: 654 * scale, y: 414 * scale))
    compression.close()
    red.setFill()
    compression.fill()
    ink.setStroke()
    compression.lineWidth = 14 * scale
    compression.stroke()

    blue.setFill()
    NSBezierPath(rect: CGRect(x: 662 * scale, y: 286 * scale, width: 142 * scale, height: 142 * scale)).fill()

    let pText = "P" as NSString
    let pAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 178 * scale, weight: .black),
        .foregroundColor: ink
    ]
    pText.draw(in: CGRect(x: 320 * scale, y: 424 * scale, width: 160 * scale, height: 190 * scale), withAttributes: pAttrs)

    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PPTiny.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode icon PNG"])
    }
    try data.write(to: url, options: .atomic)
}

let files: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in files {
    try writePNG(drawIcon(size: size), to: iconsetDir.appendingPathComponent(name), pixels: Int(size))
}

try writePNG(drawIcon(size: 1024), to: previewURL, pixels: 1024)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetDir.path,
    "-o", assetDir.appendingPathComponent("PPTiny.icns").path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "PPTiny.Icon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Generated \(assetDir.appendingPathComponent("PPTiny.icns").path)")
