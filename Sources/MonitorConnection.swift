import AppKit

struct MonitorConnection: Codable, Equatable {
    var kind: String
    var endpoint: String
    var address: Int = 1
    var model: String? = nil
    var valid: Bool {
        ["msi-usb","mccs-usb","nec-lan","nec-serial"].contains(kind) && !endpoint.isEmpty && endpoint.utf8.count <= 256 && (1...26).contains(address) && (model?.utf8.count ?? 0) <= 80
    }
    var argument: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return "route:" + ((try? encoder.encode(self)) ?? Data()).base64EncodedString()
    }
}
struct MonitorUSBDevice: Decodable { let endpoint: String; let kind: String; let name: String }

final class MonitorConnectionView: NSView {
    var selectionChanged: (() -> Void)?
    @objc func updateSelection() { selectionChanged?() }
}
