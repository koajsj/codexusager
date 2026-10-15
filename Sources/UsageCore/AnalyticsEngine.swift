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
    private var modelMeanTokens: [String: Double] = [:]
    private var modelKnownCalls: [String: Int] = [:]
    private var modelDurations: [String: (total: Double, count: Int)] = [:]
    private var projectDurations: [String: Double] = [:]
    private var projectModelTokens: [String: [String: Int64]] = [:]
    private var projectCosts: [String: CostEstimate] = [:]
    private var hourDistribution: [Int: Int64] = [:]
    private var incompleteProjects: Set<String> = []
    private var incompleteModels: Set<String> = []
    private var incompleteSessions: Set<String> = []
    private var incompleteProviders: Set<ProviderID> = []
    private var incompleteTotal = false
    private var incompleteToday = false
    private var incompleteTodayProviders: Set<ProviderID> = []
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
            adjustment: adjustment, isManual: false, note: adjustment?.note ?? "",
            durationSeconds: record.durationSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            status: record.status, contextWindowTokens: record.contextWindowTokens)
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
        let priceKey = "\(entry.provider.rawValue):\(entry.model ?? "unknown")"
        let cost = prices[priceKey]?.estimate(entry.final)
        if !p.ignored, entry.timestamp <= now {
            Self.keep(entry, in: &result.homeRecentCalls, limit: 5) { Self.newer($0, $1) }
            if day == calendar.startOfDay(for: now) { result.todayCost.consume(cost) }
            if let start = calendar.dateInterval(of: .month, for: now)?.start, entry.timestamp >= start {
                result.monthCost.consume(cost)
            }
            result.home.lastActivity = max(result.home.lastActivity ?? entry.timestamp, entry.timestamp)
            if day == calendar.startOfDay(for: now) {
                result.today.accumulate(entry.final)
                incompleteToday = incompleteToday || entry.final.total == nil
                if entry.final.total == nil { incompleteTodayProviders.insert(entry.provider) }
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
        Self.keep(entry, in: &result.recentCalls, limit: 100) { Self.newer($0, $1) }
        if entry.final.total != nil {
            Self.keep(entry, in: &result.largestCalls, limit: 5) {
                $0.final.total == $1.final.total ? Self.newer($0, $1) : ($0.final.total ?? 0) > ($1.final.total ?? 0)
            }
        }
        if let duration = entry.durationSeconds, !entry.isManual {
            Self.keep(entry, in: &result.longestCalls, limit: 5) {
                $0.durationSeconds == $1.durationSeconds ? Self.newer($0, $1) : ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0)
            }
            let next = (projectDurations[p.key] ?? 0) + duration
            if next.isFinite { projectDurations[p.key] = next }
        }
        if let name = entry.model {
            projectModelTokens[p.key, default: [:]][name] = SafeCount.add(projectModelTokens[p.key]?[name] ?? 0, total)
        }
        projectCosts[p.key, default: CostEstimate()].consume(cost)
        hourDistribution[calendar.component(.hour, from: entry.timestamp)] = SafeCount.add(hourDistribution[calendar.component(.hour, from: entry.timestamp)] ?? 0, total)
        if entry.final.total == nil {
            result.unavailableTotalCount = SafeCount.add(result.unavailableTotalCount, 1)
            incompleteTotal = true; incompleteProjects.insert(p.key)
            incompleteModels.insert(priceKey); incompleteSessions.insert(sessionKey)
            incompleteProviders.insert(entry.provider)
        }
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
        model.tokens.accumulate(entry.final)
        if !entry.isManual {
            model.callCount = SafeCount.add(model.callCount, 1)
            if let value = entry.final.total {
                let count = SafeCount.add(modelKnownCalls[modelKey] ?? 0, 1)
                let mean = modelMeanTokens[modelKey] ?? 0
                modelMeanTokens[modelKey] = mean + (Double(value) - mean) / Double(count)
                modelKnownCalls[modelKey] = count
            }
            if let value = entry.durationSeconds {
                let old = modelDurations[modelKey] ?? (0, 0), next = old.total + value
                if next.isFinite { modelDurations[modelKey] = (next, SafeCount.add(old.count, 1)) }
            }
        }
        modelRows[modelKey] = model
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
        if incompleteTotal { result.tokens.total = nil }
        if incompleteToday { result.today.total = nil }
        for provider in incompleteTodayProviders { result.todayByProvider.removeValue(forKey: provider) }
        result.sessions = sessions.values.map { row in
            var row = row
            if incompleteSessions.contains(row.id) { row.tokens.total = nil }
            return row
        }.sorted { $0.lastSeen == $1.lastSeen ? $0.id < $1.id : $0.lastSeen > $1.lastSeen }
        result.projects = projectRows.values.map { row in
            var row = row; row.sessionCount = projectSessions[row.id]?.count ?? 0
            row.trend = points(projectDays[row.id] ?? [:])
            row.commonModels = Array((projectModelTokens[row.id] ?? [:]).sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.prefix(3).map(\.key))
            row.reportedDuration = projectDurations[row.id]
            if let estimate = projectCosts[row.id], estimate.isComplete { row.estimatedCost = estimate.amount }
            if incompleteProjects.contains(row.id) { row.tokens.total = nil }
            return row
        }.sorted { ($0.tokens.total ?? 0) > ($1.tokens.total ?? 0) }
        result.models = modelRows.values.map { row in
            var row = row; row.sessionCount = modelSessions[row.id]?.count ?? 0; row.projectCount = modelProjects[row.id]?.count ?? 0
            row.trend = points(modelDays[row.id] ?? [:])
            row.estimatedCost = unpricedModels.contains(row.id) ? nil : modelCosts[row.id]
            if incompleteModels.contains(row.id) { row.tokens.total = nil }
            if row.callCount > 0, modelKnownCalls[row.id] == row.callCount {
                row.averageTokens = modelMeanTokens[row.id]
            }
            if let duration = modelDurations[row.id], duration.count > 0 {
                row.averageDuration = duration.total / Double(duration.count)
                row.durationSampleCount = duration.count
            }
            if let total = result.tokens.total, total > 0, total < Int64.max, let count = row.tokens.total {
                row.tokenShare = min(1, max(0, Double(count) / Double(total)))
            }
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
            return ProviderTotal(id: provider, tokens: incompleteProviders.contains(provider) ? nil : providerTokens[provider] ?? 0,
                                 sessions: sessions.count)
        }
        result.weeklyTrend = groupedTrend(days, component: .weekOfYear)
        result.monthlyTrend = groupedTrend(days, component: .month)
        result.hourlyDistribution = (0..<24).map { HourUsage(hour: $0, tokens: hourDistribution[$0] ?? 0) }
        result.availableModels = availableModels.sorted()
        result.generatedAt = now
        return result
    }
    private static func newer(_ a: UsageEntry, _ b: UsageEntry) -> Bool {
        a.timestamp == b.timestamp ? a.id < b.id : a.timestamp > b.timestamp
    }
    private static func keep(_ entry: UsageEntry, in values: inout [UsageEntry], limit: Int,
                      ordered: (UsageEntry, UsageEntry) -> Bool) {
        var low = 0, high = values.count
        while low < high {
            let middle = low + (high - low) / 2
            if ordered(entry, values[middle]) { high = middle } else { low = middle + 1 }
        }
        guard low < limit else { return }
        values.insert(entry, at: low)
        if values.count > limit { values.removeLast() }
    }
    private func groupedTrend(_ values: [Date: Int64], component: Calendar.Component) -> [TrendPoint] {
        var grouped: [Date: Int64] = [:]
        for (date, count) in values {
            if let start = calendar.dateInterval(of: component, for: date)?.start {
                grouped[start] = SafeCount.add(grouped[start] ?? 0, count)
            }
        }
        return points(grouped)
    }
    private func points(_ values: [Date: Int64]) -> [TrendPoint] {
        values.keys.sorted().map { TrendPoint(date: $0, tokens: values[$0] ?? 0) }
    }
}
