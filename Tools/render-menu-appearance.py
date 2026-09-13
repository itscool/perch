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
    page = 'struct MenuAppearancePage: View {' + appearance.split('struct MenuAppearancePage: View {')[1].split('final class MenuAppearancePreviewHost: NSView {')[0]
    representable = 'struct MenuAppearancePreview: NSViewRepresentable {' + appearance.split('struct MenuAppearancePreview: NSViewRepresentable {')[1].split('\nextension AppDelegate {')[0]
    toggle = 'struct AppearanceMixedToggle: NSViewRepresentable {' + appearance.split('struct AppearanceMixedToggle: NSViewRepresentable {')[1]
    stub = '\nfinal class SettingsWindow { enum Reset { case appearance }; static let shared = SettingsWindow(); func navigateToReset(_ reset: Reset) {} }\n'
    (root/'Drawing.swift').write_text(model + '\n' + row + '\nfinal class MenuAppearancePreviewHost: NSView {' + preview + '\n' + page + '\n' + representable + '\n' + toggle + stub)
    (root/'main.swift').write_text(r'''
import AppKit
import SwiftUI

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
struct AppError: Error { let message: String }
try runMenuAppearanceTests()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let suite = "perch.appearance.layout." + UUID().uuidString
let fixtureDefaults = UserDefaults(suiteName: suite)!
defer { fixtureDefaults.removePersistentDomain(forName: suite) }
let fixture = MenuAppearanceStore(defaults: fixtureDefaults)
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
var starts: [[String: CGFloat]] = []
for width in [640.0, 900.0] {
    let host = NSHostingView(rootView: MenuAppearancePage(store: fixture))
    host.frame = CGRect(x: 0, y: 0, width: width, height: 1100); host.layoutSubtreeIfNeeded()
    // Resolve lazily created native controls using offscreen drawing only.
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if width == 640, let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output.appendingPathComponent("perch-appearance-controls.png")) }
    }
    var positions: [String: CGFloat] = [:]
    for button in descendants(host).compactMap({ $0 as? NSButton }) where ["Left", "Right", "Top", "Bottom", "Fade left", "Fade right"].contains(button.title) {
        positions[button.title] = button.convert(button.bounds, to: host).minX
    }
    let sliders = descendants(host).compactMap { $0 as? NSSlider }
    precondition(sliders.count == 8, "Expected the eight appearance sliders, found \(sliders.count)")
    if let slider = sliders.dropFirst(5).first {
        positions["Title tint"] = slider.convert(slider.bounds, to: host).minX
    }
    precondition(positions.count == 7, "Appearance layout fixture missed a target control: \(positions)")
    starts.append(positions)
}
for key in starts[0].keys { precondition(abs(starts[0][key]! - starts[1][key]!) < 1, "Control drifts while resizing: " + key) }
print("PASS: border/fade checkbox and title-tint slider starts stay anchored at 640 and 900 points")

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
func menu(_ value: MenuAppearance, dark: Bool, x: CGFloat, y: CGFloat, system: Bool = false) {
    let view = MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 245, height: 214))
    view.value = value; view.dark = dark; view.system = system; view.layout()
    NSGraphicsContext.saveGraphicsState()
    let offset = NSAffineTransform(); offset.translateX(by: x, yBy: y); offset.concat()
    NSBezierPath(roundedRect: view.bounds, xRadius: 8, yRadius: 8).addClip()
    view.draw(view.bounds)
    for row in view.rows where !row.isHidden {
        NSGraphicsContext.saveGraphicsState()
        let position = NSAffineTransform(); position.translateX(by: row.frame.minX, yBy: row.frame.minY); position.concat()
        row.bounds.clip(); row.draw(row.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}
// Selection changes the content focus without changing the saved appearance.
for preset in MenuAppearancePreset.builtIns {
    for dark in [false, true] {
        let view = MenuAppearancePreviewHost(frame: NSRect(x: 0, y: 0, width: 245, height: 210))
        view.value = preset.appearance; view.dark = dark
        view.system = true; view.layout()
        let readings = view.rows.filter { $0.panelSection == "System" && $0.kind == .information }
        precondition(readings.count == 5 && readings.allSatisfy { !$0.isHidden }, "System focus omitted a reading")
        precondition(view.rows.contains { !$0.isHidden && $0.panelSection == "Agent Kill Switch" }, "Missing neighboring color transition")
        view.system = false; view.layout()
        let visible = view.rows.filter { !$0.isHidden }
        precondition(visible.filter { $0.panelSection == "System" }.count == 1)
        precondition(visible.first?.panelSection == "System" && visible.first?.panelPart == .bottom)
        precondition(visible.contains { $0.panelSection == "Audio" }, "Colored preview lost real section order")
        precondition(visible.allSatisfy { view.menuRect.contains($0.frame) }, "Preview row escapes menu surface")
        precondition(view.value == preset.appearance, "Preview focus altered appearance")
    }
}
var edge = MenuSectionAppearance()
let originalSides = edge.sides
edge.edgeToEdge = true
precondition(edge.decorationMargin == 0 && edge.drawnSides == [.top, .bottom] && edge.decorationRadius == 0)
let edgeDecoded = try JSONDecoder().decode(MenuSectionAppearance.self, from: JSONEncoder().encode(edge))
precondition(edgeDecoded.isEdgeToEdge && edgeDecoded.sides == originalSides)
edge.edgeToEdge = false
precondition(edge.drawnSides == originalSides && edge.decorationMargin == 4 && edge.decorationRadius == 2.5)
var edgePair = MenuAppearance()
edgePair.editSection(dark: false, both: true, system: false) { $0.edgeToEdge = true }
precondition(edgePair.theme(dark: false).sections.isEdgeToEdge && edgePair.theme(dark: true).sections.isEdgeToEdge && !edgePair.system.isEdgeToEdge)
let presets = MenuAppearancePreset.builtIns
precondition(presets.count == 7 && presets.allSatisfy { $0.appearance.valid })
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
let descriptions = ["Original title frames", "Type only · no decorations", "Strong vertical accents", "Rounded, filled sections", "Clear interiors · full frames", "Fading title bands · paired rules", "Greyscale fills · overlines · fading right edge"]
try export("perch-preset-studies.png", width: 1080, height: 1198) {
    label("Perch · Appearance presets", x: 28, y: 1155, size: 23, bold: true)
    label("System transition + first three colored sections · Light and Dark", x: 28, y: 1129)
    for (index, preset) in presets.enumerated() {
        let x = CGFloat(index % 2) * 532 + 24
        let y = 843 - CGFloat(index / 2) * 278
        label(preset.name, x: x, y: y + 243, size: 17, bold: true)
        label(descriptions[index], x: x, y: y + 223, size: 12)
        menu(preset.appearance, dark: false, x: x, y: y)
        menu(preset.appearance, dark: true, x: x + 253, y: y)
    }
}
try export("perch-edge-fades.png", width: 1080, height: 635) {
    label("Perch · Edge-to-edge treatments", x: 28, y: 592, size: 23, bold: true)
    label("Independent left/right fades · Production menu renderer · Light and Dark", x: 28, y: 566)
    for (index, flags) in [(false, false), (true, false), (false, true), (true, true)].enumerated() {
        var value = presets.first { $0.name == "Ribbon" }!.appearance
        value.editSection(dark: false, both: true, system: false) {
            $0.edgeToEdge = true; $0.fadeLeft = flags.0; $0.fadeRight = flags.1
            $0.backgroundIntensity = 0.20; $0.borderIntensity = 0.8
        }
        let x = CGFloat(index % 2) * 532 + 24, y = 292 - CGFloat(index / 2) * 270
        label(["No fade", "Fade left", "Fade right", "Fade both"][index], x: x, y: y + 228, size: 17, bold: true)
        menu(value, dark: false, x: x, y: y); menu(value, dark: true, x: x + 253, y: y)
    }
}
try export("perch-preview-focus.png", width: 560, height: 574) {
    label("Menu previews · Focus and dropdown edges", x: 24, y: 539, size: 20, bold: true)
    for (index, system) in [false, true].enumerated() {
        let y = 280 - CGFloat(index) * 250
        label(system ? "Editing System" : "Editing colored sections", x: 24, y: y + 224, size: 15, bold: true)
        menu(presets.first!.appearance, dark: false, x: 24, y: y, system: system)
        menu(presets.first!.appearance, dark: true, x: 287, y: y, system: system)
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
print("PASS: seven valid/stable presets, unchanged Perch original, eight round-trip palettes; images rendered without windows or live state")
''')
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', str(root/'Drawing.swift'), str(repo/'Sources/StatusColors.swift'), str(repo/'Sources/PerchVersion.swift'), str(repo/'Sources/DeskCanvasLayout.swift'), str(repo/'Sources/MenuAppearanceTests.swift'), str(root/'main.swift'), '-o', str(root/'render')], check=True)
    subprocess.run([str(root/'render'), str(output)], check=True)
