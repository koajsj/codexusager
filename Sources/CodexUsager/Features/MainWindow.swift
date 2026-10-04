import AppKit
import SwiftUI
import UsageCore

private enum MainPage: String, CaseIterable, Identifiable {
    case overview, usage, sessions, projects, models, sources
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: String(localized: "概览")
        case .usage: String(localized: "用量")
        case .sessions: String(localized: "会话")
        case .projects: String(localized: "项目")
        case .models: String(localized: "模型")
        case .sources: String(localized: "数据来源")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .usage: "chart.bar.xaxis"
        case .sessions: "clock.arrow.circlepath"
        case .projects: "folder"
        case .models: "cpu"
        case .sources: "externaldrive"
        }
    }
}

struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selection: MainPage? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = false
    @State private var autoCollapsedSidebar = false
    @State private var sessionSelection: String?
    @State private var detailSession: SessionSummary?
    @State private var manualEntry: ManualUsage?
    @State private var newManualSheet = false
    @State private var projectEntry: ProjectSummary?
    @State private var priceEntry: ModelSummary?
    @State private var exportSheet = false
    @State private var recordsSheet = false

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(MainPage.allCases, selection: $selection) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
                .navigationTitle("CodexUsager")
                .navigationSplitViewColumnWidth(min: 150, ideal: 172, max: 210)
            } detail: {
                VStack(spacing: 0) {
                    content(width: max(320, geometry.size.width - (columnVisibility == .detailOnly ? 0 : 172) - (inspectorPresented ? 285 : 0) - 32),
                            windowWidth: geometry.size.width)
                    if let error = model.storageError ?? model.operationError {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(error).lineLimit(2)
                                if let recovery = model.storageError != nil
                                    ? model.errorCenter.issue(for: .storage)?.recoverySuggestion
                                    : (model.errorCenter.issue(for: .operation) ??
                                       model.errorCenter.issue(for: .session) ??
                                       model.errorCenter.issue(for: .export))?.recoverySuggestion {
                                    Text(recovery).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                            if model.storageError == nil { Button("关闭") { model.dismissOperationError() } }
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .navigationTitle(selection?.title ?? String(localized: "概览"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        StatusBadge(health: model.overallHealth)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.refreshData() } label: {
                            if model.isRefreshing || model.isImporting {
                                ProgressView().controlSize(.small)
                            } else { Image(systemName: "arrow.clockwise") }
                        }
                        .help("刷新数据")
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(model.isRefreshing || model.isImporting)
                    }
                    if geometry.size.width >= 950 {
                        ToolbarItem(placement: .primaryAction) {
                            Button { inspectorPresented.toggle() } label: {
                                Image(systemName: "sidebar.right")
                            }
                            .help("显示详情")
                        }
                    }
                }
                .inspector(isPresented: $inspectorPresented) {
                    Group {
                        if selection == .sessions, let session = selectedSession {
                            SessionDetail(model: model, session: session)
                        } else { InspectorContent(model: model) }
                    }
                        .inspectorColumnWidth(min: 210, ideal: 235, max: 285)
                }
            }
            .onChange(of: geometry.size.width) { _, width in
                if width < 950 { inspectorPresented = false }
                if width < 675, columnVisibility != .detailOnly {
                    columnVisibility = .detailOnly
                    autoCollapsedSidebar = true
                } else if width >= 675, autoCollapsedSidebar {
                    columnVisibility = .all
                    autoCollapsedSidebar = false
                }
            }
            .onAppear {
                if geometry.size.width < 675 {
                    columnVisibility = .detailOnly
                    autoCollapsedSidebar = true
                }
            }
        }
        .frame(minWidth: 540, minHeight: 390)
        .background(WindowObserver())
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            model.start()
        }
        .sheet(isPresented: Binding(get: { model.hasCheckedCodexAccount && !model.welcomeCompleted }, set: { _ in })) {
            WelcomeView(model: model)
        }
        .onChange(of: sessionSelection) { _, id in
            model.loadSession(model.analytics.sessions.first(where: { $0.id == id }))
        }
        .sheet(item: $detailSession) { session in
            SessionDetail(model: model, session: session)
                .frame(minWidth: 390, minHeight: 430)
        }
        .sheet(item: $manualEntry) { ManualUsageSheet(model: model, existing: $0) }
        .sheet(isPresented: $newManualSheet) { ManualUsageSheet(model: model) }
        .sheet(item: $projectEntry) { ProjectRuleSheet(model: model, project: $0) }
        .sheet(item: $priceEntry) { PriceSheet(model: model, item: $0) }
        .sheet(isPresented: $exportSheet) { ExportSheet(model: model) }
        .sheet(isPresented: $recordsSheet) { RecordsSheet(model: model) }
    }

    @ViewBuilder private func content(width: CGFloat, windowWidth: CGFloat) -> some View {
        switch selection ?? .overview {
        case .overview:
            OverviewPage(model: model, width: width, compact: windowWidth < 675,
                         showSources: { selection = .sources }, showProjects: { selection = .projects })
        case .usage:
            UsagePage(model: model, width: width, openRecords: { recordsSheet = true })
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { newManualSheet = true }
                        label: { Label("手动补录", systemImage: "plus") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { exportSheet = true } label: { Label("导出", systemImage: "square.and.arrow.up") }
                    }
                }
        case .sessions:
            SessionsPage(model: model, width: width, selection: $sessionSelection, showDetail: { id in
                guard let session = model.analytics.sessions.first(where: { $0.id == id }) else { return }
                sessionSelection = id
                model.loadSession(session)
                if windowWidth >= 950 { inspectorPresented = true } else { detailSession = session }
            })
        case .projects:
            ProjectsPage(model: model, width: width, edit: { projectEntry = $0 })
        case .models:
            ModelsPage(model: model, width: width, editPrice: { priceEntry = $0 })
        case .sources: SourcesPage(model: model)
        }
    }
    private var selectedSession: SessionSummary? {
        model.analytics.sessions.first { $0.id == sessionSelection }
    }
}

private struct WindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTrackingView { WindowTrackingView() }
    func updateNSView(_ nsView: WindowTrackingView, context: Context) {}
}

private final class WindowTrackingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.contentMinSize = NSSize(width: 540, height: 390)
        let saved = UserDefaults.standard.object(forKey: "NSWindow Frame CodexUsagerMainWindow") != nil
        window.setFrameAutosaveName("CodexUsagerMainWindow")
        if !saved, let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let size = WindowSizing.initial(visible: .init(width: visible.width, height: visible.height))
            window.setContentSize(NSSize(width: size.width, height: size.height))
            window.center()
        }
    }
}

private struct InspectorContent: View {
    let model: AppModel
    var body: some View {
        Form {
            Section("同步") {
                LabeledContent("Codex", value: model.codexStatus.health.localizedLabel)
                LabeledContent("Claude", value: model.claudeStatus.health.localizedLabel)
                if let last = model.lastRefresh {
                    LabeledContent("最近刷新", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("本地数据") {
                LabeledContent("记录", value: model.analytics.recordCount.formatted())
                LabeledContent("来源文件", value: model.analytics.health.count.formatted())
                if model.isImporting { ProgressView("正在导入") }
            }
        }
        .formStyle(.grouped)
    }
}
