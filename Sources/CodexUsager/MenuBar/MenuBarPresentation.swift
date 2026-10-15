import Foundation
import UsageCore

/// Value-only presentation; rendering never accesses a provider or the filesystem.
struct MenuBarPresentation {
    struct Row: Equatable { let title: String; let value: String }
    let rows: [Row]
    let accessibilityLabel: String
    let selectionUnavailable: Bool

    @MainActor init(model: AppModel, now: Date = .now) {
        let requested = model.menuQuotaSelections
        let resolved = requested.compactMap { selection -> (ProviderID, QuotaWindow)? in
            model.quota(selection.provider).snapshot?.windows.first { $0.id == selection.windowID }
                .map { (selection.provider, $0) }
        }
        selectionUnavailable = resolved.count != requested.count
        let windows = resolved.isEmpty ? model.menuWindows.map { (model.selectedProvider, $0) } : resolved
        let details = windows.prefix(2).map { provider, window in
            let stale = model.quota(provider).isStale || window.isAwaitingRefresh(at: now)
            let prefix = requested.isEmpty ? "" : "\(provider == .codex ? "C" : "Cl") · "
            let number = model.menuNumber(window)
            let value = number >= 10_000
                ? number.formatted(.number.notation(.scientific).precision(.significantDigits(3)))
                : number.formatted(.number.precision(.fractionLength(0)))
            return Row(title: prefix + window.localizedName, value: stale ? "过期" : "\(value)%")
        }
        if model.menuStyle == .icon { rows = [] }
        else if let first = details.first {
            switch model.menuStyle {
            case .minimal: rows = [Row(title: "", value: first.value)]
            case .quotaCountdown:
                let reset = windows.first?.1.resetsAt
                let remaining = reset.map { max(0, min(31_536_000, $0.timeIntervalSince(now))) }
                let text = remaining.map { seconds in
                    seconds == 0 ? "等待更新" : "\(Int(ceil(seconds / 60)) / 60)时\(Int(ceil(seconds / 60)) % 60)分"
                } ?? "未提供"
                rows = [first, Row(title: "重置", value: text)]
            default: rows = Array(details)
            }
        } else { rows = [Row(title: model.selectedStatus.displayName, value: model.selectedStatus.health.localizedLabel)] }
        accessibilityLabel = windows.isEmpty
            ? "\(model.selectedStatus.displayName)，\(model.selectedStatus.health.localizedLabel)"
            : windows.prefix(2).map { provider, window in
                "\(provider.title)，\(window.localizedName)，\(model.menuValue == .remaining ? "剩余" : "已用") \(model.menuNumber(window).formatted(.number.precision(.fractionLength(0))))%" +
                (model.quota(provider).isStale || window.isAwaitingRefresh(at: now) ? "，上次已知值，已过期" : "")
            }.joined(separator: "；")
    }
}
