import Foundation

struct AnalyticsEngine {
    let query: UsageQuery
    let now: Date
    let calendar: Calendar
    let rules: [String: ProjectRule]
    let adjustments: [String: UsageAdjustment]
    let prices: [String: ModelPrice]
    var result = AnalyticsSnapshot()
    private var sessions: [String: SessionSummary] = [:]
    private var projectRows: [String: ProjectSummary] = [:]
    private var projectSessions: [String: Set<String>] = [:]
    private var projectDays: [String: [Date: Int64]] = [:]
    private var modelRows: [String: ModelSummary] = [:]
    private var modelSessions: [String: Set<String>] = [:]
    private var modelProjects: [String: Set<String>] = [:]
    private var modelDays: [String: [Date: Int64]] = [:]
    private var modelCosts: [String: Double] = [:]
    private var unpricedModels: Set<String> = []
    private var days: [Date: Int64] = [:]
    private var hours: [Date: Int64] = [:]
    private var providerTokens: [ProviderID: Int64] = [:]
    private var providerSessions: [ProviderID: Set<String>] = [:]
    private var availableModels: Set<String> = []
    private var todayProjects: [String: (name: String, tokens: Int64)] = [:]
    private var todayModels: [String: (provider: ProviderID, name: String, tokens: Int64)] = [:]

    init(query: UsageQuery, now: Date, rules: [ProjectRule], adjustments: [UsageAdjustment], prices: [ModelPrice],
         timeContext: AnalyticsTimeContext = AnalyticsTimeContext()) {
        self.query = query; self.now = now; calendar = timeContext.calendar
        self.rules = rules.reduce(into: [:]) { $0[$1.path] = $1 }
        self.adjustments = adjustments.reduce(into: [:]) { $0[$1.recordID] = $1 }
        self.prices = prices.reduce(into: [:]) { $0[$1.id] = $1 }
    }
    func project(_ path: String?) -> (key: String, name: String, ignored: Bool) {
        var key = path ?? "unknown"
        var visited: Set<String> = []
        var ignored = false
        while visited.insert(key).inserted, let rule = rules[key] {
            ignored = ignored || rule.ignored
            guard let next = rule.mergedInto, !next.isEmpty else { break }
            key = next
        }
        let name = rules[key]?.displayName.flatMap { $0.isEmpty ? nil : $0 }
            ?? (key == "unknown" ? "未知项目" : URL(fileURLWithPath: key).lastPathComponent)
        return (key, name, ignored)
    }
    func entry(_ record: UsageRecord) -> UsageEntry {
        let p = project(record.projectID)
        let adjustment = matchingAdjustment(record)
        return UsageEntry(id: record.id, provider: record.provider, timestamp: record.timestamp,
            sessionID: record.sessionID, project: p.key, projectName: p.name, model: record.model,
            original: record.tokens, final: record.tokens.applying(adjustment?.replacement ?? TokenValues(), provider: record.provider),
            adjustment: adjustment, isManual: false, note: adjustment?.note ?? "")
    }
    private func matchingAdjustment(_ record: UsageRecord) -> UsageAdjustment? {
        guard let value = adjustments[record.id], value.original == record.tokens,
              value.provider == nil || value.provider == record.provider else { return nil }
        let final = record.tokens.applying(value.replacement, provider: record.provider)
        guard final.total != nil else { return nil }
        do { try final.validate(provider: record.provider); return value }
        catch { return nil }
    }
    func entry(_ record: ManualUsage) -> UsageEntry {
        let p = project(record.project)
        return UsageEntry(id: "manual:" + record.id, provider: record.provider, timestamp: record.timestamp,
            sessionID: record.sessionID, project: p.key, projectName: p.name, model: record.model,
            original: record.tokens, final: record.tokens, adjustment: nil, isManual: true, note: record.note)
    }
    func includes(_ entry: UsageEntry) -> Bool {
        guard entry.timestamp <= now,
              query.provider == nil || query.provider == entry.provider,
              query.project == nil || query.project == entry.project,
              query.model == nil || query.model == entry.model else { return false }
        let start = query.from ?? query.period.start(now: now, calendar: calendar)
        if let start, entry.timestamp < start { return false }
        if let end = query.through, entry.timestamp >= (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end) { return false }
        let text = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || [entry.sessionID, entry.projectName, entry.model ?? "", entry.provider.rawValue].contains { $0.localizedCaseInsensitiveContains(text) }
    }
    mutating func consume(_ entry: UsageEntry, originalPath: String?) {
        let p = project(originalPath)
        result.availableProjects[p.key] = p.name
        if let model = entry.model { availableModels.insert(model) }
        let total = entry.final.total ?? 0
        let day = calendar.startOfDay(for: entry.timestamp)
        let sessionKey = "\(entry.provider.rawValue):\(entry.sessionID)"
        if !p.ignored, entry.timestamp <= now {
            result.home.lastActivity = max(result.home.lastActivity ?? entry.timestamp, entry.timestamp)
            if day == calendar.startOfDay(for: now) {
                result.today.accumulate(entry.final)
                result.todayByProvider[entry.provider] = SafeCount.add(result.todayByProvider[entry.provider] ?? 0, total)
                if let knownTotal = entry.final.total, knownTotal > 0 {
                    if p.key != "unknown" {
                        todayProjects[p.key] = (p.name, SafeCount.add(todayProjects[p.key]?.tokens ?? 0, knownTotal))
                    }
                    if let name = entry.model, !name.isEmpty, name != "unknown" {
                        let key = "\(entry.provider.rawValue):\(name)"
                        todayModels[key] = (entry.provider, name, SafeCount.add(todayModels[key]?.tokens ?? 0, knownTotal))
                    }
                }
            }
            if entry.timestamp >= now.addingTimeInterval(-24 * 3600), let hour = calendar.dateInterval(of: .hour, for: entry.timestamp)?.start {
                hours[hour] = SafeCount.add(hours[hour] ?? 0, total)
            }
        }
        guard includes(entry), !p.ignored else { return }
        var project = projectRows[p.key] ?? ProjectSummary(id: p.key, name: p.name, paths: [], providers: [], tokens: TokenValues(), sessionCount: 0, lastSeen: entry.timestamp, trend: [], ignored: p.ignored)
        if let originalPath, !project.paths.contains(originalPath) { project.paths.append(originalPath) }
        if !project.providers.contains(entry.provider) { project.providers.append(entry.provider) }
        project.tokens.accumulate(entry.final); project.lastSeen = max(project.lastSeen, entry.timestamp)
        projectRows[p.key] = project
        projectSessions[p.key, default: []].insert(sessionKey)
        var projectDay = projectDays[p.key] ?? [:]
        projectDay[day] = SafeCount.add(projectDay[day] ?? 0, total)
        projectDays[p.key] = projectDay
        result.tokens.accumulate(entry.final); result.recordCount = SafeCount.add(result.recordCount, 1)
        let values = entry.final
        if let input = values.input {
            let exclusive = entry.provider.inputIncludesCache
                ? input - min(input, SafeCount.add(values.cacheRead ?? 0, values.cacheWrite ?? 0)) : input
            result.composition[.input] = SafeCount.add(result.composition[.input] ?? 0, exclusive)
        }
        if let cached = values.cacheRead {
            result.composition[.cacheRead] = SafeCount.add(result.composition[.cacheRead] ?? 0, cached)
        }
        if let write = values.cacheWrite {
            result.composition[.cacheWrite] = SafeCount.add(result.composition[.cacheWrite] ?? 0, write)
        }
        if let output = values.output {
            result.composition[.output] = SafeCount.add(result.composition[.output] ?? 0, output)
        }
        if entry.isManual { result.manualCount = SafeCount.add(result.manualCount, 1) }
        if entry.adjustment != nil { result.adjustedCount = SafeCount.add(result.adjustedCount, 1) }
        days[day] = SafeCount.add(days[day] ?? 0, total)
        providerTokens[entry.provider] = SafeCount.add(providerTokens[entry.provider] ?? 0, total)
        providerSessions[entry.provider, default: []].insert(sessionKey)
        var session = sessions[sessionKey] ?? SessionSummary(id: sessionKey, provider: entry.provider, sessionID: entry.sessionID,
            project: p.key, model: entry.model, lastSeen: entry.timestamp, totalTokens: 0, recordCount: 0)
        session.tokens.accumulate(entry.final); session.totalTokens = session.tokens.total ?? 0
        session.recordCount = SafeCount.add(session.recordCount, 1)
        session.isManual = session.isManual || entry.isManual
        if entry.timestamp >= session.lastSeen { session.lastSeen = entry.timestamp; session.model = entry.model; session.project = p.key; session.projectName = p.name }
        sessions[sessionKey] = session
        let modelName = entry.model ?? "unknown", modelKey = "\(entry.provider.rawValue):\(modelName)"
        var model = modelRows[modelKey] ?? ModelSummary(name: modelName, provider: entry.provider, tokens: TokenValues(), sessionCount: 0, projectCount: 0, trend: [], estimatedCost: nil)
        model.tokens.accumulate(entry.final); modelRows[modelKey] = model
        if let price = prices[modelKey], let cost = price.estimate(entry.final) {
            let next = (modelCosts[modelKey] ?? 0) + cost
            if next.isFinite { modelCosts[modelKey] = next }
            else { unpricedModels.insert(modelKey) }
        } else { unpricedModels.insert(modelKey) }
        modelSessions[modelKey, default: []].insert(sessionKey); modelProjects[modelKey, default: []].insert(p.key)
        var modelDay = modelDays[modelKey] ?? [:]
        modelDay[day] = SafeCount.add(modelDay[day] ?? 0, total)
        modelDays[modelKey] = modelDay
    }
    mutating func finish() -> AnalyticsSnapshot {
        result.home.mainProject = todayProjects.sorted {
            $0.value.tokens == $1.value.tokens ? $0.key < $1.key : $0.value.tokens > $1.value.tokens
        }.first?.value.name
        if let model = todayModels.sorted(by: {
            $0.value.tokens == $1.value.tokens ? $0.key < $1.key : $0.value.tokens > $1.value.tokens
        }).first?.value {
            result.home.mainModel = model.name; result.home.modelProvider = model.provider
        }
        result.sessions = sessions.values.sorted { $0.lastSeen > $1.lastSeen }
        result.projects = projectRows.values.map { row in
            var row = row; row.sessionCount = projectSessions[row.id]?.count ?? 0
            row.trend = points(projectDays[row.id] ?? [:]); return row
        }.sorted { ($0.tokens.total ?? 0) > ($1.tokens.total ?? 0) }
        result.models = modelRows.values.map { row in
            var row = row; row.sessionCount = modelSessions[row.id]?.count ?? 0; row.projectCount = modelProjects[row.id]?.count ?? 0
            row.trend = points(modelDays[row.id] ?? [:])
            row.estimatedCost = unpricedModels.contains(row.id) ? nil : modelCosts[row.id]
            return row
        }.sorted { ($0.tokens.total ?? 0) > ($1.tokens.total ?? 0) }
        if query.from == nil, query.through == nil, let start = query.period.start(now: now, calendar: calendar) {
            var date = start
            let end = calendar.startOfDay(for: now)
            var filled: [TrendPoint] = []
            while date <= end {
                filled.append(TrendPoint(date: date, tokens: days[date] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
                date = next
            }
            result.trend = filled
        } else { result.trend = points(days) }
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        result.past24Hours = (-23...0).compactMap { calendar.date(byAdding: .hour, value: $0, to: hourStart) }.map { TrendPoint(date: $0, tokens: hours[$0] ?? 0) }
        result.providers = ProviderID.allCases.compactMap { provider in
            guard let sessions = providerSessions[provider] else { return nil }
            return ProviderTotal(id: provider, tokens: providerTokens[provider] ?? 0, sessions: sessions.count)
        }
        result.availableModels = availableModels.sorted()
        result.generatedAt = now
        return result
    }
    private func points(_ values: [Date: Int64]) -> [TrendPoint] {
        values.keys.sorted().map { TrendPoint(date: $0, tokens: values[$0] ?? 0) }
    }
}
