import AppKit

/// Stable destinations only: tests, confirmations and drafts stay in their
/// owning feature. Selecting a row never performs a setting or system action.
struct SettingsDestination {
    let id: String
    let title: String
    let pageTitles: [String]
    var depth = 0
    var setupStage = false
    let open: () -> Void
}

enum SettingsSetupStatus: String {
    case ready = "Ready", attention = "Needs attention", optional = "Optional", checking = "Checking"
    var symbol: String { switch self { case .ready: "checkmark.circle.fill"; case .attention: "exclamationmark.triangle.fill"; case .optional: "circle"; case .checking: "clock" } }
    var color: NSColor { switch self { case .ready: .systemGreen; case .attention: .systemOrange; case .optional, .checking: .secondaryLabelColor } }
}

/// A source-list cell is narrower than its table and can be resized after
/// construction. Position children from the cell's current bounds, never from
/// the table width plus an autoresizing offset from an initially empty cell.
final class SettingsSidebarCell: NSTableCellView {
    private let depth: Int
    init(item: SettingsDestination) {
        depth = item.depth
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: 13, weight: item.depth == 0 ? .medium : .regular)
        label.lineBreakMode = .byTruncatingTail
        textField = label; addSubview(label)
        setAccessibilityLabel(item.title)
        if item.setupStage {
            let icon = NSImageView()
            imageView = icon; addSubview(icon)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let start = 8 + CGFloat(depth * 14)
        textField?.frame = NSRect(x: start, y: (bounds.height - 18) / 2,
                                 width: max(0, bounds.width - start - 8 - (imageView == nil ? 0 : 22)), height: 18)
        imageView?.frame = NSRect(x: max(0, bounds.width - 23), y: (bounds.height - 14) / 2, width: 14, height: 14)
    }
}

final class SettingsSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let scroll = NSScrollView()
    let hint = NSTextField(wrappingLabelWithString: "")
    private(set) var destinations: [SettingsDestination] = []
    var choose: ((SettingsDestination) -> Void)?
    private var synchronizing = false
    private var available = true
    var readSetupStatus: (() -> [String: SettingsSetupStatus])?
    private(set) var setupStatuses: [String: SettingsSetupStatus] = [:]
    private var statusTimer: Timer?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        statusTimer?.invalidate(); statusTimer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.refreshSetupStatus()
        }
        timer.tolerance = 0.2; statusTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func refreshSetupStatus() {
        guard let values = readSetupStatus?(), values != setupStatuses else { return }
        setupStatuses = values
        // Update visible cells in place: never reload selection or interrupt editing.
        for (row, item) in destinations.enumerated() {
            guard item.setupStage, row < table.numberOfRows, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
            updateStatus(cell, item: item)
        }
    }
    private func updateStatus(_ cell: NSTableCellView, item: SettingsDestination) {
        let state = setupStatuses[item.id] ?? .checking
        cell.imageView?.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.rawValue)
        cell.imageView?.contentTintColor = state.color
        cell.toolTip = item.title + " — " + state.rawValue
        cell.setAccessibilityValue(state.rawValue)
    }
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
        // Source-list style adds horizontal row insets around the column.
        // Fit the document first, then let AppKit budget the column inside it.
        // Assigning viewport width directly to the column overflows the clip view.
        table.setFrameSize(NSSize(width: scroll.contentSize.width, height: table.frame.height))
        table.sizeLastColumnToFit()
    }
    func configure(_ destinations: [SettingsDestination]) {
        self.destinations = destinations
        setupStatuses = readSetupStatus?() ?? [:]
        table.reloadData()
    }
    func update(selected id: String?, busy: Bool) {
        available = !busy
        table.isEnabled = !busy
        hint.stringValue = busy ? "Finish or go Back from the current step to switch pages." : "Changes save automatically. Extra steps are explained on each page."
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
        let cell = SettingsSidebarCell(item: item)
        if item.setupStage { updateStatus(cell, item: item) }
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
