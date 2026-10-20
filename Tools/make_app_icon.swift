// Draws the Taalhulp app icon (1024 × 1024, no transparency, as iOS requires).
// Run on the Mac:
//   swiftc -o /tmp/make_app_icon Tools/make_app_icon.swift && /tmp/make_app_icon
// Writes App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// The design: a speech bubble ("taal" = language) holding "Aa", with a green check for the
// grammar coach, on a blue gradient. iOS rounds the corners itself.
// Only CoreGraphics and CoreText are used (no AppKit), so it runs fine from a terminal.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

// RGB without alpha: iOS rejects icons with transparency.
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let full = CGRect(x: 0, y: 0, width: size, height: size)  // origin bottom-left

// Background: blue gradient, lighter at the top.
let background = CGGradient(colorsSpace: space, colors: [color(0x4C7DFF), color(0x1C3AA9)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: full.maxY), end: CGPoint(x: 0, y: 0), options: [])

// Soft glow behind the bubble.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.2), color(0xFFFFFF, alpha: 0)] as CFArray,
                      locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])

// Speech bubble with a tail at the bottom left.
let bubbleRect = CGRect(x: 172, y: 300, width: 680, height: 500)
let bubble = CGMutablePath()
bubble.addRoundedRect(in: bubbleRect, cornerWidth: 150, cornerHeight: 150)
bubble.move(to: CGPoint(x: 300, y: 330))
bubble.addCurve(to: CGPoint(x: 230, y: 190), control1: CGPoint(x: 300, y: 260), control2: CGPoint(x: 270, y: 215))
bubble.addCurve(to: CGPoint(x: 440, y: 310), control1: CGPoint(x: 320, y: 215), control2: CGPoint(x: 400, y: 260))
bubble.closeSubpath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x000000, alpha: 0.28))
context.setFillColor(color(0xFFFFFF))
context.addPath(bubble)
context.fillPath()
context.restoreGState()

// "Aa" in the bubble, in the heavy system font.
let systemFont = CTFontCreateUIFontForLanguage(.system, 330, nil)!
let heavy = [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.62]] as CFDictionary
let font = CTFontCreateWithFontDescriptor(
    CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(systemFont), heavy), 330, nil)
let text = NSAttributedString(string: "Aa", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0x1C3AA9),
    NSAttributedString.Key(kCTKernAttributeName as String): -8,
])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(x: bubbleRect.midX - bounds.width / 2 - bounds.minX - 30,
                               y: bubbleRect.midY - bounds.height / 2 - bounds.minY)
CTLineDraw(line, context)

// Green check badge on the bubble's top-right corner: the grammar coach.
let badge = CGRect(x: 650, y: 610, width: 250, height: 250)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.25))
context.setFillColor(color(0x2BC46B))
context.fillEllipse(in: badge)
context.restoreGState()
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(34)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: badge.minX + 68, y: badge.midY + 2))
context.addLine(to: CGPoint(x: badge.minX + 112, y: badge.midY - 44))
context.addLine(to: CGPoint(x: badge.maxX - 62, y: badge.midY + 54))
context.strokePath()

let image = context.makeImage()!
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path)")
