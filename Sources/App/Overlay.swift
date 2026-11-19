import AppKit

/// 盖在别的应用窗口上的透明面板：不抢焦点、不接鼠标。
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// 无障碍接口的坐标原点在主屏左上角，窗口坐标原点在左下角。
    func place(at rect: CGRect) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        setFrame(NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height), display: true)
    }
}

/// 在透明面板里画若干圆角文字标签。
final class LabelsView: NSView {
    struct Label: Equatable {
        let rect: CGRect
        let text: String
        var isError = false
    }

    static let font = NSFont.systemFont(ofSize: 13)
    static let padding = CGSize(width: 8, height: 4)

    var labels: [Label] = [] {
        didSet { if labels != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    /// 文字在给定的最大宽高内占的大小（含内边距）。放不下时高度封顶，画的时候末行以省略号收尾。
    static func size(of text: String, within limit: CGSize) -> CGSize {
        let bounds = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: CGSize(width: limit.width - padding.width * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(bounds.width) + padding.width * 2, height: min(ceil(bounds.height) + padding.height * 2, limit.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        for label in labels {
            let shape = NSBezierPath(roundedRect: label.rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            shape.fill()
            (label.isError ? NSColor.systemRed : NSColor.separatorColor).setStroke()
            shape.stroke()
            NSAttributedString(string: label.text, attributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])
                .draw(with: label.rect.insetBy(dx: Self.padding.width, dy: Self.padding.height),
                      options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
    }
}

/// 输入框上方的一行提示：翻译中、失败原因。
final class Toast {
    private let panel = OverlayPanel()
    private let view = LabelsView()
    private var hideWork: DispatchWorkItem?

    init() {
        panel.contentView = view
    }

    /// `duration` 为 nil 时一直显示到下一次 show/hide。
    func show(_ message: String, above anchor: CGRect?, isError: Bool = false, duration: TimeInterval?) {
        hideWork?.cancel()
        guard let anchor else { return hide() }
        let size = LabelsView.size(of: message, within: CGSize(width: max(anchor.width, 240), height: 200))
        panel.place(at: CGRect(x: anchor.minX, y: anchor.minY - size.height - 12, width: size.width, height: size.height))
        view.labels = [LabelsView.Label(rect: CGRect(origin: .zero, size: size), text: message, isError: isError)]
        panel.orderFrontRegardless()
        if let duration {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}
