//
//  MenuTextItemView.swift
//  AndroLaunch
//
//  Shared geometry for rows that can contain user data (device names, errors).
//  The status menu keeps one fixed width; anything longer wraps onto a second
//  line instead of stretching the whole menu across the screen.
//

import AppKit

enum MenuRowMetrics {
    /// Fixed content width for the status menu.
    static let width: CGFloat = 300
    static let leadingInset: CGFloat = 14
    static let iconSize: CGFloat = 16
    static let iconGap: CGFloat = 8
    static let trailingInset: CGFloat = 14

    static var textLeading: CGFloat { leadingInset + iconSize + iconGap }
    static var textWidth: CGFloat { width - textLeading - trailingInset }

    /// Row height for text that wraps to at most `lineLimit` lines.
    static func rowHeight(
        for text: String, font: NSFont, lineLimit: Int, width: CGFloat? = nil
    ) -> CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width ?? textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let lines = max(1, min(lineLimit, Int((bounding.height / lineHeight).rounded(.up))))
        return max(20, CGFloat(lines) * lineHeight + 4)
    }
}

/// A menu row with an optional SF Symbol and text that wraps to at most two
/// lines inside `MenuRowMetrics.width`.
final class MenuTextItemView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let lineLimit: Int
    private let textColor: NSColor

    /// Top-left origin so frame math matches menu layout reading order.
    override var isFlipped: Bool { true }

    init(
        text: String,
        symbolName: String? = nil,
        textColor: NSColor = .labelColor,
        lineLimit: Int = 2
    ) {
        self.lineLimit = lineLimit
        self.textColor = textColor

        let font = NSFont.menuFont(ofSize: 14)
        let height = MenuRowMetrics.rowHeight(for: text, font: font, lineLimit: lineLimit)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuRowMetrics.width, height: height))

        label.stringValue = text
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = lineLimit
        label.usesSingleLineMode = false
        label.isBordered = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.allowsDefaultTighteningForTruncation = true
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.frame = NSRect(
            x: MenuRowMetrics.textLeading, y: 0,
            width: MenuRowMetrics.textWidth, height: height)
        addSubview(label)

        if let symbolName {
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            iconView.contentTintColor = textColor
            iconView.imageScaling = .scaleProportionallyDown
            iconView.frame = NSRect(
                x: MenuRowMetrics.leadingInset,
                y: (height - MenuRowMetrics.iconSize) / 2,
                width: MenuRowMetrics.iconSize,
                height: MenuRowMetrics.iconSize)
            addSubview(iconView)
        }

        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-lays out after the content changes (for example "Reconnect" becoming
    /// "Reconnecting…"). Height is recomputed so a second line is never clipped.
    func update(text: String, textColor: NSColor? = nil) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        if let textColor { label.textColor = textColor }

        let font = label.font ?? NSFont.menuFont(ofSize: 14)
        let height = MenuRowMetrics.rowHeight(for: text, font: font, lineLimit: lineLimit)
        guard height != frame.height else { return }
        frame.size.height = height
        label.frame = NSRect(
            x: MenuRowMetrics.textLeading, y: 0,
            width: MenuRowMetrics.textWidth, height: height)
        iconView.frame.origin.y = (height - MenuRowMetrics.iconSize) / 2
        setAccessibilityLabel(text)
    }
}
