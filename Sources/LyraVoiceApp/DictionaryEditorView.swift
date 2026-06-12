import AppKit
import LyraVoiceCore

/// Интерактивный редактор словаря замен в стиле Superwhisper:
/// проходная строчка сверху + список строк «сказали → вставится» отдельным блоком ниже.
/// Добавление — по Enter или по «+», удаление — по ✕ (проявляется при наведении).
/// Никаких кнопок «Сохранить»: изменения коммитятся сразу через `onChange`.
@MainActor
final class DictionaryEditorView: NSView, NSTextFieldDelegate {

    /// Вызывается при любом изменении набора замен (добавили/удалили/отредактировали).
    var onChange: (([DictionaryEntry]) -> Void)?

    private var entries: [DictionaryEntry] = []

    private let listStack = NSStackView()
    private let entriesContainer = NSView()
    private let addRow: DictionaryRowView

    override init(frame frameRect: NSRect) {
        addRow = DictionaryRowView(
            from: "", to: "", isAddRow: true,
            fromPlaceholder: L.t("Слово или фраза", "Word or phrase"),
            toPlaceholder: L.t("Чем заменить", "Replace with")
        )
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false

        styleContainer(addRow)
        styleContainer(entriesContainer)
        entriesContainer.translatesAutoresizingMaskIntoConstraints = false
        entriesContainer.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: entriesContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: entriesContainer.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: entriesContainer.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: entriesContainer.bottomAnchor),
        ])

        // Проходная строчка (всегда сверху): Enter / «+» добавляют запись.
        addRow.fromField.target = self
        addRow.fromField.action = #selector(commitAddRow)
        addRow.toField.target = self
        addRow.toField.action = #selector(commitAddRow)
        addRow.onTrailingButton = { [weak self] in self?.commitAddRow() }

        let container = NSStackView(views: [addRow, entriesContainer])
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            addRow.widthAnchor.constraint(equalTo: container.widthAnchor),
            entriesContainer.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
        entriesContainer.isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    private func styleContainer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = DS.Color.surfaceSunken.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = DS.Color.surfaceBorder.cgColor
    }

    // MARK: - Внешний API

    /// Обновляет список из настроек. Ничего не делает, если набор не изменился —
    /// иначе перестроение крадёт фокус во время ввода.
    func setEntries(_ newEntries: [DictionaryEntry]) {
        guard newEntries != entries else { return }
        entries = newEntries
        rebuildRows()
    }

    // MARK: - Сборка строк

    private func rebuildRows() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in entries {
            let row = makeEntryRow(from: entry.from, to: entry.to)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
        // У последней строки списка убираем нижний разделитель — его заменяет divider add-row.
        for (i, view) in listStack.arrangedSubviews.enumerated() {
            (view as? DictionaryRowView)?.showsBottomDivider = (i < listStack.arrangedSubviews.count - 1)
        }
        entriesContainer.isHidden = entries.isEmpty
    }

    private func makeEntryRow(from: String, to: String) -> DictionaryRowView {
        let row = DictionaryRowView(from: from, to: to, isAddRow: false,
                                    fromPlaceholder: "", toPlaceholder: "")
        row.fromField.delegate = self
        row.toField.delegate = self
        row.onTrailingButton = { [weak self, weak row] in
            guard let self, let row else { return }
            self.listStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            self.commitFromRows()
        }
        return row
    }

    // MARK: - Коммит

    /// Enter / «+» в проходной строчке: добавить новую запись и очистить поле ввода.
    @objc private func commitAddRow() {
        let from = addRow.fromField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { return }
        let to = addRow.toField.stringValue.trimmingCharacters(in: .whitespaces)

        let row = makeEntryRow(from: from, to: to)
        listStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true

        addRow.fromField.stringValue = ""
        addRow.toField.stringValue = ""
        commitFromRows()
        // Фокус остаётся в проходной строчке — можно сразу вводить следующую замену.
        window?.makeFirstResponder(addRow.fromField)
    }

    /// Существующая строка отредактирована (Enter/потеря фокуса) — пересобрать набор.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        // Поля проходной строчки коммитятся отдельно (по Enter), не на потерю фокуса.
        if field === addRow.fromField || field === addRow.toField { return }
        commitFromRows()
    }

    /// Считывает актуальные значения из всех строк списка и сообщает об изменении.
    private func commitFromRows() {
        let newEntries = listStack.arrangedSubviews.compactMap { ($0 as? DictionaryRowView)?.entry }
        entries = newEntries
        for (i, view) in listStack.arrangedSubviews.enumerated() {
            (view as? DictionaryRowView)?.showsBottomDivider = (i < listStack.arrangedSubviews.count - 1)
        }
        entriesContainer.isHidden = newEntries.isEmpty
        onChange?(newEntries)
    }
}

// MARK: - Строка словаря

/// Одна строка редактора: «откуда» → «куда» + хвостовая кнопка (✕ для записи, + для add-row).
/// Подсветка фона и проявление ✕ — при наведении. Разделители рисуются слоями.
@MainActor
final class DictionaryRowView: NSView {
    let fromField: DictField
    let toField: DictField
    var onTrailingButton: (() -> Void)?

    private let isAddRow: Bool
    private let arrow = NSTextField(labelWithString: "→")
    private let trailingButton = NSButton()
    private let bottomDivider = CALayer()
    private let topDivider = CALayer()
    private var tracking: NSTrackingArea?

    var showsBottomDivider = true { didSet { bottomDivider.isHidden = !showsBottomDivider } }
    var showsTopDivider = false { didSet { topDivider.isHidden = !showsTopDivider } }

    var entry: DictionaryEntry? {
        let f = fromField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return nil }
        let t = toField.stringValue.trimmingCharacters(in: .whitespaces)
        return DictionaryEntry(from: f, to: t)
    }

    init(from: String, to: String, isAddRow: Bool, fromPlaceholder: String, toPlaceholder: String) {
        self.isAddRow = isAddRow
        fromField = DictField(placeholder: fromPlaceholder)
        toField = DictField(placeholder: toPlaceholder)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        fromField.stringValue = from
        toField.stringValue = to

        arrow.font = DS.Font.text(13, weight: .medium)
        arrow.textColor = DS.Color.textTertiary
        arrow.alignment = .center
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Хвостовая кнопка: проходная строчка — явная кнопка «Добавить» (акцент, всегда видна),
        // записи — приглушённый «✕», проявляется при наведении. Раньше был непонятный «+».
        trailingButton.isBordered = false
        trailingButton.bezelStyle = .regularSquare
        trailingButton.target = self
        trailingButton.action = #selector(trailingTapped)
        trailingButton.translatesAutoresizingMaskIntoConstraints = false
        trailingButton.setContentHuggingPriority(.required, for: .horizontal)
        trailingButton.wantsLayer = true

        if isAddRow {
            trailingButton.imagePosition = .noImage
            trailingButton.attributedTitle = NSAttributedString(
                string: L.t("Добавить", "Add"),
                attributes: [.foregroundColor: NSColor.white, .font: DS.Font.text(12, weight: .semibold)]
            )
            trailingButton.layer?.backgroundColor = DS.Color.accent.cgColor
            trailingButton.layer?.cornerRadius = 7
            trailingButton.layer?.cornerCurve = .continuous
            trailingButton.alphaValue = 1
        } else {
            trailingButton.imagePosition = .imageOnly
            trailingButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L.t("Удалить", "Remove"))
            trailingButton.contentTintColor = DS.Color.textTertiary
            trailingButton.alphaValue = 0   // ✕ проявляется при наведении
        }

        let h = NSStackView(views: [fromField, arrow, toField, trailingButton])
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 10
        h.distribution = .fill
        h.translatesAutoresizingMaskIntoConstraints = false
        h.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: isAddRow ? 10 : 8)
        addSubview(h)

        fromField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var constraints: [NSLayoutConstraint] = [
            h.leadingAnchor.constraint(equalTo: leadingAnchor),
            h.trailingAnchor.constraint(equalTo: trailingAnchor),
            h.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 42),
            fromField.widthAnchor.constraint(equalTo: toField.widthAnchor),
        ]
        if isAddRow {
            constraints += [
                trailingButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
                trailingButton.heightAnchor.constraint(equalToConstant: 28),
            ]
        } else {
            constraints += [
                trailingButton.widthAnchor.constraint(equalToConstant: 22),
                trailingButton.heightAnchor.constraint(equalToConstant: 22),
            ]
        }
        NSLayoutConstraint.activate(constraints)

        for divider in [bottomDivider, topDivider] {
            divider.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.addSublayer(divider)
        }
        topDivider.isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    @objc private func trailingTapped() { onTrailingButton?() }

    override func layout() {
        super.layout()
        bottomDivider.frame = NSRect(x: 12, y: 0, width: bounds.width - 12, height: 0.5)
        topDivider.frame = NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
    }

    // MARK: Наведение

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        if !isAddRow { animateTrailingAlpha(to: 1) }
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        if !isAddRow { animateTrailingAlpha(to: 0) }
    }

    private func animateTrailingAlpha(to value: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            trailingButton.animator().alphaValue = value
        }
    }
}

// MARK: - Поле ввода словаря

/// Прозрачное однострочное поле для строк словаря (без рамки/фона, с подсказкой-плейсхолдером).
@MainActor
final class DictField: NSTextField {
    init(placeholder: String) {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = DS.Font.text(13)
        textColor = DS.Color.textPrimary
        translatesAutoresizingMaskIntoConstraints = false
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        lineBreakMode = .byTruncatingTail
        if !placeholder.isEmpty {
            placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: DS.Color.textTertiary, .font: DS.Font.text(13)]
            )
        }
    }
    required init?(coder: NSCoder) { nil }
}
