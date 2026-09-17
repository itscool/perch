import SwiftUI

struct DeskInputSettings: View {
    @ObservedObject var adapter: DeskInputAdapter
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pointer speed")
                Slider(value: $adapter.pointerSpeed, in: 0.25...4, step: 0.05)
                Text(String(format: "%.2f×", adapter.pointerSpeed)).monospacedDigit().frame(width: 55)
            }.help("Saved immediately on this Mac. Scales movement from the mouse or trackpad connected here, so it moves the shared pointer as far as the other Mac’s does.")
            Text("Every keyboard and mouse in the desk controls the one shared pointer. Switching between them, or pressing a device’s computer button, needs no setup.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
