import AppKit
import SwiftUI
import UsageCore

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private unowned let model: AppModel
    private var label: ClickThroughHostingView<StatusLabel>?

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 310, height: 300)
        popover.contentViewController = NSHostingController(rootView: MenuPopover(model: model))
        if let button = item.button { button.target = self; button.action = #selector(togglePopover) }
        update()
    }
    func update() {
        guard let button = item.button else { return }
        item.length = preferredWidth
        let description = model.menuWindows.prefix(2).map { window in
            "\(window.localizedName) \(Int(model.menuNumber(window).rounded()))%"
        }.joined(separator: "，")
        button.setAccessibilityLabel(description.isEmpty
            ? "\(model.selectedStatus.displayName)，\(model.selectedStatus.health.localizedLabel)"
            : "\(model.selectedStatus.displayName)，\(description)\(model.selectedQuota.isStale ? "，数据已过期" : "")")
        let view = label ?? ClickThroughHostingView(rootView: StatusLabel(model: model))
        view.rootView = StatusLabel(model: model)
        view.frame = button.bounds
        view.autoresizingMask = [.width, .height]
        if label == nil { button.addSubview(view); label = view }
    }
    private var preferredWidth: CGFloat {
        let windows = Array(model.menuWindows.prefix(2))
        if model.menuStyle == .icon { return 25 }
        let font = NSFont.systemFont(ofSize: model.menuStyle == .minimal ? 11 : 10, weight: .medium)
        func measured(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let content: CGFloat
        if model.selectedQuota.isStale, !windows.isEmpty {
            content = measured("额度已过期")
        } else if windows.isEmpty {
            content = measured(model.selectedStatus.health.localizedLabel)
        } else if model.menuStyle == .minimal {
            content = measured("\(Int(model.menuNumber(windows[0]).rounded()))%")
        } else if model.menuStyle == .quotaCountdown {
            content = max(measured("\(windows[0].localizedName)  \(Int(model.menuNumber(windows[0]).rounded()))%"),
                          measured(windows[0].resetsAt == nil ? "重置时间未提供" : "00:00:00"))
        } else {
            content = windows.map { measured($0.localizedName) + measured("100%") + 8 }.max() ?? 0
        }
        return min(230, max(38, 15 + 5 + content + 12))
    }
    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct StatusLabel: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: StatusIcon.image)
                .resizable().interpolation(.high)
                .frame(width: 15, height: 14)
                .accessibilityHidden(true)
            if model.menuStyle == .icon {
                EmptyView()
            } else if model.selectedQuota.isStale && !model.menuWindows.isEmpty {
                Text("额度已过期").font(.system(size: 11, weight: .medium)).lineLimit(1)
            } else if model.menuWindows.isEmpty {
                Text(model.selectedStatus.health.localizedLabel)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            } else if model.menuStyle == .minimal {
                Text(number(model.menuWindows[0]))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            } else if model.menuStyle == .quotaCountdown {
                VStack(alignment: .leading, spacing: -1) {
                    Text("\(model.menuWindows[0].localizedName)  \(number(model.menuWindows[0]))")
                    if let due = model.menuWindows[0].resetsAt {
                        let now = Date()
                        if due > now {
                            Text(timerInterval: now...due, countsDown: true).monospacedDigit()
                        } else { Text("正在更新") }
                    } else { Text("重置时间未提供") }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: -1) {
                    ForEach(Array(model.menuWindows.prefix(2))) { window in
                        HStack(spacing: 3) {
                            Text(window.localizedName).lineLimit(1).truncationMode(.middle)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 2)
                            Text(model.menuNumber(window), format: .number.precision(.fractionLength(0)))
                                .monospacedDigit().fixedSize(horizontal: true, vertical: false)
                                .contentTransition(reduceMotion ? .identity : .numericText())
                            Text("%").padding(.leading, -3)
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 3)
        .accessibilityLabel(model.selectedStatus.displayName + " " + (model.menuWindows.isEmpty
            ? model.selectedStatus.health.localizedLabel
            : model.menuWindows.map { "\($0.localizedName) \(number($0))" }.joined(separator: ", ")) +
            (model.selectedQuota.isStale ? "，上次已知值" : ""))
    }
    private func number(_ window: QuotaWindow) -> String {
        "\(Int(model.menuNumber(window).rounded()))%"
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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CodeMark().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                Text(model.selectedStatus.displayName).font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
            }
            Text(model.selectedStatus.account?.localizedPlan ?? model.selectedStatus.health.localizedLabel)
                .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            if model.menuWindows.isEmpty {
                ContentUnavailableView(model.selectedStatus.quotaAvailability.localizedLabel, systemImage: "gauge", description: Text(model.selectedStatus.health.localizedLabel))
                    .frame(height: 100)
            } else {
                ForEach(model.menuWindows) { window in QuotaRow(window: window, isStale: model.selectedQuota.isStale) }
            }
            HStack {
                Text("今日 Token")
                Spacer()
                if let count = model.selectedTodayTokens {
                    Text(count, format: .number).monospacedDigit()
                } else { Text("—") }
            }.font(.subheadline)
            HStack(spacing: 6) {
                Circle().fill(model.selectedQuota.isStale ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(model.selectedQuota.isStale ? "数据可能已过期" : model.selectedStatus.health.localizedLabel)
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("打开主窗口") { model.openMainWindow() }
                Spacer()
                Button("刷新") { model.refreshAll(); model.importSources() }
            }
        }
        .padding(16)
        .frame(width: 310)
    }
}

private struct CodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.width, y = rect.height
        path.move(to: CGPoint(x: x * 0.30, y: y * 0.18))
        path.addLine(to: CGPoint(x: x * 0.08, y: y * 0.5))
        path.addLine(to: CGPoint(x: x * 0.30, y: y * 0.82))
        path.move(to: CGPoint(x: x * 0.70, y: y * 0.18))
        path.addLine(to: CGPoint(x: x * 0.92, y: y * 0.5))
        path.addLine(to: CGPoint(x: x * 0.70, y: y * 0.82))
        path.move(to: CGPoint(x: x * 0.58, y: y * 0.08))
        path.addLine(to: CGPoint(x: x * 0.42, y: y * 0.92))
        return path
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
                Text(window.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
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
