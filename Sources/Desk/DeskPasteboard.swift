import AppKit

/// A real pasteboard behind `DeskPasteboardStore`.
///
/// Production passes the general pasteboard. Tests pass a uniquely named
/// private one and release it afterwards: the general pasteboard holds what the
/// person copied, which may be a password, and writing it would replace it.
///
/// Called only on `DeskPasteboardAccess`'s own serial queue. AppKit's pasteboard
/// is a client of the system pasteboard service and is used off the main thread
/// here deliberately, so that an app that is slow to hand over its copy never
/// stalls the thread carrying the desk.
final class SystemDeskPasteboard: DeskPasteboardStore {
    let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    func itemTypes() -> [[String]] { (pasteboard.pasteboardItems ?? []).map { $0.types.map(\.rawValue) } }
    func data(item: Int, type: String) -> Data? {
        guard let items = pasteboard.pasteboardItems, items.indices.contains(item) else { return nil }
        return items[item].data(forType: NSPasteboard.PasteboardType(type))
    }
    /// Writes ordinary data only, never a promise: a data promise would be
    /// answered on Perch's main thread while the pasting app waited. Received
    /// files go on as their file URLs in Downloads; see `DeskClipboard`.
    func replace(with items: [[(type: String, data: Data)]]) -> Int {
        let written = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in representations { item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type)) }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(written)
        return pasteboard.changeCount
    }
}

