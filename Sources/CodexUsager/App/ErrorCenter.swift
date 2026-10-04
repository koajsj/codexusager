import Observation
import UsageCore

enum ErrorScope: Hashable {
    case provider(ProviderID), scan(ProviderID), storage, analytics, session, export, widget, operation
}

@MainActor @Observable final class ErrorCenter {
    private(set) var issues: [ErrorScope: AppError] = [:]

    func report(_ issue: AppError, for scope: ErrorScope) { issues[scope] = issue }
    func clear(_ scope: ErrorScope) { issues.removeValue(forKey: scope) }
    func issue(for scope: ErrorScope) -> AppError? { issues[scope] }
}
