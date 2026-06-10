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

    // Xcode-default-inspired syntax palette
    private static let syntaxKeyword = dynamic(light: NSColor(red: 0.68, green: 0.24, blue: 0.64, alpha: 1),
                                               dark: NSColor(red: 0.99, green: 0.37, blue: 0.64, alpha: 1))
    private static let syntaxString = dynamic(light: NSColor(red: 0.82, green: 0.18, blue: 0.11, alpha: 1),
                                              dark: NSColor(red: 0.99, green: 0.42, blue: 0.37, alpha: 1))
    private static let syntaxComment = dynamic(light: NSColor(red: 0.36, green: 0.42, blue: 0.47, alpha: 1),
                                               dark: NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1))
    private static let syntaxNumber = dynamic(light: NSColor(red: 0.15, green: 0.16, blue: 0.85, alpha: 1),
                                              dark: NSColor(red: 0.82, green: 0.75, blue: 0.41, alpha: 1))
    private static let syntaxType = dynamic(light: NSColor(red: 0.25, green: 0.43, blue: 0.46, alpha: 1),
                                            dark: NSColor(red: 0.62, green: 0.94, blue: 0.87, alpha: 1))
    private static let syntaxAttribute = dynamic(light: NSColor(red: 0.58, green: 0.44, blue: 0.0, alpha: 1),
                                                 dark: NSColor(red: 0.99, green: 0.56, blue: 0.25, alpha: 1))

    static func syntaxColor(_ kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: return syntaxKeyword
        case .string: return syntaxString
        case .comment: return syntaxComment
        case .number: return syntaxNumber
        case .typeName: return syntaxType
        case .attribute: return syntaxAttribute
        }
    }

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

/// What a diff pane actually displays: a real diff row, a fold bar standing
/// in for hidden unchanged rows, or a review-comment thread.
enum DisplayRow {
    case line(fullIndex: Int, row: DiffRow)
    case fold(range: Range<Int>, count: Int)
    case comment(thread: MRThread, side: PaneSide, anchor: Int)
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
    var isSelectedLine = false

    override var isFlipped: Bool { true }

    func configure(row: DiffRow, side: PaneSide, gutterWidth: CGFloat, inCurrentBlock: Bool,
                   isSelectedLine: Bool = false) {
        self.line = side == .left ? row.left : row.right
        self.kind = row.kind
        self.side = side
        self.gutterWidth = gutterWidth
        self.inCurrentBlock = inCurrentBlock
        self.isSelectedLine = isSelectedLine
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
        if isSelectedLine {
            Theme.accent.withAlphaComponent(0.22).setFill()
            bounds.fill()
        }

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
        let plainAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.codeFont,
            .foregroundColor: NSColor.labelColor,
        ]

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

        // Syntax-highlighted text. Token ranges are Character offsets, so the
        // attributed string is assembled from substrings (no UTF-16 math).
        let attributed: NSAttributedString
        if line.tokens.isEmpty {
            attributed = NSAttributedString(string: line.text, attributes: plainAttrs)
        } else {
            let chars = Array(line.text)
            let result = NSMutableAttributedString()
            var cursor = 0
            for token in line.tokens {
                let lo = max(0, min(token.range.lowerBound, chars.count))
                let hi = max(lo, min(token.range.upperBound, chars.count))
                if lo > cursor {
                    result.append(NSAttributedString(string: String(chars[cursor..<lo]),
                                                     attributes: plainAttrs))
                }
                result.append(NSAttributedString(string: String(chars[lo..<hi]), attributes: [
                    .font: Theme.codeFont,
                    .foregroundColor: Theme.syntaxColor(token.kind),
                ]))
                cursor = hi
            }
            if cursor < chars.count {
                result.append(NSAttributedString(string: String(chars[cursor...]),
                                                 attributes: plainAttrs))
            }
            attributed = result
        }
        let textY = (h - attributed.size().height) / 2
        attributed.draw(at: NSPoint(x: textX, y: textY))
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

// MARK: - @mention autocomplete

/// Text view that shows an @-mention completion popup. NSTextView's built-in
/// completion is keyed to whole words and clunky for this; a small custom
/// dropdown is simpler and matches the GitLab UX.
final class MentionTextView: NSTextView, NSTableViewDelegate, NSTableViewDataSource {
    var members: [GitLabUser] = []

    private var popover: NSWindow?
    private let menuTable = NSTableView()
    private var matches: [GitLabUser] = []
    private var mentionStart: Int?   // UTF-16 offset of the '@'

    override func keyDown(with event: NSEvent) {
        if popover != nil {
            switch event.keyCode {
            case 125:  // down
                moveSelection(1); return
            case 126:  // up
                moveSelection(-1); return
            case 36, 48:  // return, tab
                acceptSelection(); return
            case 53:  // escape
                dismiss(); return
            default:
                break
            }
        }
        super.keyDown(with: event)
        updateMentionState()
    }

    override func didChangeText() {
        super.didChangeText()
        updateMentionState()
    }

    /// Test hook: re-run mention detection after setting text programmatically.
    func triggerMentionForTest() { updateMentionState() }

    override func resignFirstResponder() -> Bool {
        dismiss()
        return super.resignFirstResponder()
    }

    /// Detects an `@token` ending at the caret and shows/updates the popup.
    private func updateMentionState() {
        guard !members.isEmpty, let text = string as NSString?,
              selectedRange().length == 0 else { dismiss(); return }
        let caret = selectedRange().location
        var i = caret
        while i > 0 {
            let c = text.character(at: i - 1)
            let scalar = Unicode.Scalar(c)
            if c == UInt16(UnicodeScalar("@").value) {
                let prefix = text.substring(with: NSRange(location: i, length: caret - i))
                // Only trigger at start or after whitespace/'('.
                if i >= 2 {
                    let before = text.character(at: i - 2)
                    let bs = Unicode.Scalar(before)!
                    if !CharacterSet.whitespacesAndNewlines.contains(bs) && before != UInt16(UnicodeScalar("(").value) {
                        dismiss(); return
                    }
                }
                showMatches(forPrefix: prefix, mentionAt: i - 1)
                return
            }
            // mention tokens are word chars only
            if let s = scalar, CharacterSet.alphanumerics.contains(s) || c == UInt16(UnicodeScalar("_").value)
                || c == UInt16(UnicodeScalar("-").value) || c == UInt16(UnicodeScalar(".").value) {
                i -= 1
            } else {
                break
            }
        }
        dismiss()
    }

    /// Filters members for an @-mention prefix: username-prefix matches first,
    /// then name-substring matches. Username matches rank above name matches.
    static func match(_ members: [GitLabUser], prefix: String, limit: Int = 8) -> [GitLabUser] {
        let lower = prefix.lowercased()
        if lower.isEmpty { return Array(members.prefix(limit)) }
        var byUsername: [GitLabUser] = []
        var byName: [GitLabUser] = []
        for m in members {
            if m.username.lowercased().hasPrefix(lower) {
                byUsername.append(m)
            } else if m.name.lowercased().contains(lower) {
                byName.append(m)
            }
        }
        return Array((byUsername + byName).prefix(limit))
    }

    private func showMatches(forPrefix prefix: String, mentionAt: Int) {
        matches = MentionTextView.match(members, prefix: prefix)
        guard !matches.isEmpty else { dismiss(); return }
        mentionStart = mentionAt
        presentPopover()
    }

    private func presentPopover() {
        let rowHeight: CGFloat = 22
        let height = CGFloat(matches.count) * rowHeight + 2
        let width: CGFloat = 260

        let popover: NSWindow
        if let existing = self.popover {
            popover = existing
        } else {
            popover = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                               styleMask: [.borderless], backing: .buffered, defer: true)
            popover.backgroundColor = .clear
            popover.isOpaque = false
            popover.hasShadow = true
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            scroll.drawsBackground = true
            scroll.backgroundColor = .controlBackgroundColor
            scroll.borderType = .lineBorder
            scroll.hasVerticalScroller = false
            if menuTable.tableColumns.isEmpty {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("m"))
                col.width = width - 4
                menuTable.addTableColumn(col)
                menuTable.headerView = nil
                menuTable.rowHeight = rowHeight
                menuTable.backgroundColor = .controlBackgroundColor
                menuTable.dataSource = self
                menuTable.delegate = self
                menuTable.action = #selector(rowClicked)
                menuTable.target = self
            }
            scroll.documentView = menuTable
            popover.contentView = scroll
            self.popover = popover
        }
        popover.setContentSize(NSSize(width: width, height: height))
        menuTable.reloadData()
        if menuTable.selectedRow < 0 || menuTable.selectedRow >= matches.count {
            menuTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        // Position below the caret.
        if let start = mentionStart, let lm = layoutManager, let tc = textContainer {
            let glyph = lm.glyphIndexForCharacter(at: start)
            var rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            if let screenRect = window?.convertToScreen(convert(rect, to: nil)) {
                popover.setFrameTopLeftPoint(NSPoint(x: screenRect.minX, y: screenRect.minY - 2))
            }
        }
        if popover.parent == nil {
            window?.addChildWindow(popover, ordered: .above)
        }
    }

    private func moveSelection(_ delta: Int) {
        let next = max(0, min(matches.count - 1, menuTable.selectedRow + delta))
        menuTable.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        menuTable.scrollRowToVisible(next)
    }

    @objc private func rowClicked() { acceptSelection() }

    private func acceptSelection() {
        let row = menuTable.selectedRow
        guard row >= 0, row < matches.count, let start = mentionStart else { dismiss(); return }
        let caret = selectedRange().location
        let replaceRange = NSRange(location: start, length: caret - start)
        let insertion = "@\(matches[row].username) "
        if shouldChangeText(in: replaceRange, replacementString: insertion) {
            textStorage?.replaceCharacters(in: replaceRange, with: insertion)
            didChangeText()
            setSelectedRange(NSRange(location: start + (insertion as NSString).length, length: 0))
        }
        dismiss()
    }

    private func dismiss() {
        if let popover = popover {
            window?.removeChildWindow(popover)
            popover.orderOut(nil)
        }
        popover = nil
        mentionStart = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("mcell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(label)
            c.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let user = matches[row]
        let s = NSMutableAttributedString(string: "@\(user.username)",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium),
                         .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(string: "  \(user.name)",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        cell.textField?.attributedStringValue = s
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

// MARK: - Review comment rows

final class CommentRowView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("CommentRow")
    static let spacerReuseID = NSUserInterfaceItemIdentifier("CommentSpacerRow")

    private static let authorFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let dateFont = NSFont.systemFont(ofSize: 10)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)
    private static let cardMarginX: CGFloat = 16
    private static let cardPadding: CGFloat = 10
    private static let outerMarginY: CGFloat = 4
    private static let authorLineHeight: CGFloat = 16
    private static let noteSpacing: CGFloat = 6
    private static let replyRowHeight: CGFloat = 24

    private var thread: MRThread?
    private var cardWidth: CGFloat = 400
    var onReply: ((MRThread) -> Void)?
    var onDiscard: ((MRThread) -> Void)?
    private let replyButton = NSButton()
    private let discardButton = NSButton()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        replyButton.title = "Reply…"
        replyButton.bezelStyle = .recessed
        replyButton.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        replyButton.target = self
        replyButton.action = #selector(replyClicked)
        addSubview(replyButton)
        discardButton.title = "Discard Draft"
        discardButton.bezelStyle = .recessed
        discardButton.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        discardButton.target = self
        discardButton.action = #selector(discardClicked)
        addSubview(discardButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(thread: MRThread, cardWidth: CGFloat) {
        self.thread = thread
        self.cardWidth = cardWidth
        replyButton.isHidden = thread.isDraft  // can't reply before publishing
        discardButton.isHidden = !thread.hasPending
        updateForVisibleRect()
        needsDisplay = true
    }

    @objc private func replyClicked() {
        if let thread = thread { onReply?(thread) }
    }

    @objc private func discardClicked() {
        if let thread = thread { onDiscard?(thread) }
    }

    /// Card and buttons track the visible portion when scrolled horizontally.
    func updateForVisibleRect() {
        let originX = (visibleRect.isEmpty ? 0 : visibleRect.minX) + Self.cardMarginX
        let y = bounds.height - Self.outerMarginY - Self.cardPadding - 21
        replyButton.frame = NSRect(x: originX + Self.cardPadding, y: y, width: 70, height: 19)
        let discardX = replyButton.isHidden
            ? originX + Self.cardPadding
            : replyButton.frame.maxX + 8
        discardButton.frame = NSRect(x: discardX, y: y, width: 105, height: 19)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateForVisibleRect()
    }

    private static func bodyHeight(_ body: String, textWidth: CGFloat) -> CGFloat {
        let attr = NSAttributedString(string: body, attributes: [.font: bodyFont])
        let rect = attr.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height)
    }

    static func height(thread: MRThread, cardWidth: CGFloat) -> CGFloat {
        let textWidth = max(120, cardWidth - 2 * cardMarginX - 2 * cardPadding)
        var h = 2 * outerMarginY + 2 * cardPadding + replyRowHeight
        for note in thread.notes {
            h += authorLineHeight + bodyHeight(note.body, textWidth: textWidth) + noteSpacing
        }
        return ceil(h)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.codeBG.setFill()
        bounds.fill()
        guard let thread = thread else { return }

        let originX = (visibleRect.isEmpty ? 0 : visibleRect.minX) + Self.cardMarginX
        let cardRect = NSRect(x: originX, y: Self.outerMarginY,
                              width: cardWidth - 2 * Self.cardMarginX,
                              height: bounds.height - 2 * Self.outerMarginY)
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
        let alpha: CGFloat = thread.resolved ? 0.55 : 1.0
        NSColor.controlBackgroundColor.withAlphaComponent(alpha).setFill()
        card.fill()
        if thread.hasPending {
            NSColor.systemOrange.withAlphaComponent(0.7).setStroke()
        } else {
            NSColor.separatorColor.setStroke()
        }
        card.lineWidth = 1
        card.stroke()

        let textX = cardRect.minX + Self.cardPadding
        let textWidth = max(120, cardRect.width - 2 * Self.cardPadding)
        var y = cardRect.minY + Self.cardPadding

        if thread.resolved || thread.isDraft {
            let badge = (thread.isDraft ? "Pending review" : "Resolved ✓") as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.dateFont,
                .foregroundColor: thread.isDraft ? NSColor.systemOrange : NSColor.systemGreen,
            ]
            let size = badge.size(withAttributes: attrs)
            badge.draw(at: NSPoint(x: cardRect.maxX - Self.cardPadding - size.width, y: y),
                       withAttributes: attrs)
        }

        for note in thread.notes {
            let textColor = NSColor.labelColor.withAlphaComponent(thread.resolved ? 0.6 : 1)
            let author = note.author as NSString
            author.draw(at: NSPoint(x: textX, y: y), withAttributes: [
                .font: Self.authorFont, .foregroundColor: textColor,
            ])
            let authorWidth = author.size(withAttributes: [.font: Self.authorFont]).width
            let dateText = note.isPending ? "Pending" : String(note.createdAt.prefix(10))
            (dateText as NSString)
                .draw(at: NSPoint(x: textX + authorWidth + 8, y: y + 1), withAttributes: [
                    .font: Self.dateFont,
                    .foregroundColor: note.isPending
                        ? NSColor.systemOrange : NSColor.tertiaryLabelColor,
                ])
            y += Self.authorLineHeight
            let bodyHeight = Self.bodyHeight(note.body, textWidth: textWidth)
            (note.body as NSString).draw(
                in: NSRect(x: textX, y: y, width: textWidth, height: bodyHeight),
                withAttributes: [.font: Self.bodyFont, .foregroundColor: textColor])
            y += bodyHeight + Self.noteSpacing
        }
    }
}

/// Blank stand-in on the opposite pane so both tables stay row-aligned.
final class CommentSpacerRowView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.codeBG.setFill()
        bounds.fill()
    }
}

// MARK: - One pane (scroll view + table)

/// Table that routes ⌘C (via the Edit menu's first-responder chain) to the
/// pane's copy-selected-lines implementation.
final class DiffTableView: NSTableView {
    var onCopy: (() -> Void)?

    @objc func copy(_ sender: Any?) {
        onCopy?()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(copy(_:)) {
            return selectedRowIndexes.isEmpty == false
        }
        return super.responds(to: aSelector)
    }
}

final class DiffPane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let side: PaneSide
    let scrollView = NSScrollView()
    let table = DiffTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("code"))

    var rows: [DisplayRow] = []
    var gutterWidth: CGFloat = 48
    var currentBlockRange: Range<Int>?  // in full-row indices
    var onFoldClick: ((Range<Int>) -> Void)?
    var onReplyToThread: ((MRThread) -> Void)?
    var onDiscardDraft: ((MRThread) -> Void)?
    var onAddComment: ((Int, PaneSide) -> Void)?  // (fullIndex, side)
    var commentingEnabled = false
    weak var partner: DiffPane?
    private var isSyncing = false
    private var contentWidth: CGFloat = 0
    private var lastClipWidth: CGFloat = 0
    private let contextMenu = NSMenu()

    private var clipWidth: CGFloat {
        max(240, scrollView.contentView.bounds.width)
    }

    private var hasCommentRows: Bool {
        rows.contains { if case .comment = $0 { return true } else { return false } }
    }

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
        table.allowsMultipleSelection = true
        table.backgroundColor = Theme.codeBG
        table.onCopy = { [weak self] in self?.copySelectedLines() }
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

        contextMenu.delegate = self
        table.menu = contextMenu
    }

    func setContent(rows: [DisplayRow], maxColumns: Int, maxLineNumber: Int) {
        self.rows = rows
        currentBlockRange = nil
        let digits = max(2, String(max(maxLineNumber, 1)).count)
        gutterWidth = CGFloat(digits) * Theme.charWidth + 20
        // Clamp: minified single-line files would otherwise exceed AppKit's
        // internal layout limits.
        contentWidth = min(gutterWidth + 8 + CGFloat(maxColumns) * Theme.charWidth + 30, 100_000)
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
                       inCurrentBlock: currentBlockRange?.contains(fullIndex) ?? false,
                       isSelectedLine: table.isRowSelected(row))
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
        // Fold labels and comment cards anchor to the visible rect; keep them
        // in place while scrolling horizontally.
        table.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? FoldRowView)?.needsDisplay = true
            (rowView.view(atColumn: 0) as? CommentRowView)?.updateForVisibleRect()
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
        // Comment cards wrap to the visible width; re-measure on resize.
        if hasCommentRows && abs(clipWidth - lastClipWidth) > 0.5 {
            lastClipWidth = clipWidth
            let commentRows = IndexSet(rows.indices.filter {
                if case .comment = rows[$0] { return true } else { return false }
            })
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            table.noteHeightOfRows(withIndexesChanged: commentRows)
            NSAnimationContext.endGrouping()
            table.enumerateAvailableRowViews { rowView, row in
                if case .comment(let thread, _, _) = self.rows[row],
                   let view = rowView.view(atColumn: 0) as? CommentRowView {
                    view.configure(thread: thread, cardWidth: self.clipWidth)
                }
            }
        }
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
                           inCurrentBlock: currentBlockRange?.contains(fullIndex) ?? false,
                           isSelectedLine: tableView.isRowSelected(row))
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
        case .comment(let thread, let commentSide, _):
            if commentSide == side {
                let view = (tableView.makeView(withIdentifier: CommentRowView.reuseID, owner: nil) as? CommentRowView)
                    ?? {
                        let v = CommentRowView()
                        v.identifier = CommentRowView.reuseID
                        return v
                    }()
                view.configure(thread: thread, cardWidth: clipWidth)
                view.onReply = { [weak self] thread in self?.onReplyToThread?(thread) }
                view.onDiscard = { [weak self] thread in self?.onDiscardDraft?(thread) }
                return view
            } else {
                let view = (tableView.makeView(withIdentifier: CommentRowView.spacerReuseID, owner: nil) as? CommentSpacerRowView)
                    ?? {
                        let v = CommentSpacerRowView()
                        v.identifier = CommentRowView.spacerReuseID
                        return v
                    }()
                return view
            }
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .comment(let thread, _, _) = rows[row] {
            return CommentRowView.height(thread: thread, cardWidth: clipWidth)
        }
        return Theme.rowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .line = rows[row] { return true }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        table.enumerateAvailableRowViews { _, row in
            self.reconfigureRow(row)
        }
    }

    /// Copies the text of the selected lines (this pane's side) to the clipboard.
    func copySelectedLines() {
        var lines: [String] = []
        for row in table.selectedRowIndexes.sorted() {
            guard case .line(_, let diffRow) = rows[row] else { continue }
            if let line = side == .left ? diffRow.left : diffRow.right {
                lines.append(line.text)
            }
        }
        guard !lines.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

extension DiffPane: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard row >= 0, row < rows.count,
              case .line(let fullIndex, let diffRow) = rows[row] else { return }
        let line = side == .left ? diffRow.left : diffRow.right
        guard let line = line, diffRow.kind != .message else { return }

        // Copy: the clicked line, or the whole selection if clicked inside it
        let selection = table.selectedRowIndexes
        let copyTitle = selection.contains(row) && selection.count > 1
            ? "Copy \(selection.count) Lines"
            : "Copy Line"
        let copyItem = NSMenuItem(title: copyTitle,
                                  action: #selector(copyClicked(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = row
        menu.addItem(copyItem)

        if commentingEnabled {
            let item = NSMenuItem(title: "Add Comment on Line \(line.number)…",
                                  action: #selector(addCommentClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = fullIndex
            menu.addItem(item)
        }
    }

    @objc private func copyClicked(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        if !table.selectedRowIndexes.contains(row) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        copySelectedLines()
    }

    @objc private func addCommentClicked(_ sender: NSMenuItem) {
        guard let fullIndex = sender.representedObject as? Int else { return }
        onAddComment?(fullIndex, side)
    }
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
        buildTree(files: Array(files.enumerated()).map { ($0.offset, $0.element) })
    }

    /// Builds the tree from files carrying their global session indices, so a
    /// filtered subset still maps leaves back to the right `session.files` row.
    static func buildTree(files: [(index: Int, file: ChangedFile)])
        -> (root: FileNode, byIndex: [Int: FileNode]) {
        let root = FileNode(name: "")
        var byIndex: [Int: FileNode] = [:]

        for (idx, file) in files {
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

final class SidebarViewController: NSViewController, NSOutlineViewDataSource,
                                   NSOutlineViewDelegate, NSSearchFieldDelegate {
    let session: DiffSession
    let outline = NSOutlineView()
    var onSelect: ((Int) -> Void)?

    private var root = FileNode(name: "")
    private var nodeByFileIndex: [Int: FileNode] = [:]
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private var filterText = ""

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
        countLabel.stringValue = "\(session.files.count) file\(session.files.count == 1 ? "" : "s")"
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

        // Filter field
        searchField.placeholderString = "Filter files…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: 11)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let root = BackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerStack)
        root.addSubview(searchField)
        root.addSubview(separator)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: root.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 28),
            searchField.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 5),
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

    // MARK: filtering

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        filterText = trimmed
        let selectedIndex = (outline.item(atRow: outline.selectedRow) as? FileNode)?.fileIndex

        if trimmed.isEmpty {
            (root, nodeByFileIndex) = FileNode.buildTree(files: session.files)
            countLabel.stringValue = "\(session.files.count) file\(session.files.count == 1 ? "" : "s")"
        } else {
            let matches = session.files.enumerated()
                .filter { $0.element.displayPath.range(of: trimmed, options: .caseInsensitive) != nil }
                .map { (index: $0.offset, file: $0.element) }
            (root, nodeByFileIndex) = FileNode.buildTree(files: matches)
            let total = session.files.count
            countLabel.stringValue = "\(matches.count) of \(total)"
        }
        outline.reloadData()
        expandAll()
        // Preserve selection if the file is still visible.
        if let idx = selectedIndex, nodeByFileIndex[idx] != nil {
            selectFile(at: idx)
        }
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

    /// Test hook: drive the filter as if typed into the search field.
    func applyFilterForTest(_ query: String) {
        searchField.stringValue = query
        applyFilter(query)
    }

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
    private let reviewButton = NSButton()
    private let commentsButton = NSButton()
    private var commentsPopover: NSPopover?
    var onNavigateToFile: ((Int) -> Void)?

    private(set) var currentIndex: Int = -1
    private var currentDiff: FileDiff?
    private var currentBlock: Int = -1
    private var displayRows: [DisplayRow] = []
    private var fullToDisplay: [Int: Int] = [:]
    private var expandedFolds: Set<Int> = []  // keyed by fold range lowerBound
    private var commentMap: [Int: [(MRThread, PaneSide)]] = [:]  // full row index → threads

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
        let reply: (MRThread) -> Void = { [weak self] thread in
            self?.replyToThread(thread)
        }
        leftPane.onReplyToThread = reply
        rightPane.onReplyToThread = reply
        let discard: (MRThread) -> Void = { [weak self] thread in
            self?.discardDrafts(of: thread)
        }
        leftPane.onDiscardDraft = discard
        rightPane.onDiscardDraft = discard
        let addComment: (Int, PaneSide) -> Void = { [weak self] fullIndex, side in
            self?.addComment(atFullIndex: fullIndex, side: side)
        }
        leftPane.onAddComment = addComment
        rightPane.onAddComment = addComment
        leftPane.commentingEnabled = session.mr != nil
        rightPane.commentingEnabled = session.mr != nil
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

        reviewButton.bezelStyle = .rounded
        reviewButton.controlSize = .small
        reviewButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        reviewButton.contentTintColor = .systemOrange
        reviewButton.target = self
        reviewButton.action = #selector(submitReview(_:))
        reviewButton.toolTip = "Publish all pending review comments at once"
        reviewButton.isHidden = true

        commentsButton.bezelStyle = .rounded
        commentsButton.controlSize = .small
        commentsButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        commentsButton.target = self
        commentsButton.action = #selector(showAllComments(_:))
        commentsButton.toolTip = "Show all review comments in this MR"
        commentsButton.isHidden = true

        let headerStack = NSStackView(views: [pathLabel, statsLabel, NSView(), commentsButton, reviewButton, counterLabel, prev, next])
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
        rebuildCommentMap()
        rebuildDisplayRows()
        leftPane.setContent(rows: displayRows, maxColumns: diff.maxLeftColumns, maxLineNumber: diff.maxLineNumber)
        rightPane.setContent(rows: displayRows, maxColumns: diff.maxRightColumns, maxLineNumber: diff.maxLineNumber)
        updateCounter()
        updateReviewButton()
    }

    /// Anchors the MR's review threads to full-row indices of the current file.
    private func rebuildCommentMap() {
        commentMap = [:]
        guard let mr = session.mr, let diff = currentDiff else { return }
        let threads = mr.displayThreads(for: diff.file)
        guard !threads.isEmpty else { return }
        var rowByRightLine: [Int: Int] = [:]
        var rowByLeftLine: [Int: Int] = [:]
        for (i, row) in diff.rows.enumerated() {
            if let r = row.right { rowByRightLine[r.number] = i }
            if let l = row.left { rowByLeftLine[l.number] = i }
        }
        for thread in threads {
            guard let pos = thread.position else { continue }
            if let nl = pos.newLine, pos.newPath == diff.file.newPath, let idx = rowByRightLine[nl] {
                commentMap[idx, default: []].append((thread, .right))
            } else if let ol = pos.oldLine, let idx = rowByLeftLine[ol] {
                commentMap[idx, default: []].append((thread, .left))
            }
        }
    }

    /// Rebuilds the display list: context runs longer than the threshold are
    /// folded, keeping `contextLines` visible around each change. Lines with
    /// review comments are never folded; their threads follow them as rows.
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
            for (thread, side) in commentMap[idx] ?? [] {
                out.append(.comment(thread: thread, side: side, anchor: idx))
            }
        }
        var i = 0
        while i < rows.count {
            guard rows[i].kind == .context && commentMap[i] == nil else {
                emit(i)
                i += 1
                continue
            }
            var j = i
            while j < rows.count && rows[j].kind == .context && commentMap[j] == nil { j += 1 }
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

    // MARK: GitLab review comments

    /// Modal text-entry dialog. Returns the text and whether to send
    /// immediately (true) or batch into the pending review (false).
    private func commentDialog(title: String) -> (body: String, sendNow: Bool)? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "“Add to Review” batches the comment; submit the whole review at once with the Submit Review button."
        alert.addButton(withTitle: "Add to Review")
        alert.addButton(withTitle: "Send Now")
        alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 100))
        let textView = MentionTextView(frame: scroll.bounds)
        textView.members = session.mr?.members ?? []
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.isRichText = false
        textView.allowsUndo = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView
        let response = alert.runModal()
        let sendNow: Bool
        switch response {
        case .alertFirstButtonReturn: sendNow = false
        case .alertSecondButtonReturn: sendNow = true
        default: return nil
        }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (text, sendNow)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "GitLab request failed"
        alert.informativeText = "\(error)"
        alert.runModal()
    }

    private func refreshComments() {
        guard let mr = session.mr else { return }
        mr.refresh()
        rebuildCommentMap()
        rebuildDisplayRows()
        leftPane.updateRows(displayRows)
        rightPane.updateRows(displayRows)
        updateReviewButton()
    }

    func updateReviewButton() {
        let count = session.mr?.draftCount ?? 0
        reviewButton.isHidden = count == 0
        reviewButton.title = "Submit Review (\(count))"

        guard let mr = session.mr else { commentsButton.isHidden = true; return }
        let total = mr.allThreadLocations(files: session.files).count
        commentsButton.isHidden = total == 0
        commentsButton.title = "Comments (\(total))"
    }

    func showAllCommentsForTest() { showAllComments(nil) }

    @objc private func showAllComments(_ sender: Any?) {
        guard let mr = session.mr else { return }
        let entries = mr.allThreadLocations(files: session.files).map {
            CommentsListController.Entry(fileIndex: $0.fileIndex, line: $0.line,
                                         path: session.files[$0.fileIndex].displayPath,
                                         thread: $0.thread)
        }
        guard !entries.isEmpty else { return }
        let list = CommentsListController(entries: entries)
        let popover = NSPopover()
        popover.contentViewController = list
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: list.view.frame.height)
        list.onSelect = { [weak self, weak popover] entry in
            popover?.close()
            self?.navigateToComment(entry)
        }
        commentsPopover = popover
        popover.show(relativeTo: commentsButton.bounds, of: commentsButton, preferredEdge: .maxY)
    }

    private func navigateToComment(_ entry: CommentsListController.Entry) {
        if entry.fileIndex != currentIndex {
            onNavigateToFile?(entry.fileIndex)  // selects file in sidebar → showFile
        }
        // After the file is shown, scroll to the thread's row.
        DispatchQueue.main.async { [weak self] in
            self?.scrollToThread(id: entry.thread.id)
        }
    }

    private func scrollToThread(id: String) {
        guard let displayIndex = displayRows.firstIndex(where: {
            if case .comment(let t, _, _) = $0 { return t.id == id } else { return false }
        }) else { return }
        leftPane.scrollToRow(displayIndex, animated: true)
    }

    @objc private func submitReview(_ sender: Any?) {
        guard let mr = session.mr, mr.draftCount > 0 else { return }
        do {
            try mr.client.publishDrafts()
            refreshComments()
        } catch {
            showError(error)
        }
    }

    private func discardDrafts(of thread: MRThread) {
        guard let mr = session.mr, !thread.draftIDs.isEmpty else { return }
        do {
            for id in thread.draftIDs {
                try mr.client.deleteDraft(id: id)
            }
            refreshComments()
        } catch {
            showError(error)
        }
    }

    private func replyToThread(_ thread: MRThread) {
        guard let mr = session.mr,
              let (body, sendNow) = commentDialog(
                  title: "Reply to \(thread.notes.first?.author ?? "thread")") else { return }
        do {
            if sendNow {
                try mr.client.postReply(discussionID: thread.id, body: body)
            } else {
                try mr.client.createDraft(mr: mr.mr, body: body, position: nil,
                                          replyToDiscussionID: thread.id)
            }
            refreshComments()
        } catch {
            showError(error)
        }
    }

    private func addComment(atFullIndex fullIndex: Int, side: PaneSide) {
        guard let mr = session.mr, let diff = currentDiff,
              fullIndex < diff.rows.count else { return }
        let row = diff.rows[fullIndex]
        let file = diff.file
        var oldLine: Int?
        var newLine: Int?
        switch side {
        case .right:
            guard let r = row.right else { return }
            newLine = r.number
            if row.kind == .context { oldLine = row.left?.number }
        case .left:
            guard let l = row.left else { return }
            oldLine = l.number
            if row.kind == .context { newLine = row.right?.number }
        }
        let lineDesc = newLine.map { "line \($0)" } ?? "old line \(oldLine ?? 0)"
        guard let (body, sendNow) = commentDialog(
            title: "Comment on \((file.displayPath as NSString).lastPathComponent), \(lineDesc)")
        else { return }
        let position = MRPosition(
            oldPath: file.oldPath.isEmpty ? file.newPath : file.oldPath,
            newPath: file.newPath.isEmpty ? file.oldPath : file.newPath,
            oldLine: oldLine, newLine: newLine)
        do {
            if sendNow {
                try mr.client.postThread(mr: mr.mr, body: body, position: position)
            } else {
                try mr.client.createDraft(mr: mr.mr, body: body, position: position,
                                          replyToDiscussionID: nil)
            }
            refreshComments()
        } catch {
            showError(error)
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
        let fileCount = "(\(session.files.count) file\(session.files.count == 1 ? "" : "s"))"
        if let mr = session.mr {
            window.title = "diffy — !\(mr.mr.iid) \(mr.mr.title) — \(session.title)  \(fileCount)"
        } else {
            window.title = "diffy — \(session.title)  \(fileCount)"
        }
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
        contentVC.onNavigateToFile = { [weak self] index in
            self?.sidebarVC.selectFile(at: index)
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

// MARK: - All-comments overview popover

final class CommentsListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct Entry {
        let fileIndex: Int
        let line: Int
        let path: String
        let thread: MRThread
    }

    private let entries: [Entry]
    private let table = NSTableView()
    var onSelect: ((Entry) -> Void)?

    init(entries: [Entry]) {
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.width = 380
        table.addTableColumn(column)
        table.headerView = nil
        if #available(macOS 11.0, *) { table.style = .fullWidth }
        table.rowHeight = 54
        table.dataSource = self
        table.delegate = self
        table.action = #selector(rowClicked)
        table.target = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400,
                                             height: min(420, max(60, CGFloat(entries.count) * 54 + 8))))
        scroll.frame = container.bounds
        scroll.autoresizingMask = [.width, .height]
        container.addSubview(scroll)
        self.view = container
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < entries.count else { return }
        onSelect?(entries[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ccell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let label = NSTextField(wrappingLabelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.maximumNumberOfLines = 3
            c.addSubview(label)
            c.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let e = entries[row]
        let first = e.thread.notes.first
        let header = NSMutableAttributedString(
            string: "\((e.path as NSString).lastPathComponent):\(e.line)",
            attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                         .foregroundColor: NSColor.labelColor])
        if e.thread.resolved {
            header.append(NSAttributedString(string: "  ✓",
                attributes: [.foregroundColor: NSColor.systemGreen,
                             .font: NSFont.systemFont(ofSize: 11)]))
        } else if e.thread.hasPending {
            header.append(NSAttributedString(string: "  • pending",
                attributes: [.foregroundColor: NSColor.systemOrange,
                             .font: NSFont.systemFont(ofSize: 10)]))
        }
        let snippet = (first?.body ?? "").replacingOccurrences(of: "\n", with: " ")
        header.append(NSAttributedString(
            string: "\n\(first?.author ?? "")  \(String(snippet.prefix(80)))",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        cell.textField?.attributedStringValue = header
        return cell
    }
}

// MARK: - @mention popup UI test delegate

final class MentionUITestDelegate: NSObject, NSApplicationDelegate {
    let screenshotPath: String
    var window: NSWindow?
    var textView: MentionTextView?

    init(screenshotPath: String) { self.screenshotPath = screenshotPath }

    /// Composites the main window and any child windows (the popover) into one
    /// PNG, positioned by their screen frames. (CGWindowListCreateImage is
    /// gone in macOS 15 and ScreenCaptureKit needs entitlements/async.)
    private func captureCompositing(window: NSWindow) {
        var windows: [NSWindow] = [window]
        windows.append(contentsOf: window.childWindows ?? [])
        let union = windows.reduce(NSRect.null) { $0.union($1.frame) }
        guard !union.isEmpty,
              let combined = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(union.width), pixelsHigh: Int(union.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: combined)
        for win in windows {
            guard let view = win.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            // window frames are bottom-left origin; flip into the combined rep
            let x = win.frame.minX - union.minX
            let y = union.maxY - win.frame.maxY
            rep.draw(in: NSRect(x: x, y: y, width: win.frame.width, height: win.frame.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = combined.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: screenshotPath))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "diffy — @mention test"
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 380, height: 160))
        let tv = MentionTextView(frame: scroll.bounds)
        tv.members = [
            GitLabUser(username: "jost", name: "Jost Joller"),
            GitLabUser(username: "jo", name: "Jo Helmuth"),
            GitLabUser(username: "portmann", name: "Samuel Portmann"),
            GitLabUser(username: "sniederhauser", name: "Stefan Niederhauser"),
        ]
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.string = "Looks good, @jo"
        scroll.documentView = tv
        scroll.borderType = .bezelBorder
        window.contentView?.addSubview(scroll)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.textView = tv

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.triggerMentionForTest()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.captureCompositing(window: window)
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let session: DiffSession?      // nil = start with the branch wizard
    let wizardGit: Git?
    let paths: [String]
    let noFetch: Bool
    let screenshotPath: String?
    let initialFileIndex: Int
    let initialChangeJumps: Int
    let autoConfirm: Bool
    let expandAllOnLaunch: Bool
    let collapseFoldersOnLaunch: Bool
    let copyLinesRange: ClosedRange<Int>?
    let fileFilterQuery: String?
    let showCommentsOnLaunch: Bool
    var windowController: MainWindowController?
    var wizardController: WizardWindowController?

    init(session: DiffSession?, wizardGit: Git? = nil, paths: [String] = [],
         noFetch: Bool = false,
         screenshotPath: String?, initialFileIndex: Int = 0,
         initialChangeJumps: Int = 0, autoConfirm: Bool = false,
         expandAllOnLaunch: Bool = false, collapseFoldersOnLaunch: Bool = false,
         copyLinesRange: ClosedRange<Int>? = nil, fileFilterQuery: String? = nil,
         showCommentsOnLaunch: Bool = false) {
        self.session = session
        self.wizardGit = wizardGit
        self.paths = paths
        self.noFetch = noFetch
        self.screenshotPath = screenshotPath
        self.initialFileIndex = initialFileIndex
        self.initialChangeJumps = initialChangeJumps
        self.autoConfirm = autoConfirm
        self.expandAllOnLaunch = expandAllOnLaunch
        self.collapseFoldersOnLaunch = collapseFoldersOnLaunch
        self.copyLinesRange = copyLinesRange
        self.fileFilterQuery = fileFilterQuery
        self.showCommentsOnLaunch = showCommentsOnLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if let session = session {
            openMainWindow(session: session)
        } else if let git = wizardGit {
            let wizard = WizardWindowController(git: git, paths: paths, noFetch: noFetch) { [weak self] session in
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
            var delay = autoConfirm ? 1.8 : 0.8
            if showCommentsOnLaunch { delay += 0.6 }
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
        if let query = fileFilterQuery {
            wc.sidebarVC.applyFilterForTest(query)
        }
        if showCommentsOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                wc.contentVC.showAllCommentsForTest()
            }
        }
        if let range = copyLinesRange {
            // Headless test path: select rows in the right pane, copy, print.
            let pane = wc.contentVC.rightPane
            pane.table.selectRowIndexes(IndexSet(integersIn: range), byExtendingSelection: false)
            pane.copySelectedLines()
            print(NSPasteboard.general.string(forType: .string) ?? "<empty pasteboard>")
            NSApp.terminate(nil)
        }
        if let wizard = wizardController {
            wizardController = nil
            wizard.close()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func captureScreenshot(to path: String) {
        guard let targetWindow = windowController?.window ?? wizardController?.window else { return }
        // Composite the window with any child windows (popovers) so overlays
        // like the comments list are captured too.
        var windows: [NSWindow] = [targetWindow]
        windows.append(contentsOf: targetWindow.childWindows ?? [])
        if windows.count == 1 {
            guard let view = targetWindow.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            return
        }
        let union = windows.reduce(NSRect.null) { $0.union($1.frame) }
        guard !union.isEmpty,
              let combined = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(union.width), pixelsHigh: Int(union.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: combined)
        for win in windows {
            guard let view = win.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: NSRect(x: win.frame.minX - union.minX,
                                y: union.maxY - win.frame.maxY,
                                width: win.frame.width, height: win.frame.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = combined.representation(using: .png, properties: [:]) {
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

        // Standard Edit menu: without it, ⌘C/⌘V/⌘X/⌘A/⌘Z don't reach text
        // fields (comment dialogs, wizard search) or the diff panes.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

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
