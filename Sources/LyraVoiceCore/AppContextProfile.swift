import Foundation

public enum TargetTextFormat: String, Codable, Equatable, Sendable {
    case plainText
    case chatMessage
    case email
    case code
    case terminalCommand
    case markdown
    case password
    case url
    case searchQuery
    case filePath
    case documentText
}

public struct ScreenContextSnapshot: Codable, Equatable, Sendable {
    public var focusedRole: String?
    public var focusedSubrole: String?
    public var focusedTitle: String?
    public var focusedDescription: String?
    public var focusedValueSnippet: String?
    public var selectedTextSnippet: String?
    public var clipboardTextSnippet: String?
    public var textBeforeCursorSnippet: String?
    public var textAfterCursorSnippet: String?
    public var isSecureTextEntry: Bool

    public init(
        focusedRole: String? = nil,
        focusedSubrole: String? = nil,
        focusedTitle: String? = nil,
        focusedDescription: String? = nil,
        focusedValueSnippet: String? = nil,
        selectedTextSnippet: String? = nil,
        clipboardTextSnippet: String? = nil,
        textBeforeCursorSnippet: String? = nil,
        textAfterCursorSnippet: String? = nil,
        isSecureTextEntry: Bool = false
    ) {
        self.focusedRole = Self.trimmedNonEmpty(focusedRole)
        self.focusedSubrole = Self.trimmedNonEmpty(focusedSubrole)
        self.focusedTitle = Self.trimmedNonEmpty(focusedTitle)
        self.focusedDescription = Self.trimmedNonEmpty(focusedDescription)
        self.focusedValueSnippet = Self.truncatedSnippet(focusedValueSnippet)
        self.selectedTextSnippet = Self.truncatedSnippet(selectedTextSnippet)
        self.clipboardTextSnippet = Self.truncatedSnippet(clipboardTextSnippet)
        self.textBeforeCursorSnippet = Self.truncatedSnippet(textBeforeCursorSnippet)
        self.textAfterCursorSnippet = Self.truncatedSnippet(textAfterCursorSnippet)
        self.isSecureTextEntry = isSecureTextEntry || Self.looksSensitive([
            focusedRole,
            focusedSubrole,
            focusedTitle,
            focusedDescription
        ])
    }

    public func redactedForPrivacy() -> ScreenContextSnapshot {
        guard isSecureTextEntry else { return self }
        return ScreenContextSnapshot(
            focusedRole: focusedRole,
            focusedSubrole: focusedSubrole,
            focusedTitle: focusedTitle,
            focusedDescription: focusedDescription,
            isSecureTextEntry: true
        )
    }

    public var combinedContextText: String {
        [
            focusedTitle,
            focusedDescription,
            focusedValueSnippet,
            selectedTextSnippet,
            clipboardTextSnippet,
            textBeforeCursorSnippet,
            textAfterCursorSnippet
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncatedSnippet(_ value: String?, limit: Int = 500) -> String? {
        guard let trimmed = trimmedNonEmpty(value) else { return nil }
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit))
    }

    private static func looksSensitive(_ values: [String?]) -> Bool {
        let haystack = values
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return haystack.contains("secure")
            || haystack.contains("password")
            || haystack.contains("passcode")
            || haystack.contains("парол")
            || haystack.contains("код доступа")
            || haystack.contains("секрет")
    }
}

public struct AppContextProfile: Codable, Equatable, Sendable {
    public var format: TargetTextFormat
    public var displayName: String
    public var screenContext: ScreenContextSnapshot?
    public var isSensitive: Bool

    public init(
        format: TargetTextFormat = .plainText,
        displayName: String = "",
        screenContext: ScreenContextSnapshot? = nil,
        isSensitive: Bool = false
    ) {
        self.format = format
        self.displayName = displayName
        self.screenContext = screenContext?.redactedForPrivacy()
        self.isSensitive = isSensitive || format == .password || screenContext?.isSecureTextEntry == true
    }

    public static func profile(
        bundleIdentifier: String?,
        localizedName: String?,
        screenContext: ScreenContextSnapshot? = nil
    ) -> AppContextProfile {
        let bundle = (bundleIdentifier ?? "").lowercased()
        let name = localizedName ?? ""
        let sanitizedContext = screenContext?.redactedForPrivacy()

        if sanitizedContext?.isSecureTextEntry == true {
            return AppContextProfile(
                format: .password,
                displayName: name,
                screenContext: sanitizedContext,
                isSensitive: true
            )
        }

        if let refinedFormat = refinedFormat(from: sanitizedContext) {
            return AppContextProfile(
                format: refinedFormat,
                displayName: name,
                screenContext: sanitizedContext
            )
        }

        switch bundle {
        case "com.apple.mail",
             "com.microsoft.outlook",
             "com.readdle.smartemail-mac",
             "com.google.gmail":
            return AppContextProfile(format: .email, displayName: name, screenContext: sanitizedContext)

        case "com.apple.terminal",
             "com.googlecode.iterm2",
             "dev.warp.warp":
            return AppContextProfile(format: .terminalCommand, displayName: name, screenContext: sanitizedContext)

        case "com.microsoft.vscode",
             "com.todesktop.230313mzl4w4u92",
             "com.jetbrains.intellij",
             "com.jetbrains.pycharm",
             "com.jetbrains.webstorm",
             "com.jetbrains.rider",
             "com.apple.dt.xcode":
            return AppContextProfile(format: .code, displayName: name, screenContext: sanitizedContext)

        case "com.tinyspeck.slackmacgap",
             "com.apple.messages",
             "org.telegram.desktop",
             "ru.keepcoder.telegram",
             "net.whatsapp.whatsapp",
             "com.discord",
             "com.hnc.discord":
            return AppContextProfile(format: .chatMessage, displayName: name, screenContext: sanitizedContext)

        case "md.obsidian",
             "notion.id",
             "com.sublimetext.4",
             "com.barebones.bbedit":
            return AppContextProfile(format: .markdown, displayName: name, screenContext: sanitizedContext)

        default:
            return AppContextProfile(format: .plainText, displayName: name, screenContext: sanitizedContext)
        }
    }

    private static func refinedFormat(from context: ScreenContextSnapshot?) -> TargetTextFormat? {
        guard let context else { return nil }
        let role = (context.focusedRole ?? "").lowercased()
        let title = (context.focusedTitle ?? "").lowercased()
        let description = (context.focusedDescription ?? "").lowercased()
        let combined = context.combinedContextText
        let combinedLower = combined.lowercased()

        if looksLikeURLContext(title: title, description: description, text: combinedLower) {
            return .url
        }
        if looksLikeSearchContext(title: title, description: description) {
            return .searchQuery
        }
        if looksLikeFilePath(combined) {
            return .filePath
        }
        if role.contains("textarea") || role.contains("text area") || role.contains("axtextarea") {
            return .documentText
        }
        return nil
    }

    private static func looksLikeURLContext(title: String, description: String, text: String) -> Bool {
        title.contains("address")
            || title.contains("url")
            || title.contains("адрес")
            || description.contains("address")
            || description.contains("url")
            || text.contains("http://")
            || text.contains("https://")
            || text.contains("www.")
    }

    private static func looksLikeSearchContext(title: String, description: String) -> Bool {
        title.contains("search")
            || title.contains("поиск")
            || description.contains("search")
            || description.contains("поиск")
    }

    private static func looksLikeFilePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/")
            || trimmed.hasPrefix("~/")
            || trimmed.contains("/Users/")
            || trimmed.contains("\\")
    }
}
