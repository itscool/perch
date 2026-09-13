#!/usr/bin/env python3
"""Render production appearance styles offscreen; no windows, input or live settings.

Compile only model/drawing declarations, excluding AppDelegate and Settings pages.
The process cannot launch the app, run helpers, or present a window.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='perch-appearance-render-') as temp:
    root = Path(temp)
    appearance = (repo/'Sources/MenuAppearance.swift').read_text()
    row = (repo/'Sources/MenuRowView.swift').read_text().split('\nextension AppDelegate {')[0]
    model = appearance.split('\nstruct MenuAppearancePage: View {')[0]
    preview = appearance.split('final class MenuAppearancePreviewHost: NSView {')[1].split('\nstruct MenuAppearancePreview: NSViewRepresentable {')[0]
    (root/'Drawing.swift').write_text(model + '\n' + row + '\nfinal class MenuAppearancePreviewHost: NSView {' + preview)
    (root/'main.swift').write_text(r'''
import AppKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let output = URL(fileURLWithPath: CommandLine.arguments[1])
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 13, bold: Bool = false) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: NSColor(white: 0.16, alpha: 1)])
}
func export(_ name: String, width: CGFloat, height: CGFloat, draw: () -> Void) throws {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(white: 0.94, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
func menu(_ value: MenuAppearance, dark: Bool, x: CGFloat, y: CGFloat) {
    let view = MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 245, height: 214))
    view.value = value; view.dark = dark; view.layout()
    NSGraphicsContext.saveGraphicsState()
    let offset = NSAffineTransform(); offset.translateX(by: x, yBy: y); offset.concat()
    (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.98, alpha: 1)).setFill()
    NSBezierPath(roundedRect: view.bounds, xRadius: 10, yRadius: 10).fill()
    view.bounds.clip()
    for row in view.rows where !row.isHidden {
        NSGraphicsContext.saveGraphicsState()
        let position = NSAffineTransform(); position.translateX(by: row.frame.minX, yBy: row.frame.minY); position.concat()
        row.bounds.clip(); row.draw(row.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}
let presets = MenuAppearancePreset.builtIns
precondition(presets.count == 6 && presets.allSatisfy { $0.appearance.valid })
precondition(presets.first!.appearance == MenuAppearance(), "Perch original changed")
precondition(Set(presets.map(\.id)).count == presets.count)
precondition(MenuAppearancePreset.builtIns.map(\.id) == presets.map(\.id), "Preset identities change on reread")
for palette in MenuPalette.allCases {
    precondition(palette.swatches.count == MenuPalette.sections.count)
    let encoded = try JSONEncoder().encode(palette)
    let decoded = try JSONDecoder().decode(MenuPalette.self, from: encoded)
    precondition(decoded == palette)
}
func composite(_ color: NSColor, over background: [Double]) -> [Double] {
    let rgb = color.usingColorSpace(.sRGB)!
    let alpha = Double(rgb.alphaComponent)
    return zip([Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)], background).map { $0 * alpha + $1 * (1 - alpha) }
}
func luminance(_ rgb: [Double]) -> Double {
    let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
}
var minimum = Double.infinity
for preset in presets {
    for dark in [false, true] {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            for name in MenuPalette.sections {
                let theme = preset.appearance.theme(dark: dark), style = theme.style(name)
                if style.showTitle == false { continue }
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                let row = MenuRowView(item: item, kind: .section)
                row.appearance = appearance; row.appearanceOverride = preset.appearance; row.panelSection = name
                var background = Array(repeating: dark ? 0.13 : 0.98, count: 3)
                if style.backgroundScope != .none {
                    let color = style.greyBackground ? NSColor(white: style.greyLevel, alpha: 1) : theme.palette.color(name)
                    background = composite(color.withAlphaComponent(style.backgroundIntensity), over: background)
                }
                let color = row.displayedText().attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
                let a = luminance(composite(color, over: background)), b = luminance(background)
                let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                if preset.name == "Perch original" {
                    if ratio < 4.5 { print("Preserved original: \(name), dark=\(dark), contrast \(ratio):1") }
                } else { precondition(ratio >= 4.5, "New preset title contrast: \(preset.name), \(name), dark=\(dark), \(ratio)") }
                minimum = min(minimum, ratio)
            }
        }
    }
}
print(String(format: "Measured title contrast %.2f:1 minimum across Light/Dark and all sections", minimum))
let descriptions = ["Original title frames", "Type only · no decorations", "Strong vertical accents", "Rounded, filled sections", "Clear interiors · full frames", "Flat title bands · paired rules"]
try export("perch-preset-studies.png", width: 1080, height: 920) {
    label("Perch · Appearance presets", x: 28, y: 877, size: 23, bold: true)
    label("The same first four menu sections · Light and Dark · Production renderer", x: 28, y: 851)
    for (index, preset) in presets.enumerated() {
        let x = CGFloat(index % 2) * 532 + 24
        let y = 565 - CGFloat(index / 2) * 278
        label(preset.name, x: x, y: y + 243, size: 17, bold: true)
        label(descriptions[index], x: x, y: y + 223, size: 12)
        menu(preset.appearance, dark: false, x: x, y: y)
        menu(preset.appearance, dark: true, x: x + 253, y: y)
    }
}
try export("perch-palette-studies.png", width: 1080, height: 590) {
    label("Perch · Color palettes", x: 28, y: 545, size: 23, bold: true)
    label("Choose any palette independently of the preset. Swatches show all nine section assignments.", x: 28, y: 519)
    for (index, palette) in MenuPalette.allCases.enumerated() {
        let y = 462 - CGFloat(index) * 59
        label(palette.rawValue, x: 30, y: y + 11, size: 15, bold: true)
        for (colorIndex, color) in palette.swatches.enumerated() {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 155 + CGFloat(colorIndex) * 96, y: y, width: 82, height: 38), xRadius: 7, yRadius: 7).fill()
        }
    }
}
precondition(NSApp.windows.isEmpty, "Offscreen render created a window")
print("PASS: six valid/stable presets, unchanged Perch original, eight round-trip palettes; images rendered without windows or live state")
''')
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', str(root/'Drawing.swift'), str(repo/'Sources/StatusColors.swift'), str(repo/'Sources/PerchVersion.swift'), str(root/'main.swift'), '-o', str(root/'render')], check=True)
    subprocess.run([str(root/'render'), str(output)], check=True)
