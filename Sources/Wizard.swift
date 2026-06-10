import AppKit

// MARK: - One branch picker: [local | origin | ...] + search + list

final class BranchPicker: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let workingTree = "« Working Tree »"

    struct Group {
        let name: String
        let branches: [String]
    }

    private let groups: [Group]
    private let segmented: NSSegmentedControl
    private let search = NSSearchField()
    private let table = NSTableView()
    private var filtered: [String] = []
    private(set) var selected: String?
    var onSelectionChanged: (() -> Void)?

    init(title: String, groups: [Group]) {
        self.groups = groups
        self.segmented = NSSegmentedControl(labels: groups.map { $0.name },
                                            trackingMode: .selectOne,
                                            target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        segmented.target = self
        segmented.action = #selector(segmentChanged)
        if !groups.isEmpty { segmented.selectedSegment = 0 }

        search.placeholderString = "Filter branches…"
        search.delegate = self
        search.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch"))
        column.minWidth = 100
        column.maxWidth = 100_000
        table.addTableColumn(column)
        table.headerView = nil
        if #available(macOS 11.0, *) { table.style = .fullWidth }
        table.rowHeight = 22
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let stack = NSStackView(views: [titleLabel, segmented, search, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            segmented.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            search.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        refilter()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Select a branch by name, switching to whichever group contains it.
    func preselect(_ name: String) {
        for (gi, group) in groups.enumerated() where group.branches.contains(name) {
            segmented.selectedSegment = gi
            refilter()
            if let row = filtered.firstIndex(of: name) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                table.scrollRowToVisible(row)
            }
            return
        }
    }

    @objc private func segmentChanged() {
        search.stringValue = ""
        refilter()
    }

    func controlTextDidChange(_ obj: Notification) {
        refilter()
    }

    private func refilter() {
        let gi = max(0, segmented.selectedSegment)
        let base = groups.isEmpty ? [] : groups[gi].branches
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty
            ? base
            : base.filter { $0.range(of: query, options: .caseInsensitive) != nil }
        table.reloadData()
        // Keep the previous choice if still visible, else pick the top match.
        if let sel = selected, let row = filtered.firstIndex(of: sel) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !filtered.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            selected = nil
            onSelectionChanged?()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("BranchCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = filtered[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selected = table.selectedRow >= 0 ? filtered[table.selectedRow] : nil
        onSelectionChanged?()
    }
}

// MARK: - Wizard window

final class WizardWindowController: NSWindowController {
    private let git: Git
    private let paths: [String]
    private let onConfirm: (DiffSession) -> Void
    private let sourcePicker: BranchPicker
    private let targetPicker: BranchPicker
    private let showButton = NSButton(title: "Show Diff", target: nil, action: nil)

    init(git: Git, paths: [String], onConfirm: @escaping (DiffSession) -> Void) {
        self.git = git
        self.paths = paths
        self.onConfirm = onConfirm

        let locals = git.localBranches()
        var sourceGroups = [BranchPicker.Group(name: "local",
                                               branches: [BranchPicker.workingTree] + locals)]
        var targetGroups = [BranchPicker.Group(name: "local", branches: locals)]
        for remote in git.remotes() {
            let branches = git.remoteBranches(remote)
            sourceGroups.append(BranchPicker.Group(name: remote, branches: branches))
            targetGroups.append(BranchPicker.Group(name: remote, branches: branches))
        }

        sourcePicker = BranchPicker(title: "Branch with diffs", groups: sourceGroups)
        targetPicker = BranchPicker(title: "Target branch", groups: targetGroups)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "diffy — Compare Branches"

        super.init(window: window)

        let cancelButton = NSButton(title: "Cancel", target: nil,
                                    action: #selector(NSWindow.performClose(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        showButton.target = self
        showButton.action = #selector(confirm)
        showButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [NSView(), cancelButton, showButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [sourcePicker, targetPicker, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = BackgroundView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sourcePicker.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            targetPicker.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
        window.setContentSize(NSSize(width: 480, height: 580))
        window.center()

        // Sensible defaults: current branch vs main/master/develop.
        let current = git.currentBranch()
        if let current = current {
            sourcePicker.preselect(current)
        } else {
            sourcePicker.preselect(BranchPicker.workingTree)
        }
        let locals2 = git.localBranches()
        if let target = ["main", "master", "develop"].first(where: {
            locals2.contains($0) && $0 != current
        }) ?? locals2.first(where: { $0 != current }) {
            targetPicker.preselect(target)
        }

        let updateEnabled = { [weak self] in
            guard let self = self else { return }
            self.showButton.isEnabled =
                self.sourcePicker.selected != nil && self.targetPicker.selected != nil
        }
        sourcePicker.onSelectionChanged = updateEnabled
        targetPicker.onSelectionChanged = updateEnabled
        updateEnabled()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func confirm() {
        guard let source = sourcePicker.selected, let target = targetPicker.selected else { return }
        let refs = source == BranchPicker.workingTree ? [target] : [target, source]
        do {
            let session = try DiffSession(cwd: git.repoRoot, refs: refs, paths: paths)
            if session.files.isEmpty {
                let alert = NSAlert()
                alert.messageText = "No differences"
                alert.informativeText = "\(session.leftLabel) and \(session.rightLabel) are identical."
                alert.runModal()
                return
            }
            onConfirm(session)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cannot compare"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }
}
