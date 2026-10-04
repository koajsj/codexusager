import Foundation
import Testing
@testable import UsageCore

@Test func authenticationReportsMissingCLIWithoutReadingCredentials() async {
    let service = AuthenticationService(locate: { nil })
    do {
        _ = try await service.startLogin()
        Issue.record("Missing CLI must fail")
    } catch let error as AppError {
        #expect(error.debugDetail == "auth_executable_missing")
    } catch { Issue.record("Expected actionable missing-CLI error") }
    await service.shutdown()
}

@Test func authenticationMatchesCompletionAndConfirmsAccountUsingSyntheticRPC() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("synthetic-codex")
    let script = #"""
    #!/usr/bin/python3
    import json, sys
    login_id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    def emit(value):
        print(json.dumps(value), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request["method"]
        if method == "account/login/start":
            emit({"id": request["id"], "result": {"type": "chatgpt", "loginId": login_id, "authUrl": "https://auth.openai.com/authorize?state=synthetic"}})
            emit({"method": "account/login/completed", "params": {"loginId": login_id, "success": True}})
        elif method == "account/read":
            emit({"id": request["id"], "result": {"account": {"type": "chatgpt", "planType": "unknown"}}})
        else:
            emit({"id": request["id"], "result": {}})
    """#
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let service = AuthenticationService(locate: { executable })
    do {
        let login = try await service.startLogin()
        try await service.waitForLogin(login.loginId)
        #expect(try await service.checkStatus() == .chatGPT)
        try await service.logout()
        await service.shutdown()
    } catch { await service.shutdown(); throw error }
}

@Test func officialBrowserLoginRejectsUntrustedURLs() throws {
    let id = UUID().uuidString
    let valid = Data("{\"type\":\"chatgpt\",\"loginId\":\"\(id)\",\"authUrl\":\"https://auth.openai.com/authorize?state=synthetic\"}".utf8)
    #expect(try BrowserLogin.validated(valid).loginId == id)
    for url in ["http://auth.openai.com/", "https://auth.openai.com.evil.invalid/", "https://evil.invalid/", "file:///tmp/invalid", "https://name:pass@auth.openai.com/", "https://auth.openai.com:8888/"] {
        let data = try JSONSerialization.data(withJSONObject: ["type": "chatgpt", "loginId": id, "authUrl": url])
        #expect(throws: Error.self) { try BrowserLogin.validated(data) }
    }
    #expect(throws: Error.self) { try BrowserLogin.validated(Data("{}".utf8)) }
}

@Test func smartRefreshSeparatesQuotaAndSessionCadence() {
    #expect(RefreshPolicy.smart.quotaInterval(remaining: 62) == 900)
    #expect(RefreshPolicy.smart.quotaInterval(remaining: 20) == 900)
    #expect(RefreshPolicy.smart.quotaInterval(remaining: 19) == 300)
    #expect(RefreshPolicy.smart.quotaInterval(remaining: 4) == 300)
    #expect(RefreshPolicy.smart.quotaInterval(remaining: .nan) == 900)
    #expect(RefreshPolicy.smart.scanInterval == 1800)
    #expect(RefreshPolicy.manual.quotaInterval(remaining: 0) == nil)
    #expect(RefreshPolicy.manual.scanInterval == nil)
    #expect(RefreshPolicy.hourly.scanInterval == 3600)
}

@Test func refreshPreferenceBackupReadsLegacyAndRejectsUnknownPolicy() throws {
    var settings = BackupSettings(appearance: "system", menuSource: "codex", menuStyle: "dualQuota",
        menuValue: "remaining", refreshAutomatically: true, hidePaths: true,
        notifyCodex25: false, notifyCodex10: false, notifyCodexReset: false, notifyClaude25: false,
        welcomeCompleted: true)
    let legacy = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(BackupSettings.self, from: legacy).refreshPolicy == nil)
    settings.refreshPolicy = "hourly"
    var document = BackupDocument(settings: settings, projectRules: [], adjustments: [], manualUsage: [], quotaHistory: [], modelPrices: [])
    try BackupValidation.validate(document)
    try BackupValidation.validateShape(JSONEncoder().encode(document))
    document.settings.refreshPolicy = "invalid"
    #expect(throws: BackupError.self) { try BackupValidation.validate(document) }
}
