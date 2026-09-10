import AppKit

/// Stable destinations only: tests, confirmations and drafts stay in their
/// owning feature. Selecting a row never performs a setting or system action.
struct SettingsDestination {
    let id: String
    let title: String
    let pageTitles: [String]
    var depth = 0
    let open: () -> Void
}

final class SettingsSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let scroll = NSScrollView()
    let hint = NSTextField(wrappingLabelWithString: "")
    private(set) var destinations: [SettingsDestination] = []
    var choose: ((SettingsDestination) -> Void)?
    private var synchronizing = false
    private var available = true
    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: .init("destination"))
        table.addTableColumn(column); table.headerView = nil
        table.rowHeight = 28; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .sourceList
        table.target = self; table.action = #selector(clickedRow)
        table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Settings categories")
        table.setAccessibilityHelp("Use arrow keys to choose a settings page, then Tab to reach its controls.")
        scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        table.backgroundColor = .clear
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        addSubview(scroll); addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        NSColor.separatorColor.setFill(); NSRect(x: bounds.maxX-1, y: 0, width: 1, height: bounds.height).fill()
    }
    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 8, y: 66, width: bounds.width-16, height: max(0, bounds.height-80))
        hint.frame = NSRect(x: 14, y: 12, width: bounds.width-28, height: 46)
        table.tableColumns.first?.width = scroll.contentSize.width
    }
    func configure(_ destinations: [SettingsDestination]) {
        self.destinations = destinations
        table.reloadData()
    }
    func update(selected id: String?, busy: Bool) {
        available = !busy
        table.isEnabled = !busy
        hint.stringValue = busy ? "Finish or go Back from the current step to switch pages." : "Changes save as you make them. Drafts have an explicit Save."
        synchronizing = true
        if let row = destinations.firstIndex(where: { $0.id == id }) {
            if table.selectedRow != row {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                table.scrollRowToVisible(row)
            }
        } else { table.deselectAll(nil) }
        synchronizing = false
    }
    func numberOfRows(in tableView: NSTableView) -> Int { destinations.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { available }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = destinations[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: 13, weight: item.depth == 0 ? .medium : .regular)
        label.frame = NSRect(x: 8 + CGFloat(item.depth*14), y: 5, width: max(0, tableView.bounds.width-22-CGFloat(item.depth*14)), height: 18)
        label.autoresizingMask = [.width]
        cell.textField = label; cell.addSubview(label)
        cell.setAccessibilityLabel(item.title)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !synchronizing, available, destinations.indices.contains(table.selectedRow) else { return }
        choose?(destinations[table.selectedRow])
    }
    @objc private func clickedRow() {
        // Clicking the already-selected category still returns from its child.
        guard available, destinations.indices.contains(table.clickedRow) else { return }
        choose?(destinations[table.clickedRow])
    }
}
