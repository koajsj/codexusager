import AppKit
import SwiftUI
import UsageCore

@MainActor final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private unowned let model: AppModel
    private let label = StatusLabelView(frame: .zero)
    private var accessibilityLabel: String?

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuPopover(model: model, dismiss: { [weak self] in self?.popover.performClose(nil) }))
        if let button = item.button {
            button.target = self; button.action = #selector(togglePopover)
            label.frame = button.bounds
            label.autoresizingMask = [.width, .height]
            button.addSubview(label)
        }
        update()
    }
    func update() {
        let presentation = MenuBarPresentation(model: model)
        if label.rows != presentation.rows { label.rows = presentation.rows }
        if let button = item.button, label.frame != button.bounds { label.frame = button.bounds }
        let width = label.preferredWidth
        if item.length != width { item.length = width }
        if accessibilityLabel != presentation.accessibilityLabel {
            accessibilityLabel = presentation.accessibilityLabel
            item.button?.setAccessibilityLabel(presentation.accessibilityLabel)
            item.button?.toolTip = presentation.accessibilityLabel
        }
        label.refreshAppearance()
    }
    func close() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(item)
    }
    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            let height = min(560, max(200, (button.window?.screen?.visibleFrame.height ?? 600) - 40))
            popover.contentSize = NSSize(width: 360, height: height)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.highlight(true); label.refreshAppearance()
            model.refreshMenuIfNeeded()
        }
    }
    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false); label.refreshAppearance()
    }
}

/// Measurement and drawing share fonts. The button retains all native mouse handling.
@MainActor private final class StatusLabelView: NSView {
    var rows: [MenuBarPresentation.Row] = [] {
        didSet {
            guard rows != oldValue else { return }
            measuredWidth = nil
            needsDisplay = true
        }
    }
    private var measuredWidth: (height: CGFloat, width: CGFloat)?
    private var lastHighlighted: Bool?
    private let iconView = NSImageView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.image = StatusIcon.image
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
    }
    required init?(coder: NSCoder) { return nil }
    override func layout() {
        super.layout()
        let frame = NSRect(x: 4, y: (bounds.height - 14) / 2, width: 14, height: 14)
        if iconView.frame != frame { iconView.frame = frame }
    }
    private var textColor: NSColor {
        (superview as? NSButton)?.isHighlighted == true ? .selectedMenuItemTextColor : .labelColor
    }
    func refreshAppearance(force: Bool = false) {
        let highlighted = (superview as? NSButton)?.isHighlighted == true
        guard force || lastHighlighted != highlighted else { return }
        lastHighlighted = highlighted
        iconView.contentTintColor = textColor
        needsDisplay = true
    }
    private var fontSize: CGFloat {
        rows.count > 1 ? min(10, max(8, floor(bounds.height / 2) - 2)) : 11
    }
    private var titleFont: NSFont { .systemFont(ofSize: fontSize, weight: .medium) }
    private var numberFont: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance(force: true)
    }
    private func width(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    var preferredWidth: CGFloat {
        if let measuredWidth, measuredWidth.height == bounds.height { return measuredWidth.width }
        guard !rows.isEmpty else { return NSStatusBar.system.thickness }
        let measured = rows.map { width($0.title, font: titleFont) + width($0.value, font: numberFont) + 6 }.max() ?? 0
        let result = min(140, max(72, measured + 30))
        measuredWidth = (bounds.height, result)
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = textColor
        guard !rows.isEmpty else { return }
        let lineHeight = min(ceil(titleFont.ascender - titleFont.descender), bounds.height / CGFloat(rows.count))
        let start = (bounds.height - lineHeight * CGFloat(rows.count)) / 2
        for (index, row) in rows.enumerated() {
            let y = start + CGFloat(rows.count - index - 1) * lineHeight
            let valueWidth = width(row.value, font: numberFont)
            let textWidth = max(0, bounds.width - 28)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            paragraph.alignment = .left
            (row.title as NSString).draw(in: NSRect(x: 23, y: y, width: max(0, textWidth - valueWidth - 4), height: lineHeight),
                withAttributes: [.font: titleFont, .foregroundColor: color, .paragraphStyle: paragraph])
            (row.value as NSString).draw(in: NSRect(x: bounds.width - 5 - valueWidth, y: y, width: valueWidth, height: lineHeight),
                withAttributes: [.font: numberFont, .foregroundColor: color])
        }
    }
}

@MainActor private enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let path = NSBezierPath()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: rect.width * 0.31, y: rect.height * 0.82))
            path.line(to: NSPoint(x: rect.width * 0.08, y: rect.height * 0.5))
            path.line(to: NSPoint(x: rect.width * 0.31, y: rect.height * 0.18))
            path.move(to: NSPoint(x: rect.width * 0.69, y: rect.height * 0.82))
            path.line(to: NSPoint(x: rect.width * 0.92, y: rect.height * 0.5))
            path.line(to: NSPoint(x: rect.width * 0.69, y: rect.height * 0.18))
            path.move(to: NSPoint(x: rect.width * 0.58, y: rect.height * 0.92))
            path.line(to: NSPoint(x: rect.width * 0.42, y: rect.height * 0.08))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct MenuPopover: View {
    let model: AppModel
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(nsImage: StatusIcon.image).accessibilityHidden(true)
                        Text("CodexUsager").font(.headline)
                        Spacer()
                        if model.isRefreshing || model.isImporting { ProgressView().controlSize(.small) }
                    }
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        let status = model.status(provider)
                        let quota = model.quota(provider)
                        Divider()
                        HStack {
                            Text(provider.title).font(.headline)
                            Spacer(minLength: 4)
                            Text(status.account?.localizedPlan ?? "未知套餐").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack {
                            StatusBadge(health: status.health)
                            if quota.isStale, quota.snapshot?.windows.isEmpty == false { Text("上次已知额度 · 已过期").font(.caption2).foregroundStyle(.orange) }
                        }
                        if let windows = quota.snapshot?.windows, !windows.isEmpty {
                            ForEach(windows) { window in QuotaRow(window: window, isStale: quota.isStale || window.isAwaitingRefresh(at: .now)) }
                        } else {
                            Text(status.quotaAvailability.localizedLabel).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let issue = status.issue {
                            Text(issue.userMessage).font(.caption).foregroundStyle(.orange)
                            Text(issue.recoverySuggestion).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let updated = quota.snapshot?.fetchedAt {
                            Text("额度更新：\(updated.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let error = model.sourceRefresh[provider]?.scanError {
                            Text("会话扫描：\(error)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Divider()
                    if model.isImporting {
                        Text("正在增量索引，先显示已有统计。").font(.caption2).foregroundStyle(.secondary)
                    }
                    LabeledContent("今日 Token") {
                        TokenNumber(value: model.hasIndexed ? model.analytics.today.total : nil, compact: true).monospacedDigit()
                    }
                    if let last = model.lastImport {
                        Text("最近索引：\(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else { Text("尚未完成本地索引").font(.caption2).foregroundStyle(.secondary) }
                    if let issue = model.storageError ?? model.operationError {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                    if MenuBarPresentation(model: model).selectionUnavailable {
                        Text("所选额度窗口暂不可用；未能匹配任何窗口时显示默认来源。可在设置中重新选择。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(14)
            }
            Divider()
            HStack(spacing: 12) {
                Button("打开主窗口") { dismiss(); model.openMainWindow() }
                Button("刷新") { model.refreshData() }.disabled(model.isRefreshing || model.isImporting)
                Spacer(minLength: 0)
                Button { dismiss(); model.openSettings() } label: { Image(systemName: "gearshape") }.help("设置").accessibilityLabel("设置")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("退出 CodexUsager").accessibilityLabel("退出 CodexUsager")
            }.buttonStyle(.borderless).font(.caption).padding(12)
        }
        .frame(width: 360)
    }
}

struct QuotaRow: View {
    let window: QuotaWindow
    let isStale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.localizedName).font(.subheadline).lineLimit(1)
                Spacer()
                Text(window.isOverLimit ? "\(window.usedPercent.formatted(.number.precision(.fractionLength(0))))% 已用" : "\(window.remainingPercent.formatted(.number.precision(.fractionLength(0))))%")
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            if window.isOverLimit {
                Text("已超出限额").font(.caption).foregroundStyle(.orange)
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(.blue)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: window.remainingPercent)
            HStack {
                Text("重置")
                Spacer()
                ResetCountdown(resetsAt: window.resetsAt, isStale: isStale)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ResetCountdown: View {
    let resetsAt: Date?
    let isStale: Bool
    var body: some View {
        if let resetsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = resetsAt.timeIntervalSince(context.date)
                let seconds = Int(max(0, min(31_536_000, ceil(remaining))))
                if remaining > 31_536_000 { Text(resetsAt, format: .dateTime.year().month().day()) }
                else if seconds == 0 { Text("正在更新").monospacedDigit() }
                else {
                    Text(String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60))
                        .monospacedDigit()
                }
            }
        } else { Text(isStale ? "上次已知值" : "未提供") }
    }
}
