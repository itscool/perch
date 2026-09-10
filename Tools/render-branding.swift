import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func render(_ name: String, width: Int, height: Int, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(); NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}
func bird() {
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 225, y: 425))
    body.curve(to: NSPoint(x: 633, y: 660), controlPoint1: NSPoint(x: 345, y: 390), controlPoint2: NSPoint(x: 500, y: 620))
    body.curve(to: NSPoint(x: 795, y: 550), controlPoint1: NSPoint(x: 765, y: 765), controlPoint2: NSPoint(x: 855, y: 670))
    body.line(to: NSPoint(x: 868, y: 508)); body.line(to: NSPoint(x: 758, y: 493))
    body.curve(to: NSPoint(x: 357, y: 316), controlPoint1: NSPoint(x: 690, y: 313), controlPoint2: NSPoint(x: 515, y: 279))
    body.line(to: NSPoint(x: 174, y: 278)); body.close()
    NSColor.white.setFill(); body.fill()
    let wing = NSBezierPath()
    wing.move(to: NSPoint(x: 365, y: 455)); wing.curve(to: NSPoint(x: 653, y: 524), controlPoint1: NSPoint(x: 455, y: 490), controlPoint2: NSPoint(x: 567, y: 535))
    wing.curve(to: NSPoint(x: 365, y: 455), controlPoint1: NSPoint(x: 579, y: 387), controlPoint2: NSPoint(x: 452, y: 365)); wing.close()
    NSColor(calibratedRed: 0.0, green: 0.47, blue: 0.53, alpha: 1).setFill(); wing.fill()
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 727, y: 589, width: 19, height: 19)).fill()
    let perch = NSBezierPath(); perch.move(to: NSPoint(x: 280, y: 237)); perch.line(to: NSPoint(x: 750, y: 237)); perch.lineWidth = 20; perch.lineCapStyle = .round; NSColor.white.withAlphaComponent(0.7).setStroke(); perch.stroke()
}
try render("icon.png", width: 1024, height: 1024) {
    let outline = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.76, blue: 0.73, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.26, blue: 0.38, alpha: 1))!.draw(in: outline, angle: -65)
    bird()
}
func text(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (string as NSString).draw(in: NSRect(x: 30, y: y, width: 660, height: size * 2.5), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}
try render("installer.png", width: 720, height: 440) {
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 720, height: 440).fill()
    text("Perch", y: 340, size: 40, weight: .bold, color: NSColor(calibratedRed: 0.03, green: 0.36, blue: 0.41, alpha: 1))
    text("Your Mac, ready for AI work.", y: 302, size: 17, weight: .regular, color: .darkGray)
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 330, y: 200)); arrow.line(to: NSPoint(x: 390, y: 200)); arrow.move(to: NSPoint(x: 375, y: 215)); arrow.line(to: NSPoint(x: 390, y: 200)); arrow.line(to: NSPoint(x: 375, y: 185)); arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.0, green: 0.55, blue: 0.59, alpha: 1).setStroke(); arrow.stroke()
    text("Drag Perch into Applications, then open it to get started.", y: 54, size: 15, weight: .medium, color: .darkGray)
    text("Apple silicon · macOS 26 or later", y: 10, size: 12, weight: .regular, color: .gray)
}
let iconset = destination.appendingPathComponent("Perch.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-z", String(point*scale), String(point*scale), destination.appendingPathComponent("icon.png").path, "--out", iconset.appendingPathComponent("icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png").path]
        process.standardOutput = FileHandle.nullDevice; try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { exit(1) }
    }
}
let iconutil = Process(); iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); iconutil.arguments = ["-c", "icns", iconset.path, "-o", destination.appendingPathComponent("Perch.icns").path]; try iconutil.run(); iconutil.waitUntilExit(); exit(iconutil.terminationStatus)
