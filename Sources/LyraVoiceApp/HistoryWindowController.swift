import AppKit
import LyraVoiceCore

/// Окно истории диктовок: список записей (дата · модель · длительность · слова · текст)
/// с копированием и удалением. Данные — из `HistoryStore` (JSONL).
@MainActor
final class HistoryWindowController: NSWindowController {
    private let store: HistoryStore
    private var entries: [DictationEntry] = []

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: L.t("История пуста", "History is empty"))
    private let copyButton = NSButton(title: L.t("Копировать", "Copy"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L.t("Удалить", "Delete"), target: nil, action: nil)
    private let clearButton = NSButton(title: L.t("Очистить всё", "Clear all"), target: nil, action: nil)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    init(store: HistoryStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L.t("История диктовок", "Dictation history")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        reload()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        entries = (try? store.all()) ?? []
        tableView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        updateButtons()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = DS.Color.base.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 86
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.selectionHighlightStyle = .regular
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(copySelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        content.addSubview(scroll)

        emptyLabel.font = DS.Font.text(14)
        emptyLabel.textColor = DS.Color.textTertiary
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        for button in [copyButton, deleteButton, clearButton] {
            button.bezelStyle = .rounded
            button.font = DS.Font.text(13, weight: .medium)
        }
        copyButton.target = self; copyButton.action = #selector(copySelected)
        copyButton.keyEquivalent = "\r"
        deleteButton.target = self; deleteButton.action = #selector(deleteSelected)
        clearButton.target = self; clearButton.action = #selector(clearAll)

        let buttonRow = NSStackView(views: [clearButton, NSView(), deleteButton, copyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            buttonRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
    }

    private func updateButtons() {
        let hasSelection = tableView.selectedRow >= 0
        copyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        clearButton.isEnabled = !entries.isEmpty
    }

    private var selectedEntry: DictationEntry? {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return nil }
        return entries[row]
    }

    // MARK: - Actions

    @objc private func copySelected() {
        guard let entry = selectedEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    @objc private func deleteSelected() {
        guard let entry = selectedEntry else { return }
        try? store.delete(id: entry.id)
        reload()
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = L.t("Очистить всю историю?", "Clear all history?")
        alert.informativeText = L.t("Все записи будут удалены без возможности восстановления.", "All entries will be deleted permanently.")
        alert.addButton(withTitle: L.t("Очистить", "Clear"))
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.clear()
        reload()
    }
}

extension HistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = HistoryRowView()
        let words = entry.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let meta = "\(Self.dateFormatter.string(from: entry.createdAt)) · \(entry.modelID) · \(Int(entry.durationSeconds.rounded())) \(L.t("с", "s")) · \(words) \(L.t("сл.", "w"))"
        cell.configure(meta: meta, text: entry.text)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }
}

/// Строка истории: мета сверху, текст-превью снизу, на стеклянной карточке.
@MainActor
private final class HistoryRowView: NSView {
    private let card = NSView()
    private let metaLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = DS.Color.glassStrokeSoft.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        metaLabel.font = DS.Font.mono(11, weight: .medium)
        metaLabel.textColor = DS.Color.textTertiary
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(metaLabel)

        textLabel.font = DS.Font.text(13)
        textLabel.textColor = DS.Color.textPrimary
        textLabel.maximumNumberOfLines = 3
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            metaLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            metaLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            metaLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            textLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 6),
            textLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(meta: String, text: String) {
        metaLabel.stringValue = meta
        textLabel.stringValue = text
    }
}
