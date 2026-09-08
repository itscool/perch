import Foundation

/// Registration reads registry metadata, independently of the HID input client.
/// Conformance/element queries through that client can return no elements when
/// input access is unavailable, even though the registry describes the keyboard.
enum NavigationKeyboardMetadata {
    static func identity(_ properties: [String: Any], ancestorBuiltIn: Bool? = nil) -> NavigationKeyboardIdentity? {
        let pairs = properties["DeviceUsagePairs"] as? [[String: Any]] ?? []
        let keyboard = pairs.contains { ($0["DeviceUsagePage"] as? NSNumber)?.intValue == 1 && ($0["DeviceUsage"] as? NSNumber)?.intValue == 6 }
            || ((properties["PrimaryUsagePage"] as? NSNumber)?.intValue == 1 && (properties["PrimaryUsage"] as? NSNumber)?.intValue == 6)
        let builtIn = (properties["Built-In"] as? NSNumber)?.boolValue ?? ancestorBuiltIn
        let transport = properties["Transport"] as? String ?? ""
        guard keyboard, NavigationDeviceScope.isExternal(builtIn: builtIn, transport: transport) else { return nil }
        func number(_ key: String) -> Int { (properties[key] as? NSNumber)?.intValue ?? 0 }
        return .init(vendor: number("VendorID"), product: number("ProductID"), version: number("VersionNumber"),
                     name: properties["Product"] as? String ?? "External keyboard", transport: transport,
                     usages: usages(properties["Elements"]) ?? [])
    }

    static func usages(_ object: Any?) -> [UInt32]? {
        guard let elements = object as? [[String: Any]] else { return nil }
        var result = Set<UInt32>(), remaining = 4096
        func visit(_ elements: [[String: Any]], depth: Int, keyboard: Bool) -> Bool {
            guard depth <= 16, elements.count <= remaining else { return false }
            remaining -= elements.count
            for element in elements {
                let page = (element["UsagePage"] as? NSNumber)?.intValue
                let usage = (element["Usage"] as? NSNumber)?.int64Value
                let type = (element["Type"] as? NSNumber)?.intValue
                let inKeyboard = keyboard || (type == 513 && page == 1 && usage == 6)
                if inKeyboard, page == 7, let type, (1...4).contains(type), let usage,
                   usage >= 0, usage <= Int64(UInt32.max), NavigationLearning.allowed(UInt32(usage)) {
                    result.insert(UInt32(usage))
                }
                if let children = element["Elements"] {
                    guard let children = children as? [[String: Any]], visit(children, depth: depth + 1, keyboard: inKeyboard) else { return false }
                }
            }
            return true
        }
        return visit(elements, depth: 0, keyboard: false) ? result.sorted() : nil
    }
}
