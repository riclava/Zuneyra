#!/usr/bin/env swift
// Export the approved artwork without changing its design.
// iOS receives an opaque full-bleed master; macOS receives the same artwork
// inside the platform's inset rounded-square silhouette on a transparent canvas.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func export(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconExport", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "IconExport", code: 2) }
}

let arguments = CommandLine.arguments
 guard arguments.count == 3 else { fatalError("Usage: swift scripts/generate-app-icons.swift <artwork.png> <AppIcon.appiconset>") }
let sourceURL = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("Cannot read icon artwork") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int, mac: Bool) throws -> CGImage {
    let alpha: CGImageAlphaInfo = mac ? .premultipliedLast : .noneSkipLast
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: colorSpace, bitmapInfo: alpha.rawValue) else { throw NSError(domain: "IconExport", code: 3) }
    context.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    if mac {
        let scale = CGFloat(pixels) / 1024
        let shape = canvas.insetBy(dx: 100 * scale, dy: 100 * scale)
        let path = CGPath(roundedRect: shape, cornerWidth: 184 * scale, cornerHeight: 184 * scale, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 18 * scale, color: CGColor(gray: 0, alpha: 0.22))
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.85, green: 0.08, blue: 0.22, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.clip()
        context.draw(artwork, in: shape)
    } else {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(canvas)
        context.draw(artwork, in: canvas)
    }
    guard let image = context.makeImage() else { throw NSError(domain: "IconExport", code: 4) }
    return image
}

let iosFilename = "AppIcon-iOS-1024.png"
try export(render(pixels: 1024, mac: false), to: output.appendingPathComponent(iosFilename))
var images: [[String: String]] = [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": iosFilename]]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "AppIcon-mac-\(size)@\(scale)x.png"
        try export(render(pixels: size * scale, mac: true), to: output.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("Contents.json"), options: .atomic)
print("Exported iOS master and 10 macOS icon representations.")
