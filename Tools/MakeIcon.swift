import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.dropFirst().first ?? "SparklePromptIcon.png"
let s: Int = 1024
let sf = CGFloat(s)

let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: s,
    height: s,
    bitsPerComponent: 8,
    bytesPerRow: s * 4,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

// Utilities
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// macOS Squircle Bounds
let bounds = CGRect(x: 0, y: 0, width: sf, height: sf)
let corner = sf * 0.225

func addSquirclePath(in rect: CGRect, cornerRadius: CGFloat) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
}

// MARK: - 1. Base Shape & Clip
addSquirclePath(in: bounds, cornerRadius: corner)
ctx.clip()

// MARK: - 2. Backplate (Deep Cosmic / AI Gradient)
// Rich violet to deep midnight blue
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.24, 0.12, 0.45, 1.0), // Top-left: vibrant violet
    color(0.10, 0.08, 0.20, 1.0), // Center
    color(0.04, 0.04, 0.08, 1.0)  // Bottom-right: deep dark
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: sf), end: CGPoint(x: sf, y: 0), options: [])

// Background mesh / texture (faint lines to simulate script text)
ctx.setBlendMode(.screen)
let linesCount = 10
for i in 0..<linesCount {
    let y = sf * (0.85 - CGFloat(i) * 0.07)
    let w = sf * CGFloat.random(in: 0.3...0.5)
    let alpha = CGFloat(0.05 + 0.1 * (1.0 - abs(y/sf - 0.5)*2)) // Brighter in middle

    ctx.setFillColor(color(1, 1, 1, alpha))
    let rect = CGRect(x: sf*0.25, y: y, width: w, height: sf*0.015)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: sf*0.0075, cornerHeight: sf*0.0075, transform: nil))
    ctx.fillPath()
}
ctx.setBlendMode(.normal)

// MARK: - 3. The "Teleprompter Glass" Lens
// An inner rounded rectangle representing the beam splitter glass.
let glassInset = sf * 0.08
let glassRect = bounds.insetBy(dx: glassInset, dy: glassInset)
let glassCorner = corner * 0.8

ctx.saveGState()
// Outer shadow of the glass
ctx.setShadow(offset: CGSize(width: 0, height: -sf * 0.04), blur: sf * 0.06, color: color(0, 0, 0, 0.6))
addSquirclePath(in: glassRect, cornerRadius: glassCorner)
ctx.setFillColor(color(0.08, 0.06, 0.15, 0.5)) // Dark, semi-transparent base
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
addSquirclePath(in: glassRect, cornerRadius: glassCorner)
ctx.clip()

// Glass diagonal reflection (The classic iOS/macOS glossy diagonal)
let reflectGrad = CGGradient(colorsSpace: cs, colors: [
    color(1, 1, 1, 0.25),
    color(1, 1, 1, 0.02),
    color(1, 1, 1, 0.0)
] as CFArray, locations: [0, 0.49, 0.5])!
ctx.drawLinearGradient(reflectGrad, start: CGPoint(x: glassRect.minX, y: glassRect.maxY), end: CGPoint(x: glassRect.maxX, y: glassRect.minY), options: [])

// Glowing bottom edge of the glass (representing the teleprompter screen reflecting upwards)
let glowGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.5, 0.2, 1.0, 0.0),
    color(0.5, 0.2, 1.0, 0.35)
] as CFArray, locations: [0.6, 1.0])!
ctx.drawLinearGradient(glowGrad, start: CGPoint(x: sf*0.5, y: sf*0.5), end: CGPoint(x: sf*0.5, y: glassRect.minY), options: [])

// Inner bevel of the glass
ctx.setStrokeColor(color(1, 1, 1, 0.3))
ctx.setLineWidth(sf * 0.004)
addSquirclePath(in: glassRect.insetBy(dx: sf*0.002, dy: sf*0.002), cornerRadius: glassCorner)
ctx.strokePath()

ctx.setStrokeColor(color(0, 0, 0, 0.5))
addSquirclePath(in: glassRect.insetBy(dx: -sf*0.002, dy: -sf*0.002), cornerRadius: glassCorner)
ctx.strokePath()

ctx.restoreGState()

// MARK: - 4. Central "Sparkle" Icon
// A geometric, 4-pointed star (like the Apple Intelligence / AI Sparkle)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -sf * 0.02), blur: sf * 0.05, color: color(0, 0, 0, 0.7))

let cx = sf * 0.5
let cy = sf * 0.5
let rOuter = sf * 0.28
let rInner = sf * 0.07

let starPath = CGMutablePath()
starPath.move(to: CGPoint(x: cx, y: cy + rOuter)) // Top
starPath.addQuadCurve(to: CGPoint(x: cx + rOuter, y: cy), control: CGPoint(x: cx + rInner, y: cy + rInner)) // Top to Right
starPath.addQuadCurve(to: CGPoint(x: cx, y: cy - rOuter), control: CGPoint(x: cx + rInner, y: cy - rInner)) // Right to Bottom
starPath.addQuadCurve(to: CGPoint(x: cx - rOuter, y: cy), control: CGPoint(x: cx - rInner, y: cy - rInner)) // Bottom to Left
starPath.addQuadCurve(to: CGPoint(x: cx, y: cy + rOuter), control: CGPoint(x: cx - rInner, y: cy + rInner)) // Left to Top
starPath.closeSubpath()

// Vibrant, glowing gradient for the star
let starGrad = CGGradient(colorsSpace: cs, colors: [
    color(1.0, 0.95, 0.7, 1.0), // Golden/White top
    color(1.0, 0.35, 0.7, 1.0), // Magenta middle
    color(0.40, 0.15, 0.9, 1.0) // Deep purple bottom
] as CFArray, locations: [0, 0.45, 1])!

ctx.saveGState()
ctx.addPath(starPath)
ctx.clip()
ctx.drawLinearGradient(starGrad, start: CGPoint(x: cx - rOuter, y: cy + rOuter), end: CGPoint(x: cx + rOuter, y: cy - rOuter), options: [])
ctx.restoreGState()

// Star inner highlight (glossy physical rim)
ctx.setStrokeColor(color(1, 1, 1, 0.7))
ctx.setLineWidth(sf * 0.012)
ctx.addPath(starPath)
ctx.strokePath()

ctx.restoreGState() // End drop shadow

// Center glowing aura
ctx.saveGState()
ctx.setBlendMode(.screen)
let aura = CGGradient(colorsSpace: cs, colors: [
    color(1.0, 0.4, 0.8, 0.5),
    color(1.0, 0.4, 0.8, 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(aura, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: sf * 0.4, options: [])
ctx.restoreGState()

// MARK: - 5. Secondary Sparkles (Constellation effect)
func drawSimpleStar(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: CGFloat) {
    let sPath = CGMutablePath()
    let rIn = radius * 0.25
    sPath.move(to: CGPoint(x: x, y: y + radius))
    sPath.addQuadCurve(to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x + rIn, y: y + rIn))
    sPath.addQuadCurve(to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x + rIn, y: y - rIn))
    sPath.addQuadCurve(to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x - rIn, y: y - rIn))
    sPath.addQuadCurve(to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x - rIn, y: y + rIn))
    sPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: radius * 0.5, color: color(1, 1, 1, 0.8))
    ctx.setFillColor(color(1, 1, 1, opacity))
    ctx.addPath(sPath)
    ctx.fillPath()
    ctx.restoreGState()
}

drawSimpleStar(x: cx + sf * 0.28, y: cy + sf * 0.28, radius: sf * 0.07, opacity: 0.95)
drawSimpleStar(x: cx - sf * 0.25, y: cy - sf * 0.18, radius: sf * 0.045, opacity: 0.8)

// MARK: - 6. macOS Edge Lighting (Physical Bevel)
// The HIG defines a very specific edge light/shadow for macOS icons.

// Top Edge Highlight (White, fades out downwards)
ctx.saveGState()
addSquirclePath(in: bounds.insetBy(dx: sf*0.015, dy: sf*0.015), cornerRadius: corner * 0.95)
ctx.clip()
let topHighlight = CGGradient(colorsSpace: cs, colors: [
    color(1, 1, 1, 0.45),
    color(1, 1, 1, 0.0)
] as CFArray, locations: [0, 0.15])!
ctx.drawLinearGradient(topHighlight, start: CGPoint(x: 0, y: sf), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Bottom Edge Shadow (Black, fades out upwards)
ctx.saveGState()
addSquirclePath(in: bounds.insetBy(dx: sf*0.015, dy: sf*0.015), cornerRadius: corner * 0.95)
ctx.clip()
let botShadow = CGGradient(colorsSpace: cs, colors: [
    color(0, 0, 0, 0.6),
    color(0, 0, 0, 0.0)
] as CFArray, locations: [0, 0.15])!
ctx.drawLinearGradient(botShadow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: sf), options: [])
ctx.restoreGState()

// Dark Outer Border (0.5pt to 1pt depending on scale, gives crisp edge on light backgrounds)
ctx.setStrokeColor(color(0, 0, 0, 0.4))
ctx.setLineWidth(sf * 0.01)
addSquirclePath(in: bounds.insetBy(dx: sf*0.005, dy: sf*0.005), cornerRadius: corner * 0.98)
ctx.strokePath()

// Fine Bright Inner Border
ctx.setStrokeColor(color(1, 1, 1, 0.25))
ctx.setLineWidth(sf * 0.005)
addSquirclePath(in: bounds.insetBy(dx: sf*0.015, dy: sf*0.015), cornerRadius: corner * 0.95)
ctx.strokePath()

// MARK: - Export
guard let cgImage = ctx.makeImage() else { exit(1) }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
