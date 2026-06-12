import AppKit
import ApplicationServices
import LyraVoiceCore

@MainActor
enum PasteOutcome: Equatable {
    /// Текст вставлен в активное поле.
    case pasted
    /// Скопировано, но автовставка невозможна: нет доступа к «Универсальному доступу».
    case copiedNeedsAccess
    /// Скопировано, но курсор не в текстовом поле — вставлять некуда.
    /// Показываем карточку результата с текстом и кнопкой «Скопировать».
    case copiedNoTextField
}

@MainActor
final class ClipboardPasteService {
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Копирует текст и пытается вставить его в `targetApp` (приложение, активное в
    /// момент начала диктовки). Результат приходит в `completion` асинхронно, потому
    /// что нужно дождаться активации цели и проверить фокус.
    ///
    /// Логика:
    /// 1. Нет Accessibility → `.copiedNeedsAccess`.
    /// 2. Есть доступ, но курсор НЕ в редактируемом поле → `.copiedNoTextField`.
    /// 3. Есть доступ и поле в фокусе → вставка выбранным методом → `.pasted`.
    func copyAndPaste(
        _ text: String,
        into targetApp: NSRunningApplication?,
        autoEnter: Bool = false,
        pasteMode: PasteMode = .clipboard,
        completion: @escaping (PasteOutcome) -> Void
    ) {
        copy(text)

        guard AccessibilityPermission.isTrusted else {
            completion(.copiedNeedsAccess)
            return
        }

        let target = validTarget(targetApp)
        target?.activate(options: [.activateIgnoringOtherApps])

        let delay = target != nil ? 0.18 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.hasFocusedEditableElement() {
                switch pasteMode {
                case .clipboard:
                    self.sendPasteShortcut()
                case .simulateTyping:
                    self.simulateTyping(text)
                }
                if autoEnter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.sendKey(0x24) // Return
                    }
                }
                completion(.pasted)
            } else {
                completion(.copiedNoTextField)
            }
        }
    }

    /// Симулирует посимвольный ввод через CGEvent (Unicode, не зависит от раскладки).
    /// Работает в Terminal, iTerm и других приложениях, блокирующих вставку через буфер.
    /// Между символами — микро-пауза: без неё некоторые приложения (Electron/веб-поля)
    /// не успевают обработать события и «съедают» хвост длинного текста.
    private func simulateTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            var uniChars: [UniChar]
            if scalar.value <= 0xFFFF {
                uniChars = [UniChar(scalar.value)]
            } else {
                // Суррогатная пара для символов выше U+FFFF (emoji и пр.)
                let v = scalar.value - 0x10000
                uniChars = [UniChar(0xD800 + (v >> 10)), UniChar(0xDC00 + (v & 0x3FF))]
            }
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                up.post(tap: .cghidEventTap)
            }
            usleep(1200)
        }
    }

    private func validTarget(_ targetApp: NSRunningApplication?) -> NSRunningApplication? {
        guard let targetApp,
              targetApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !targetApp.isTerminated else { return nil }
        return targetApp
    }

    /// Есть ли сейчас в системе сфокусированный редактируемый элемент (текстовое поле,
    /// область текста или элемент с настраиваемым значением). Требует Accessibility.
    private func hasFocusedEditableElement() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        // CFTypeRef → AXUIElement (тип проверен системой).
        let element = focused as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String,
           role == (kAXTextFieldRole as String) ||
           role == (kAXTextAreaRole as String) ||
           role == (kAXComboBoxRole as String) {
            return true
        }

        // Фолбэк: значение элемента можно менять → считаем редактируемым (Electron/веб).
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return false
    }

    private func sendKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func sendPasteShortcut() {
        // combinedSessionState: синтетический ⌘V не смешивается с физическим
        // состоянием клавиатуры (важно после отпускания Fn в push-to-talk).
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandKey: CGKeyCode = 0x37  // ⌘ (left command)
        let vKey: CGKeyCode = 0x09        // V

        let events: [CGEvent?] = [
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            { let e = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true); e?.flags = .maskCommand; return e }(),
            { let e = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false); e?.flags = .maskCommand; return e }(),
            CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        ]

        for event in events {
            event?.post(tap: .cghidEventTap)
        }
    }
}
