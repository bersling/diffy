import AppKit

// MARK: - Theme

enum Theme {
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let gutterFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    static let charWidth: CGFloat = ("0" as NSString).size(withAttributes: [.font: codeFont]).width
    static let rowHeight: CGFloat = {
        let lm = NSLayoutManager()
        return ceil(lm.defaultLineHeight(for: codeFont)) + 3
    }()

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let addedBG = dynamic(light: NSColor(red: 0.86, green: 0.96, blue: 0.86, alpha: 1),
                                 dark: NSColor(red: 0.21, green: 0.32, blue: 0.21, alpha: 1))
    static let addedHL = dynamic(light: NSColor(red: 0.68, green: 0.90, blue: 0.70, alpha: 1),
                                 dark: NSColor(red: 0.27, green: 0.46, blue: 0.27, alpha: 1))
    static let deletedBG = dynamic(light: NSColor(red: 0.99, green: 0.88, blue: 0.86, alpha: 1),
                                   dark: NSColor(red: 0.37, green: 0.21, blue: 0.21, alpha: 1))
    static let deletedHL = dynamic(light: NSColor(red: 0.97, green: 0.73, blue: 0.70, alpha: 1),
                                   dark: NSColor(red: 0.53, green: 0.26, blue: 0.26, alpha: 1))
    static let modifiedBG = dynamic(light: NSColor(red: 0.85, green: 0.91, blue: 0.98, alpha: 1),
                                    dark: NSColor(red: 0.17, green: 0.26, blue: 0.37, alpha: 1))
    static let modifiedHL = dynamic(light: NSColor(red: 0.67, green: 0.81, blue: 0.96, alpha: 1),
                                    dark: NSColor(red: 0.24, green: 0.40, blue: 0.58, alpha: 1))
    static let placeholderBG = dynamic(light: NSColor(white: 0.93, alpha: 1),
                                       dark: NSColor(white: 0.16, alpha: 1))
    static let gutterBG = dynamic(light: NSColor(white: 0.975, alpha: 1),
                                  dark: NSColor(white: 0.13, alpha: 1))
    static let foldBG = dynamic(light: NSColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1),
                                dark: NSColor(red: 0.15, green: 0.19, blue: 0.26, alpha: 1))
    static let codeBG = dynamic(light: .white, dark: NSColor(white: 0.11, alpha: 1))
    static let accent = NSColor.controlAccentColor

    static func statusColor(_ status: FileStatus) -> NSColor {
        switch status {
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .modified: return .systemBlue
        case .renamed: return .systemPurple
        case .copied: return .systemTeal
        case .typeChanged: return .systemOrange
        }
    }
}

enum PaneSide { case left, right }

/// What a diff pane actually displays: either a real diff row, or a fold bar
/// standing in for a run of hidden unchanged rows.
enum DisplayRow {
    case line(fullIndex: Int, row: DiffRow)
    case fold(range: Range<Int>, count: Int)
}

/// Opaque view that always paints the window background color (appearance-aware).
final class BackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

// MARK: - One line of one pane

final class DiffHalfRowView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("DiffHalfRow")

    var line: DiffLine?
    var kind: RowKind = .context
    var side: PaneSide = .left
    var gutterWidth: CGFloat = 48
    var inCurrentBlock = false

    override var isFlipped: Bool { true }

    func configure(row: DiffRow, side: PaneSide, gutterWidth: CGFloat, inCurrentBlock: Bool) {
        self.line = side == .left ? row.left : row.right
        self.kind = row.kind
        self.side = side
        self.gutterWidth = gutterWidth
        self.inCurrentBlock = inCurrentBlock
        needsDisplay = true
    }

    private var backgroundColor: NSColor {
        guard line != nil else { return Theme.placeholderBG }
        switch kind {
        case .context, .message: return Theme.codeBG
        case .addition: return Theme.addedBG
        case .deletion: return Theme.deletedBG
        case .modification: return Theme.modifiedBG
        }
    }

    private var highlightColor: NSColor {
        switch kind {
        case .addition: return Theme.addedHL
        case .deletion: return Theme.deletedHL
        default: return Theme.modifiedHL
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        let w = bounds.width

        backgroundColor.setFill()
        bounds.fill()

        if kind == .message {
            let text = line?.text ?? ""
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: 16, y: (h - size.height) / 2), withAttributes: attrs)
            return
        }

        // Gutter
        Theme.gutterBG.setFill()
        NSRect(x: 0, y: 0, width: gutterWidth, height: h).fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: gutterWidth - 1, y: 0, width: 1, height: h).fill()

        if inCurrentBlock && kind != .context {
            Theme.accent.setFill()
            NSRect(x: 0, y: 0, width: 2.5, height: h).fill()
        }

        guard let line = line else {
            // Placeholder side: subtle diagonal hatching
            NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            var x: CGFloat = gutterWidth - h
            while x < w {
                path.move(to: NSPoint(x: x, y: h))
                path.line(to: NSPoint(x: x + h, y: 0))
                x += 7
            }
            path.stroke()
            return
        }

        // Line number
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.gutterFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let numStr = "\(line.number)" as NSString
        let numSize = numStr.size(withAttributes: numAttrs)
        numStr.draw(at: NSPoint(x: gutterWidth - 8 - numSize.width, y: (h - numSize.height) / 2),
                    withAttributes: numAttrs)

        let textX = gutterWidth + 8
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.codeFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (line.text as NSString).size(withAttributes: textAttrs)
        let textY = (h - textSize.height) / 2

        // Intra-line changed range
        if let hl = line.highlight, hl.lowerBound <= line.text.count, hl.upperBound <= line.text.count {
            let chars = Array(line.text)
            let prefix = String(chars[0..<hl.lowerBound])
            let middle = String(chars[hl.lowerBound..<hl.upperBound])
            let prefixW = (prefix as NSString).size(withAttributes: [.font: Theme.codeFont]).width
            var middleW = (middle as NSString).size(withAttributes: [.font: Theme.codeFont]).width
            if middle.isEmpty { middleW = Theme.charWidth * 0.6 }
            highlightColor.setFill()
            NSRect(x: textX + prefixW, y: 0.5, width: middleW, height: h - 1).fill()
        }

        (line.text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)
    }
}

// MARK: - Fold bar (collapsed unchanged lines)

final class FoldRowView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("FoldRow")

    private var range: Range<Int> = 0..<0
    private var count = 0
    var onClick: ((Range<Int>) -> Void)?

    override var isFlipped: Bool { true }

    func configure(range: Range<Int>, count: Int) {
        self.range = range
        self.count = count
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.foldBG.setFill()
        bounds.fill()

        let border = NSBezierPath()
        border.lineWidth = 1
        border.setLineDash([3, 3], count: 2, phase: 0)
        border.move(to: NSPoint(x: 0, y: 0.5))
        border.line(to: NSPoint(x: bounds.width, y: 0.5))
        border.move(to: NSPoint(x: 0, y: bounds.height - 0.5))
        border.line(to: NSPoint(x: bounds.width, y: bounds.height - 0.5))
        NSColor.separatorColor.setStroke()
        border.stroke()

        let text = "⋯ \(count) unchanged lines ⋯" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.linkColor,
        ]
        let size = text.size(withAttributes: attrs)
        // Keep the label visible even when the document is much wider than the
        // viewport: center it within the visible portion of the row.
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        text.draw(at: NSPoint(x: visible.midX - size.width / 2,
                              y: (bounds.height - size.height) / 2),
                  withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(range)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - One pane (scroll view + table)

final class DiffPane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let side: PaneSide
    let scrollView = NSScrollView()
    let table = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("code"))

    var rows: [DisplayRow] = []
    var gutterWidth: CGFloat = 48
    var currentBlockRange: Range<Int>?  // in full-row indices
    var onFoldClick: ((Range<Int>) -> Void)?
    weak var partner: DiffPane?
    private var isSyncing = false
    private var contentWidth: CGFloat = 0

    init(side: PaneSide) {
        self.side = side
        super.init()

        column.minWidth = 0
        column.maxWidth = 1_000_000
        table.addTableColumn(column)
        table.headerView = nil
        if #available(macOS 11.0, *) { table.style = .fullWidth }
        table.intercellSpacing = .zero
        table.rowHeight = Theme.rowHeight
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.backgroundColor = Theme.codeBG
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.dataSource = self
        table.delegate = self

        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.codeBG
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged),
                                               name: NSView.frameDidChangeNotification, object: clip)
    }

    func setContent(rows: [DisplayRow], maxColumns: Int, maxLineNumber: Int) {
        self.rows = rows
        currentBlockRange = nil
        let digits = max(2, String(max(maxLineNumber, 1)).count)
        gutterWidth = CGFloat(digits) * Theme.charWidth + 20
        contentWidth = gutterWidth + 8 + CGFloat(maxColumns) * Theme.charWidth + 30
        table.reloadData()
        updateColumnWidth()
        let clip = scrollView.contentView
        clip.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(clip)
    }

    /// Swap the row list without touching the scroll position (used when a
    /// fold is expanded: rows above the fold keep their offsets).
    func updateRows(_ rows: [DisplayRow]) {
        self.rows = rows
        table.reloadData()
    }

    func setCurrentBlock(_ range: Range<Int>?) {
        currentBlockRange = range
        table.enumerateAvailableRowViews { _, row in
            if row >= 0 && row < self.rows.count {
                self.reconfigureRow(row)
            }
        }
    }

    private func reconfigureRow(_ row: Int) {
        guard case .line(let fullIndex, let diffRow) = rows[row],
              let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DiffHalfRowView
        else { return }
        view.configure(row: diffRow, side: side, gutterWidth: gutterWidth,
                       inCurrentBlock: currentBlockRange?.contains(fullIndex) ?? false)
    }

    private func updateColumnWidth() {
        let visible = scrollView.contentView.bounds.width
        column.width = max(contentWidth, visible)
    }

    func scrollToRow(_ row: Int, animated: Bool) {
        guard row >= 0 && row < rows.count else { return }
        let clip = scrollView.contentView
        let rowRect = table.rect(ofRow: row)
        var target = rowRect.midY - clip.bounds.height / 2
        let maxY = max(0, table.bounds.height - clip.bounds.height)
        target = min(max(0, target), maxY)
        let origin = NSPoint(x: clip.bounds.origin.x, y: target)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    @objc private func boundsChanged() {
        // Fold labels are centered in the visible rect; keep them centered
        // while scrolling horizontally.
        table.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? FoldRowView)?.needsDisplay = true
        }
        guard !isSyncing, let partner = partner else { return }
        let y = scrollView.contentView.bounds.origin.y
        let pc = partner.scrollView.contentView
        if abs(pc.bounds.origin.y - y) > 0.5 {
            partner.isSyncing = true
            pc.setBoundsOrigin(NSPoint(x: pc.bounds.origin.x, y: y))
            partner.scrollView.reflectScrolledClipView(pc)
            partner.isSyncing = false
        }
    }

    @objc private func frameChanged() {
        updateColumnWidth()
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .line(let fullIndex, let diffRow):
            let view = (tableView.makeView(withIdentifier: DiffHalfRowView.reuseID, owner: nil) as? DiffHalfRowView)
                ?? {
                    let v = DiffHalfRowView()
                    v.identifier = DiffHalfRowView.reuseID
                    return v
                }()
            view.configure(row: diffRow, side: side, gutterWidth: gutterWidth,
                           inCurrentBlock: currentBlockRange?.contains(fullIndex) ?? false)
            return view
        case .fold(let range, let count):
            let view = (tableView.makeView(withIdentifier: FoldRowView.reuseID, owner: nil) as? FoldRowView)
                ?? {
                    let v = FoldRowView()
                    v.identifier = FoldRowView.reuseID
                    return v
                }()
            view.configure(range: range, count: count)
            view.onClick = { [weak self] range in self?.onFoldClick?(range) }
            return view
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

// MARK: - Sidebar file tree

final class FileNode {
    let name: String
    var children: [FileNode] = []
    var fileIndex: Int?  // nil = directory
    weak var parent: FileNode?
    var isDir: Bool { fileIndex == nil }

    init(name: String, fileIndex: Int? = nil) {
        self.name = name
        self.fileIndex = fileIndex
    }

    var fileCount: Int {
        isDir ? children.reduce(0) { $0 + $1.fileCount } : 1
    }

    /// Builds a directory tree from the changed files, with single-child
    /// directory chains compressed ("src/main/java" style).
    static func buildTree(files: [ChangedFile]) -> (root: FileNode, byIndex: [Int: FileNode]) {
        let root = FileNode(name: "")
        var byIndex: [Int: FileNode] = [:]

        for (idx, file) in files.enumerated() {
            let components = file.displayPath.split(separator: "/").map(String.init)
            var node = root
            for dir in components.dropLast() {
                if let existing = node.children.first(where: { $0.isDir && $0.name == dir }) {
                    node = existing
                } else {
                    let child = FileNode(name: dir)
                    node.children.append(child)
                    node = child
                }
            }
            let leaf = FileNode(name: components.last ?? file.displayPath, fileIndex: idx)
            node.children.append(leaf)
            byIndex[idx] = leaf
        }

        func sortAndCompress(_ node: FileNode) {
            for i in node.children.indices where node.children[i].isDir {
                // Compress chains of single-child directories into one node.
                while node.children[i].children.count == 1,
                      let only = node.children[i].children.first, only.isDir {
                    let combined = FileNode(name: node.children[i].name + "/" + only.name)
                    combined.children = only.children
                    node.children[i] = combined
                }
                sortAndCompress(node.children[i])
            }
            node.children.sort { a, b in
                if a.isDir != b.isDir { return a.isDir }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        sortAndCompress(root)

        func assignParents(_ node: FileNode) {
            for child in node.children {
                child.parent = node
                assignParents(child)
            }
        }
        assignParents(root)
        return (root, byIndex)
    }
}

final class SidebarCellView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarCell")

    private var node: FileNode?
    private var file: ChangedFile?
    private var selected = false

    override var isFlipped: Bool { true }

    func configure(node: FileNode, file: ChangedFile?, selected: Bool) {
        self.node = node
        self.file = file
        self.selected = selected
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let node = node else { return }
        let h = bounds.height
        let primaryColor: NSColor = selected ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = selected
            ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.7)
            : .secondaryLabelColor

        var x: CGFloat = 2

        if let file = file {
            // Status badge
            let color = Theme.statusColor(file.status)
            let badge = NSRect(x: x, y: (h - 15) / 2, width: 15, height: 15)
            color.withAlphaComponent(selected ? 0.45 : 0.18).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
            let letterAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: selected ? NSColor.selectedMenuItemTextColor : color,
            ]
            let letter = file.status.letter as NSString
            let ls = letter.size(withAttributes: letterAttrs)
            letter.draw(at: NSPoint(x: badge.midX - ls.width / 2, y: badge.midY - ls.height / 2),
                        withAttributes: letterAttrs)
            x = badge.maxX + 6
        } else {
            // Folder icon
            if #available(macOS 11.0, *),
               let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                let img = folder.withSymbolConfiguration(config) ?? folder
                let size = img.size
                let rect = NSRect(x: x, y: (h - size.height) / 2, width: size.width, height: size.height)
                let tinted = img.copy() as! NSImage
                tinted.isTemplate = true
                NSGraphicsContext.current?.saveGraphicsState()
                tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: selected ? 0.9 : 0.55)
                NSGraphicsContext.current?.restoreGraphicsState()
                x = rect.maxX + 6
            } else {
                x += 4
            }
        }

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: node.isDir ? .medium : .regular),
            .foregroundColor: primaryColor,
        ]
        let nameStr = node.name as NSString
        let nameSize = nameStr.size(withAttributes: nameAttrs)
        let avail = bounds.width - x - 4
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingMiddle
        var attrs = nameAttrs
        attrs[.paragraphStyle] = para
        nameStr.draw(in: NSRect(x: x, y: (h - nameSize.height) / 2,
                                width: min(nameSize.width, avail), height: nameSize.height),
                     withAttributes: attrs)
        x += min(nameSize.width, avail) + 6

        if node.isDir && x < bounds.width - 16 {
            let count = "\(node.fileCount)" as NSString
            let countAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: secondaryColor,
            ]
            let cs = count.size(withAttributes: countAttrs)
            count.draw(at: NSPoint(x: x, y: (h - cs.height) / 2), withAttributes: countAttrs)
        }
    }
}

// MARK: - Sidebar controller

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let session: DiffSession
    let outline = NSOutlineView()
    var onSelect: ((Int) -> Void)?

    private var root = FileNode(name: "")
    private var nodeByFileIndex: [Int: FileNode] = [:]

    init(session: DiffSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        (root, nodeByFileIndex) = FileNode.buildTree(files: session.files)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.minWidth = 100
        column.maxWidth = 1_000_000
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        if #available(macOS 11.0, *) { outline.style = .fullWidth }
        outline.rowHeight = 24
        outline.intercellSpacing = .zero
        outline.allowsEmptySelection = true
        outline.indentationPerLevel = 13
        outline.autoresizesOutlineColumn = false
        outline.dataSource = self
        outline.delegate = self
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Header: file count + collapse/expand-all buttons
        let countLabel = NSTextField(labelWithString:
            "\(session.files.count) file\(session.files.count == 1 ? "" : "s")")
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        func treeButton(_ symbol: String, fallback: String, action: Selector, tooltip: String) -> NSButton {
            let b = NSButton()
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
                b.image = img
            } else {
                b.title = fallback
            }
            b.bezelStyle = .texturedRounded
            b.isBordered = false
            b.target = self
            b.action = action
            b.toolTip = tooltip
            return b
        }
        let collapseButton = treeButton("chevron.right.square", fallback: "▸▸",
                                        action: #selector(collapseAllAction(_:)),
                                        tooltip: "Collapse All Folders (⌥⌘←)")
        let expandButton = treeButton("chevron.down.square", fallback: "▾▾",
                                      action: #selector(expandAllAction(_:)),
                                      tooltip: "Expand All Folders (⌥⌘→)")

        let headerStack = NSStackView(views: [countLabel, NSView(), collapseButton, expandButton])
        headerStack.orientation = .horizontal
        headerStack.spacing = 6
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let root = BackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerStack)
        root.addSubview(separator)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: root.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 28),
            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outline.reloadData()
        expandAll()
    }

    func expandAll() {
        for child in root.children {
            outline.expandItem(child, expandChildren: true)
        }
    }

    func collapseAll() {
        for child in root.children {
            outline.collapseItem(child, collapseChildren: true)
        }
    }

    @objc func expandAllAction(_ sender: Any?) { expandAll() }
    @objc func collapseAllAction(_ sender: Any?) { collapseAll() }

    func selectFile(at index: Int) {
        guard let node = nodeByFileIndex[index] else { return }
        // Expand collapsed ancestors so the row exists, topmost first.
        var ancestors: [FileNode] = []
        var p = node.parent
        while let cur = p, cur !== root {
            ancestors.append(cur)
            p = cur.parent
        }
        for ancestor in ancestors.reversed() {
            outline.expandItem(ancestor)
        }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    // MARK: outline data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? FileNode ?? root
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? FileNode ?? root
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDir ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let view = (outlineView.makeView(withIdentifier: SidebarCellView.reuseID, owner: nil) as? SidebarCellView)
            ?? {
                let v = SidebarCellView()
                v.identifier = SidebarCellView.reuseID
                return v
            }()
        let row = outlineView.row(forItem: node)
        let file = node.fileIndex.map { session.files[$0] }
        view.configure(node: node, file: file, selected: row >= 0 && outlineView.isRowSelected(row))
        return view
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshVisibleCells()
        guard let node = outline.item(atRow: outline.selectedRow) as? FileNode,
              let index = node.fileIndex else { return }
        onSelect?(index)
    }

    private func refreshVisibleCells() {
        outline.enumerateAvailableRowViews { _, row in
            guard let node = self.outline.item(atRow: row) as? FileNode,
                  let cell = self.outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarCellView
            else { return }
            let file = node.fileIndex.map { self.session.files[$0] }
            cell.configure(node: node, file: file, selected: self.outline.isRowSelected(row))
        }
    }
}

// MARK: - Content controller (header + two panes)

final class ContentViewController: NSViewController {
    let session: DiffSession
    let leftPane = DiffPane(side: .left)
    let rightPane = DiffPane(side: .right)

    private let pathLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private let counterLabel = NSTextField(labelWithString: "")

    private(set) var currentIndex: Int = -1
    private var currentDiff: FileDiff?
    private var currentBlock: Int = -1
    private var displayRows: [DisplayRow] = []
    private var fullToDisplay: [Int: Int] = [:]
    private var expandedFolds: Set<Int> = []  // keyed by fold range lowerBound

    /// Lines of context kept visible around each change; longer unchanged
    /// runs are folded behind a clickable bar.
    private static let contextLines = 3
    private static let minFoldSize = 10

    init(session: DiffSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        leftPane.partner = rightPane
        rightPane.partner = leftPane
        let expand: (Range<Int>) -> Void = { [weak self] range in
            self?.expandFold(range)
        }
        leftPane.onFoldClick = expand
        rightPane.onFoldClick = expand
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = BackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false

        // Header bar
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statsLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        counterLabel.font = NSFont.systemFont(ofSize: 11)
        counterLabel.textColor = .secondaryLabelColor

        func navButton(_ symbol: String, fallback: String, action: Selector, tooltip: String) -> NSButton {
            let b = NSButton()
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
                b.image = img
            } else {
                b.title = fallback
            }
            b.bezelStyle = .texturedRounded
            b.target = self
            b.action = action
            b.toolTip = tooltip
            return b
        }
        let prev = navButton("chevron.up", fallback: "▲", action: #selector(prevChange(_:)), tooltip: "Previous Change (P)")
        let next = navButton("chevron.down", fallback: "▼", action: #selector(nextChange(_:)), tooltip: "Next Change (N)")

        let headerStack = NSStackView(views: [pathLabel, statsLabel, NSView(), counterLabel, prev, next])
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerStack)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)

        // Panes
        let paneStack = NSStackView(views: [leftPane.scrollView, rightPane.scrollView])
        paneStack.orientation = .horizontal
        paneStack.distribution = .fillEqually
        paneStack.spacing = 1
        paneStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(paneStack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 38),

            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            paneStack.topAnchor.constraint(equalTo: header.bottomAnchor),
            paneStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            paneStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            paneStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        self.view = root
    }

    func showFile(at index: Int) {
        guard index >= 0 && index < session.files.count, index != currentIndex else { return }
        currentIndex = index
        let diff = session.fileDiff(at: index)
        currentDiff = diff
        currentBlock = -1

        let file = diff.file
        if file.status == .renamed || file.status == .copied {
            pathLabel.stringValue = "\(file.oldPath) → \(file.newPath)"
        } else {
            pathLabel.stringValue = file.displayPath
        }

        let stats = NSMutableAttributedString()
        if diff.additions > 0 {
            stats.append(NSAttributedString(string: "+\(diff.additions) ",
                attributes: [.foregroundColor: NSColor.systemGreen,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)]))
        }
        if diff.deletions > 0 {
            stats.append(NSAttributedString(string: "−\(diff.deletions)",
                attributes: [.foregroundColor: NSColor.systemRed,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)]))
        }
        statsLabel.attributedStringValue = stats

        expandedFolds.removeAll()
        rebuildDisplayRows()
        leftPane.setContent(rows: displayRows, maxColumns: diff.maxLeftColumns, maxLineNumber: diff.maxLineNumber)
        rightPane.setContent(rows: displayRows, maxColumns: diff.maxRightColumns, maxLineNumber: diff.maxLineNumber)
        updateCounter()
    }

    /// Rebuilds the display list: context runs longer than the threshold are
    /// folded, keeping `contextLines` visible around each change.
    private func rebuildDisplayRows() {
        guard let diff = currentDiff else {
            displayRows = []
            fullToDisplay = [:]
            return
        }
        let rows = diff.rows
        var out: [DisplayRow] = []
        var map: [Int: Int] = [:]
        func emit(_ idx: Int) {
            map[idx] = out.count
            out.append(.line(fullIndex: idx, row: rows[idx]))
        }
        var i = 0
        while i < rows.count {
            guard rows[i].kind == .context else {
                emit(i)
                i += 1
                continue
            }
            var j = i
            while j < rows.count && rows[j].kind == .context { j += 1 }
            let head = i == 0 ? 0 : Self.contextLines           // after previous change
            let tail = j == rows.count ? 0 : Self.contextLines  // before next change
            let hideStart = i + head
            let hideEnd = j - tail
            let hidden = hideEnd - hideStart
            if hidden >= Self.minFoldSize && !expandedFolds.contains(hideStart) {
                for k in i..<hideStart { emit(k) }
                out.append(.fold(range: hideStart..<hideEnd, count: hidden))
                for k in hideEnd..<j { emit(k) }
            } else {
                for k in i..<j { emit(k) }
            }
            i = j
        }
        displayRows = out
        fullToDisplay = map
    }

    private func expandFold(_ range: Range<Int>) {
        guard !expandedFolds.contains(range.lowerBound) else { return }
        expandedFolds.insert(range.lowerBound)
        rebuildDisplayRows()
        leftPane.updateRows(displayRows)
        rightPane.updateRows(displayRows)
        // Re-apply the current block marker (full-row indices are unchanged).
        if currentBlock >= 0, let diff = currentDiff, currentBlock < diff.changeBlocks.count {
            let startRow = diff.changeBlocks[currentBlock]
            let blockRange = self.blockRange(startingAt: startRow)
            leftPane.setCurrentBlock(blockRange)
            rightPane.setCurrentBlock(blockRange)
        }
    }

    @objc func expandAllFolds(_ sender: Any?) {
        var changed = false
        for row in displayRows {
            if case .fold(let range, _) = row {
                expandedFolds.insert(range.lowerBound)
                changed = true
            }
        }
        guard changed else { return }
        rebuildDisplayRows()
        leftPane.updateRows(displayRows)
        rightPane.updateRows(displayRows)
    }

    private func blockRange(startingAt rowIndex: Int) -> Range<Int> {
        guard let diff = currentDiff else { return rowIndex..<rowIndex }
        var end = rowIndex
        while end < diff.rows.count && diff.rows[end].kind != .context && diff.rows[end].kind != .message {
            end += 1
        }
        return rowIndex..<max(end, rowIndex + 1)
    }

    private func goToBlock(_ blockIndex: Int) {
        guard let diff = currentDiff, !diff.changeBlocks.isEmpty else { return }
        let clamped = min(max(0, blockIndex), diff.changeBlocks.count - 1)
        currentBlock = clamped
        let startRow = diff.changeBlocks[clamped]
        let range = blockRange(startingAt: startRow)
        leftPane.setCurrentBlock(range)
        rightPane.setCurrentBlock(range)
        if let displayIndex = fullToDisplay[startRow] {
            leftPane.scrollToRow(displayIndex, animated: true)
        }
        updateCounter()
    }

    private func updateCounter() {
        guard let diff = currentDiff else { counterLabel.stringValue = ""; return }
        let total = diff.changeBlocks.count
        if total == 0 {
            counterLabel.stringValue = ""
        } else if currentBlock < 0 {
            counterLabel.stringValue = "\(total) change\(total == 1 ? "" : "s")"
        } else {
            counterLabel.stringValue = "Change \(currentBlock + 1) of \(total)"
        }
    }

    @objc func nextChange(_ sender: Any?) {
        goToBlock(currentBlock + 1)
    }

    @objc func prevChange(_ sender: Any?) {
        goToBlock(currentBlock <= 0 ? 0 : currentBlock - 1)
    }
}

// MARK: - Main window controller

final class MainWindowController: NSWindowController {
    let session: DiffSession
    let sidebarVC: SidebarViewController
    let contentVC: ContentViewController
    private var keyMonitor: Any?

    init(session: DiffSession) {
        self.session = session
        self.sidebarVC = SidebarViewController(session: session)
        self.contentVC = ContentViewController(session: session)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "diffy — \(session.title)  (\(session.files.count) file\(session.files.count == 1 ? "" : "s"))"
        window.minSize = NSSize(width: 760, height: 400)
        window.center()
        window.setFrameAutosaveName("DiffyMainWindow")

        super.init(window: window)

        let splitVC = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 520
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)
        splitVC.splitView.autosaveName = "DiffySplit"
        window.contentViewController = splitVC
        // Setting contentViewController resizes the window to the VC's fitting
        // size; restore the intended initial size.
        window.setContentSize(NSSize(width: 1320, height: 850))
        window.center()

        sidebarVC.onSelect = { [weak self] index in
            self?.contentVC.showFile(at: index)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if !session.files.isEmpty {
            sidebarVC.selectFile(at: 0)
            contentVC.showFile(at: 0)
        }
        window?.makeFirstResponder(sidebarVC.outline)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let split = (self.window?.contentViewController as? NSSplitViewController) else { return }
            if split.splitView.subviews.first?.frame.width ?? 0 < 100 {
                split.splitView.setPosition(300, ofDividerAt: 0)
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
            return false
        }
        let f7 = String(UnicodeScalar(NSF7FunctionKey)!)
        let chars = event.charactersIgnoringModifiers
        let shift = event.modifierFlags.contains(.shift)
        switch chars {
        case "n":
            contentVC.nextChange(nil)
            return true
        case "p", "N":
            contentVC.prevChange(nil)
            return true
        case f7:
            if shift { contentVC.prevChange(nil) } else { contentVC.nextChange(nil) }
            return true
        case "]":
            selectFile(offset: 1)
            return true
        case "[":
            selectFile(offset: -1)
            return true
        default:
            return false
        }
    }

    @objc func nextChangeAction(_ sender: Any?) { contentVC.nextChange(sender) }
    @objc func prevChangeAction(_ sender: Any?) { contentVC.prevChange(sender) }
    @objc func expandAllAction(_ sender: Any?) { contentVC.expandAllFolds(sender) }
    @objc func expandAllFoldersAction(_ sender: Any?) { sidebarVC.expandAll() }
    @objc func collapseAllFoldersAction(_ sender: Any?) { sidebarVC.collapseAll() }
    @objc func nextFileAction(_ sender: Any?) { selectFile(offset: 1) }
    @objc func prevFileAction(_ sender: Any?) { selectFile(offset: -1) }

    private func selectFile(offset: Int) {
        let target = contentVC.currentIndex + offset
        guard target >= 0 && target < session.files.count else { return }
        sidebarVC.selectFile(at: target)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let session: DiffSession?      // nil = start with the branch wizard
    let wizardGit: Git?
    let paths: [String]
    let screenshotPath: String?
    let initialFileIndex: Int
    let initialChangeJumps: Int
    let autoConfirm: Bool
    let expandAllOnLaunch: Bool
    let collapseFoldersOnLaunch: Bool
    var windowController: MainWindowController?
    var wizardController: WizardWindowController?

    init(session: DiffSession?, wizardGit: Git? = nil, paths: [String] = [],
         screenshotPath: String?, initialFileIndex: Int = 0,
         initialChangeJumps: Int = 0, autoConfirm: Bool = false,
         expandAllOnLaunch: Bool = false, collapseFoldersOnLaunch: Bool = false) {
        self.session = session
        self.wizardGit = wizardGit
        self.paths = paths
        self.screenshotPath = screenshotPath
        self.initialFileIndex = initialFileIndex
        self.initialChangeJumps = initialChangeJumps
        self.autoConfirm = autoConfirm
        self.expandAllOnLaunch = expandAllOnLaunch
        self.collapseFoldersOnLaunch = collapseFoldersOnLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if let session = session {
            openMainWindow(session: session)
        } else if let git = wizardGit {
            let wizard = WizardWindowController(git: git, paths: paths) { [weak self] session in
                self?.openMainWindow(session: session)
            }
            wizardController = wizard
            wizard.showWindow(nil)
            if autoConfirm {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.wizardController?.confirm()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)

        if let path = screenshotPath {
            let delay = autoConfirm ? 1.8 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.captureScreenshot(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    private func openMainWindow(session: DiffSession) {
        let wc = MainWindowController(session: session)
        windowController = wc
        wc.showWindow(nil)
        if initialFileIndex > 0 && initialFileIndex < session.files.count {
            wc.sidebarVC.selectFile(at: initialFileIndex)
        }
        for _ in 0..<initialChangeJumps {
            wc.contentVC.nextChange(nil)
        }
        if expandAllOnLaunch {
            wc.contentVC.expandAllFolds(nil)
        }
        if collapseFoldersOnLaunch {
            wc.sidebarVC.collapseAll()
        }
        if let wizard = wizardController {
            wizardController = nil
            wizard.close()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func captureScreenshot(to path: String) {
        let targetWindow = windowController?.window ?? wizardController?.window
        guard let view = targetWindow?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About diffy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit diffy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let navMenuItem = NSMenuItem()
        let navMenu = NSMenu(title: "Navigate")
        let nextChange = NSMenuItem(title: "Next Change", action: #selector(MainWindowController.nextChangeAction(_:)), keyEquivalent: "j")
        let prevChange = NSMenuItem(title: "Previous Change", action: #selector(MainWindowController.prevChangeAction(_:)), keyEquivalent: "k")
        let nextFile = NSMenuItem(title: "Next File", action: #selector(MainWindowController.nextFileAction(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        let prevFile = NSMenuItem(title: "Previous File", action: #selector(MainWindowController.prevFileAction(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        let expandAll = NSMenuItem(title: "Expand Unchanged Lines",
                                   action: #selector(MainWindowController.expandAllAction(_:)),
                                   keyEquivalent: "e")
        let expandFolders = NSMenuItem(title: "Expand All Folders",
                                       action: #selector(MainWindowController.expandAllFoldersAction(_:)),
                                       keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        expandFolders.keyEquivalentModifierMask = [.command, .option]
        let collapseFolders = NSMenuItem(title: "Collapse All Folders",
                                         action: #selector(MainWindowController.collapseAllFoldersAction(_:)),
                                         keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        collapseFolders.keyEquivalentModifierMask = [.command, .option]
        for item in [nextChange, prevChange, nextFile, prevFile, .separator(),
                     expandAll, .separator(), expandFolders, collapseFolders] {
            navMenu.addItem(item)
        }
        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
