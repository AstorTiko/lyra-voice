import AppKit
import ApplicationServices
import LyraVoiceCore

@MainActor
final class ScreenContextReader {
    func snapshot(smartContextEnabled: Bool) -> ScreenContextSnapshot? {
        guard smartContextEnabled, AccessibilityPermission.isTrusted else { return nil }

        guard let focusedContext = readFocusedElement() else { return nil }

        let clipboardSnippet = focusedContext.isSecureTextEntry != true
            ? NSPasteboard.general.string(forType: .string)
            : nil

        return ScreenContextSnapshot(
            focusedRole: focusedContext.role,
            focusedSubrole: focusedContext.subrole,
            focusedTitle: focusedContext.title,
            focusedDescription: focusedContext.description,
            focusedValueSnippet: focusedContext.isSecureTextEntry ? nil : focusedContext.value,
            selectedTextSnippet: focusedContext.isSecureTextEntry ? nil : focusedContext.selectedText,
            clipboardTextSnippet: clipboardSnippet,
            textBeforeCursorSnippet: focusedContext.isSecureTextEntry ? nil : focusedContext.textBeforeCursor,
            textAfterCursorSnippet: focusedContext.isSecureTextEntry ? nil : focusedContext.textAfterCursor,
            isSecureTextEntry: focusedContext.isSecureTextEntry
        )
        .redactedForPrivacy()
    }

    private func readFocusedElement() -> FocusedContext? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        let role = axString(element, kAXRoleAttribute)
        let subrole = axString(element, kAXSubroleAttribute)
        let title = axString(element, kAXTitleAttribute)
        let description = axString(element, kAXDescriptionAttribute)
        let secure = isSecure(role: role, subrole: subrole, title: title, description: description)
        let editable = isEditable(element: element, role: role)
        let value = secure || !editable ? nil : axString(element, kAXValueAttribute)
        let selectedRange = secure || !editable ? nil : axRange(element, kAXSelectedTextRangeAttribute)
        let cursorContext = cursorSnippets(in: value, selectedRange: selectedRange)

        return FocusedContext(
            role: role,
            subrole: subrole,
            title: title,
            description: description,
            value: value,
            selectedText: secure || !editable ? nil : axString(element, kAXSelectedTextAttribute),
            textBeforeCursor: cursorContext.before,
            textAfterCursor: cursorContext.after,
            isSecureTextEntry: secure
        )
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        if let value = ref as? String { return value }
        if let value = ref { return String(describing: value) }
        return nil
    }

    private func axRange(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let rawValue = ref,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else { return nil }
        let value = rawValue as! AXValue
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func cursorSnippets(in value: String?, selectedRange: CFRange?) -> (before: String?, after: String?) {
        guard let value, let selectedRange, selectedRange.location >= 0 else { return (nil, nil) }
        let utf16Count = value.utf16.count
        let startOffset = min(selectedRange.location, utf16Count)
        let endOffset = min(max(selectedRange.location + selectedRange.length, startOffset), utf16Count)

        guard let startUTF16 = value.utf16.index(value.utf16.startIndex, offsetBy: startOffset, limitedBy: value.utf16.endIndex),
              let endUTF16 = value.utf16.index(value.utf16.startIndex, offsetBy: endOffset, limitedBy: value.utf16.endIndex),
              let start = String.Index(startUTF16, within: value),
              let end = String.Index(endUTF16, within: value) else {
            return (nil, nil)
        }

        let before = String(value[..<start])
        let after = String(value[end...])
        return (String(before.suffix(500)), String(after.prefix(500)))
    }

    private func isEditable(element: AXUIElement, role: String?) -> Bool {
        if let role,
           role == (kAXTextFieldRole as String) ||
           role == (kAXTextAreaRole as String) ||
           role == (kAXComboBoxRole as String) {
            return true
        }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return false
    }

    private func isSecure(
        role: String?,
        subrole: String?,
        title: String?,
        description: String?
    ) -> Bool {
        let haystack = [role, subrole, title, description]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return haystack.contains("secure")
            || haystack.contains("password")
            || haystack.contains("passcode")
            || haystack.contains("парол")
            || haystack.contains("код доступа")
    }
}

private struct FocusedContext {
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var value: String?
    var selectedText: String?
    var textBeforeCursor: String?
    var textAfterCursor: String?
    var isSecureTextEntry: Bool
}
