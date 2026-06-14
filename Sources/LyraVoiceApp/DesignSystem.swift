import AppKit

/// Дизайн-система приложения: тёмная тема + Liquid Glass (стиль Apple), шрифт SF Pro.
/// Единый источник цветов, типографики, скруглений и стеклянных подложек, чтобы
/// весь UI был консистентным и менялся из одного места.
@MainActor
enum DS {

    // MARK: - Цвета (restrained dark utility)

    enum Color {
        /// Почти чёрная нейтральная база без синего AI-тинта.
        static let base = NSColor(red: 0.028, green: 0.028, blue: 0.032, alpha: 1)
        /// Тёмный нейтральный тинт поверх размытия — глубина без цветного glow.
        static let glassTint = NSColor(red: 0.045, green: 0.045, blue: 0.052, alpha: 0.58)
        /// Светящаяся кромка стекла (верхний внутренний хайлайт).
        static let glassStroke = NSColor.white.withAlphaComponent(0.14)
        static let glassStrokeSoft = NSColor.white.withAlphaComponent(0.08)
        static let glassEdgeBright = NSColor.white.withAlphaComponent(0.44)
        static let glassSpecular = NSColor.white.withAlphaComponent(0.20)

        /// Единственный продуктовый акцент — бирюза, без фиолетовых тонов.
        static let accent = NSColor(red: 0.122, green: 0.722, blue: 0.788, alpha: 1)      // #1FB8C9
        static let accentSoft = NSColor(red: 0.122, green: 0.722, blue: 0.788, alpha: 0.80)
        /// Имена для градиентов оверлея: teal → cyan (раньше violet → cyan).
        static let accentCyan = NSColor(red: 0.098, green: 0.851, blue: 0.878, alpha: 1)  // #19D9E0
        static let accentViolet = NSColor(red: 0.090, green: 0.588, blue: 0.682, alpha: 1) // #1796AE (teal)

        /// Семантика статусов.
        static let success = NSColor(red: 0.40, green: 0.86, blue: 0.62, alpha: 1)
        static let info = NSColor(red: 0.098, green: 0.851, blue: 0.878, alpha: 1)        // #19D9E0 (cyan, было violet-blue)
        static let danger = NSColor(red: 0.96, green: 0.36, blue: 0.40, alpha: 1)

        /// Текст.
        static let textPrimary = NSColor.white
        static let textSecondary = NSColor.white.withAlphaComponent(0.62)
        static let textTertiary = NSColor.white.withAlphaComponent(0.40)

        /// Поверхность карточки на тёмном фоне — плоский neutral charcoal.
        static let surface = NSColor(red: 0.075, green: 0.075, blue: 0.082, alpha: 1)
        /// Утопленная поверхность (вложенные панели, поля ввода) — чуть темнее карточки и фона.
        static let surfaceSunken = NSColor(red: 0.045, green: 0.045, blue: 0.052, alpha: 1)
        /// Кромка поверхностей — тонкая, чтобы карточка отделялась от фона без «грязи».
        static let surfaceBorder = NSColor.white.withAlphaComponent(0.07)

        /// Поверхности кнопок на стекле. Hover заметно ярче базового — чтобы
        /// наведение читалось однозначно.
        static let controlBackground = NSColor.white.withAlphaComponent(0.09)
        static let controlBackgroundHover = NSColor.white.withAlphaComponent(0.22)
        /// Общая подсветка наведения для выбираемых строк/тайлов (заметная).
        static let hoverFill = NSColor.white.withAlphaComponent(0.10)
    }

    // MARK: - Типографика (SF Pro — системный шрифт macOS)

    enum Font {
        /// Дизайн шрифта ЗАГОЛОВКОВ. Тело и заголовки — единый SF Pro (без засечек).
        /// `.default` = SF Pro, `.rounded` = SF Pro Rounded, `.serif` = New York.
        /// Тико: засечки убрать — оставляем чистый системный SF Pro.
        static let headingDesign: NSFontDescriptor.SystemDesign = .default

        /// Заголовочный шрифт выбранного дизайна (New York / SF Rounded), системный — без бандла.
        static func heading(_ size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(headingDesign) {
                return NSFont(descriptor: d, size: size) ?? base
            }
            return base
        }

        static func display(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }
        static func text(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }
        /// Моноширинные цифры — для таймеров/счётчиков, чтобы не «прыгали».
        static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
            NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - Геометрия

    enum Radius {
        static let pill = 14.0
        static let panel = 16.0
        static let control = 9.0
    }

    enum Space {
        static let xs = 4.0
        static let sm = 8.0
        static let md = 12.0
        static let lg = 16.0
    }

    // MARK: - Liquid Glass

    /// Стиль стеклянной подложки — задаёт материал размытия, тинт, кромку и блики.
    /// Разные поверхности требуют разного: парящий оверлей — почти невидимая кромка,
    /// сайдбар — настоящая полупрозрачность desktop, карточки — спокойное матовое стекло.
    struct GlassStyle {
        var material: NSVisualEffectView.Material
        var blending: NSVisualEffectView.BlendingMode
        var tint: NSColor
        var borderColor: NSColor
        var borderWidth: CGFloat
        var edgeOpacity: Float
        var specularOpacity: Float
        var shadowOpacity: Float
        var shadowRadius: CGFloat

        /// Парящий оверлей записи: тёмная капсула, кромка почти незаметна.
        static let overlay = GlassStyle(
            material: .hudWindow, blending: .behindWindow,
            tint: NSColor(white: 0.02, alpha: 0.70),
            borderColor: NSColor.white.withAlphaComponent(0.06), borderWidth: 0.5,
            edgeOpacity: 0.05, specularOpacity: 0.07,
            shadowOpacity: 0.26, shadowRadius: 16
        )

        /// Сайдбар: полупрозрачное frosted-стекло, заметно светлее тёмного контента,
        /// чтобы читалось как отдельная стеклянная панель (виден размытый стол).
        static let sidebar = GlassStyle(
            material: .sidebar, blending: .behindWindow,
            tint: NSColor(white: 0.16, alpha: 0.34),
            borderColor: .clear, borderWidth: 0,
            edgeOpacity: 0, specularOpacity: 0,
            shadowOpacity: 0, shadowRadius: 0
        )

        /// Карточка/результат: спокойное матовое стекло без жирных бликов.
        static let panel = GlassStyle(
            material: .hudWindow, blending: .behindWindow,
            tint: NSColor(white: 0.05, alpha: 0.55),
            borderColor: NSColor.white.withAlphaComponent(0.10), borderWidth: 1,
            edgeOpacity: 0.06, specularOpacity: 0.07,
            shadowOpacity: 0.12, shadowRadius: 8
        )

        /// Компактный попап (пикеры выбора): то же матовое стекло, что `panel`,
        /// но без бликов/глоу — маленький контейнер не должен «гореть».
        static let popover = GlassStyle(
            material: .hudWindow, blending: .behindWindow,
            tint: NSColor(white: 0.05, alpha: 0.60),
            borderColor: NSColor.white.withAlphaComponent(0.12), borderWidth: 1,
            edgeOpacity: 0, specularOpacity: 0,
            shadowOpacity: 0.22, shadowRadius: 14
        )
    }

    /// Создаёт стеклянную подложку (Apple Liquid Glass, тёмный вариант):
    /// размытие фона + ровный тинт + кромка + мягкая тень. Возвращает контейнер,
    /// в который кладётся остальной контент.
    static func makeGlassContainer(cornerRadius: CGFloat, style: GlassStyle = .panel) -> GlassContainerView {
        GlassContainerView(cornerRadius: cornerRadius, style: style)
    }

    static func configureLiquidGlassLayer(_ layer: CALayer?, cornerRadius: CGFloat, active: Bool = false) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.105 : 0.065).cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = (active ? Color.accent.withAlphaComponent(0.48) : Color.glassStroke).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = active ? 0.22 : 0.14
        layer?.shadowRadius = active ? 12 : 8
        layer?.shadowOffset = NSSize(width: 0, height: active ? 5 : 3)
    }
}

// MARK: - Сайдбар (непрозрачная тёмная подложка)

/// Подложка сайдбара: Liquid Glass (behindWindow blur + тёмный тинт).
/// Показывает размытый рабочий стол — для этого окно должно быть isOpaque = false.
@MainActor
final class SidebarPanelView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let divider = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.masksToBounds = true
        addSubview(blur)

        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.04, alpha: 0.40).cgColor
        addSubview(tint)

        divider.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.addSublayer(divider)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        divider.frame = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
    }
}

// MARK: - Карточка (стеклянная панель для окон)

/// Спокойная матовая карточка для контента: ровная полупрозрачная подложка,
/// тонкая хайрлайн-кромка сверху и мягкая тень. Без радиальных бликов, чтобы
/// поверхность читалась чисто, а не «грязно».
@MainActor
final class CardView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DS.Radius.control + 3) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = DS.Color.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.surfaceBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = NSSize(width: 0, height: 4)
    }
    required init?(coder: NSCoder) { nil }
}

/// Стеклянная карточка на настоящем материале размытия (Liquid Glass), удобная для AutoLayout:
/// blur + тинт пинятся к краям, контент добавляется обычным `addSubview` (ляжет поверх),
/// кромка рисуется бордером слоя. В отличие от `GlassContainerView` (frame-based contentView)
/// дружит с констрейнтами — для контентных секций (дашборд, строки настроек). C-редизайн.
@MainActor
final class GlassCardView: NSView {
    init(cornerRadius: CGFloat = DS.Radius.control + 3, style: DS.GlassStyle = .panel) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        // Чистая ровная тёмная поверхность + тонкая обводка. Без градиента-перелива
        // (Тико: на главной он смотрелся не очень) и без блюра («грязный серый»).
        layer?.backgroundColor = DS.Color.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = DS.Color.surfaceBorder.cgColor
    }
    required init?(coder: NSCoder) { nil }
}

// MARK: - Кнопка

@MainActor
final class StyledButton: NSButton {
    enum Style { case primary, accent, secondary, ghost }

    private let style: Style
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    init(title: String, style: Style, action: Selector?, target: AnyObject?) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = DS.Radius.control
        layer?.cornerCurve = .continuous
        contentTintColor = foreground
        font = DS.Font.text(13, weight: (style == .primary || style == .accent) ? .semibold : .medium)
        applyBackground()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = 34
        size.width += 24
        return size
    }

    private var foreground: NSColor {
        switch style {
        case .primary: return DS.Color.textPrimary
        case .accent: return .white
        case .secondary: return DS.Color.textPrimary
        case .ghost: return DS.Color.textSecondary
        }
    }

    private func applyBackground() {
        let color: NSColor
        switch style {
        case .primary:
            color = hovering ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.12)
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(hovering ? 0.13 : 0.08).cgColor
            layer?.backgroundColor = color.cgColor
            return
        case .accent:
            color = hovering
                ? (DS.Color.accent.blended(withFraction: 0.14, of: .white) ?? DS.Color.accent)
                : DS.Color.accent
            layer?.borderWidth = 0
            layer?.backgroundColor = color.cgColor
            return
        case .secondary:
            color = hovering ? DS.Color.controlBackgroundHover : DS.Color.controlBackground
        case .ghost:
            color = hovering ? DS.Color.controlBackground : .clear
        }
        layer?.backgroundColor = color.cgColor
        if style == .ghost {
            layer?.borderWidth = 1
            layer?.borderColor = DS.Color.glassStrokeSoft.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; applyBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; applyBackground() }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.4
            window?.invalidateCursorRects(for: self)
        }
    }
}

/// Стеклянный контейнер: `NSVisualEffectView` (размытие) + тинт-слой + кромка.
/// Внешний вид задаётся `DS.GlassStyle`. Контент добавляется в `contentView`.
@MainActor
final class GlassContainerView: NSView {
    let contentView = NSView()
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let edgeLight = CAGradientLayer()
    private let specular = CAGradientLayer()
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat, style: DS.GlassStyle = .panel) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        // 1. Размытие фона (стекло).
        blur.material = style.material
        blur.blendingMode = style.blending
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.appearance = NSAppearance(named: .vibrantDark)
        addSubview(blur)

        // 2. Тинт поверх размытия — глубина + читаемость.
        tint.wantsLayer = true
        tint.layer?.backgroundColor = style.tint.cgColor
        tint.layer?.cornerRadius = cornerRadius
        tint.layer?.masksToBounds = true
        addSubview(tint)

        // 3. Контент. Закрепляем по краям контейнера Auto Layout-констрейнтами, а не
        // ручным frame в layout(): ручной frame вызывающие легко ломали
        // (`contentView.translatesAutoresizingMaskIntoConstraints = false` без
        // констрейнтов → движок обнулял frame в super.layout() → попапы рендерились
        // пустыми). Констрейнты гарантируют корректный размер независимо от вызывающих.
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 4. Кромка + тень.
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = style.borderWidth
        layer?.borderColor = style.borderColor.cgColor
        if style.shadowOpacity > 0 {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = style.shadowOpacity
            layer?.shadowRadius = style.shadowRadius
            layer?.shadowOffset = NSSize(width: 0, height: 6)
        }

        if style.edgeOpacity > 0 {
            edgeLight.colors = [
                DS.Color.glassEdgeBright.cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor,
                NSColor.white.withAlphaComponent(0.16).cgColor
            ]
            edgeLight.locations = [0, 0.5, 1]
            edgeLight.startPoint = CGPoint(x: 0, y: 1)
            edgeLight.endPoint = CGPoint(x: 1, y: 0)
            edgeLight.cornerRadius = cornerRadius
            edgeLight.cornerCurve = .continuous
            edgeLight.opacity = style.edgeOpacity
            edgeLight.compositingFilter = "screenBlendMode"
            layer?.addSublayer(edgeLight)
        }

        if style.specularOpacity > 0 {
            specular.type = .radial
            specular.colors = [
                DS.Color.glassSpecular.cgColor,
                NSColor.white.withAlphaComponent(0).cgColor
            ]
            specular.startPoint = CGPoint(x: 0.24, y: 0.0)
            specular.endPoint = CGPoint(x: 0.76, y: 0.85)
            specular.opacity = style.specularOpacity
            specular.compositingFilter = "screenBlendMode"
            layer?.addSublayer(specular)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        // contentView закреплён констрейнтами к краям (см. init) — super.layout()
        // решит его размер и размеры вложенных autolayout-подвью за один проход.
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        layer?.cornerRadius = cornerRadius
        edgeLight.frame = bounds
        specular.frame = bounds
        edgeLight.cornerRadius = cornerRadius
    }
}
