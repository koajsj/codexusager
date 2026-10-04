import Foundation
import UsageCore

extension QuotaWindow {
    var localizedName: String {
        switch durationMinutes {
        case 300: String(localized: "5 小时")
        case 10080: String(localized: "每周")
        case let value?: String(format: String(localized: "%d 分钟"), value)
        case nil: limitName ?? limitID
        }
    }
}

extension ConnectionHealth {
    var localizedLabel: String {
        switch self {
        case .notInstalled: String(localized: "未安装")
        case .signedOut: String(localized: "未连接")
        case .connected: String(localized: "已连接")
        case .syncing: String(localized: "同步中")
        case .offline: String(localized: "连接异常")
        case .unavailable: String(localized: "服务暂时不可用")
        case .stale: String(localized: "数据已过期")
        case .parseError: String(localized: "解析异常")
        case .reconnectRequired: String(localized: "需要重新连接")
        }
    }
}

extension QuotaAvailability {
    var localizedLabel: String {
        switch self {
        case .available: String(localized: "实时额度")
        case .unavailable: String(localized: "实时额度当前不可用")
        case .unsupportedVersion: String(localized: "当前版本暂不支持实时额度")
        case .signedOut: String(localized: "登录后可读取额度")
        case .offline: String(localized: "额度服务离线")
        }
    }
}

extension AccountProfile {
    var localizedPlan: String {
        normalizedPlan == "unknown" ? String(localized: "未知套餐") : displayName
    }
}

extension ProviderID {
    var title: String { self == .codex ? "Codex" : "Claude" }
}
extension TokenMetric {
    var title: String {
        switch self {
        case .total: String(localized: "总计")
        case .input: String(localized: "输入")
        case .cacheRead: String(localized: "缓存读取")
        case .cacheWrite: String(localized: "缓存写入")
        case .output: String(localized: "输出")
        case .reasoning: String(localized: "推理")
        }
    }
}
extension UsagePeriod {
    var title: String {
        switch self {
        case .today: String(localized: "今天")
        case .week: String(localized: "7 天")
        case .month: String(localized: "30 天")
        case .year: String(localized: "今年")
        case .all: String(localized: "全部")
        }
    }
}
extension ExportKind {
    var title: String {
        switch self {
        case .usage: "用量"; case .sessions: "会话"; case .projects: "项目"
        case .adjustments: "人工修正"; case .manual: "手动记录"
        }
    }
}
extension Error {
    var localizedDataMessage: String {
        guard let error = self as? DataValidationError else { return "数据保存失败，请检查磁盘空间和文件权限后重试。" }
        switch error {
        case .negativeTokens: return "Token 必须是非负整数。"
        case .cacheExceedsInput: return "Codex 缓存读取包含在输入中，不能大于输入。"
        case .reasoningExceedsOutput: return "推理 Token 包含在输出中，不能大于输出。"
        case .missingReason: return "请填写修正原因。"
        case .missingTotal: return "请填写总 Token 或可计算的输入与输出。"
        case .noChange: return "至少填写一项不同的修正值。"
        case .projectCycle: return "项目合并会形成循环，请选择其他目标。"
        case .missingRecord: return "原始记录已不在当前索引中，请刷新会话。"
        case .invalidPrice: return "单价必须是有限的非负数。"
        }
    }
}
