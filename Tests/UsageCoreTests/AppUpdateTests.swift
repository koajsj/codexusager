import Foundation
import Testing
@testable import UsageCore

@Test func releaseVersionsCompareNumericallyAndRespectChannels() throws {
    let preview = try #require(AppReleaseVersion(tag: "v1.0.2-preview"))
    let stable = try #require(AppReleaseVersion(tag: "v1.0.2"))
    let next = try #require(AppReleaseVersion(tag: "v1.0.10-preview"))
    #expect(preview < stable)
    #expect(stable < next)
    for invalid in ["1.0.2", "v1.0", "v1.0.2-beta", "v01.0.2", "v-1.0.2", "v１.0.2", "v999999999999999999999999999999999999.0.0"] {
        #expect(AppReleaseVersion(tag: invalid) == nil)
    }
}

private func updateRelease(_ tag: String, preview: Bool, draft: Bool = false,
                           download: String? = nil, hasAsset: Bool = true) -> [String: Any] {
    let base = "https://github.com/koajsj/codexusager/releases"
    let name = "CodexUsager-\(tag).dmg"
    return ["tag_name": tag, "html_url": "\(base)/tag/\(tag)", "body": "版本说明",
        "draft": draft, "prerelease": preview,
        "assets": hasAsset ? [["name": name, "state": "uploaded", "size": 1_024,
            "browser_download_url": download ?? "\(base)/download/\(tag)/\(name)"]] : []]
}

@Test func updateCatalogSelectsVersionInsteadOfResponseOrder() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        updateRelease("v1.0.3-preview", preview: true), updateRelease("v1.0.10-preview", preview: true),
        updateRelease("v1.0.4", preview: false), updateRelease("v9.0.0", preview: false, draft: true),
        updateRelease("v8.0.0-beta", preview: true), updateRelease("v7.0.0", preview: true)])
    let current = try #require(AppReleaseVersion(tag: "v1.0.2-preview"))
    guard case .available(let preview) = try AppUpdateService.evaluate(data, current: current, includePreviews: true) else {
        Issue.record("Expected Preview update"); return
    }
    #expect(preview.tag == "v1.0.10-preview")
    #expect(preview.downloadURL.lastPathComponent == "CodexUsager-v1.0.10-preview.dmg")
    guard case .available(let stable) = try AppUpdateService.evaluate(data, current: current, includePreviews: false) else {
        Issue.record("Expected stable update"); return
    }
    #expect(stable.tag == "v1.0.4")
}

@Test func updateCatalogRejectsMissingOrForeignDownloads() throws {
    let current = try #require(AppReleaseVersion(tag: "v1.0.2-preview"))
    for release in [updateRelease("v1.0.3-preview", preview: true, hasAsset: false),
                    updateRelease("v1.0.3-preview", preview: true, download: "https://invalid.example/App.dmg")] {
        let data = try JSONSerialization.data(withJSONObject: [release])
        #expect(throws: AppUpdateError.artifactUnavailable) {
            try AppUpdateService.evaluate(data, current: current, includePreviews: true)
        }
    }
    #expect(throws: AppUpdateError.invalidResponse) {
        try AppUpdateService.evaluate(Data("{}".utf8), current: current, includePreviews: true)
    }
}

@Test func updateCatalogDistinguishesNoReleaseAndUpToDate() throws {
    let current = try #require(AppReleaseVersion(tag: "v1.0.2-preview"))
    #expect(try AppUpdateService.evaluate(Data("[]".utf8), current: current, includePreviews: true) == .noCompatibleRelease)
    let data = try JSONSerialization.data(withJSONObject: [updateRelease("v1.0.2-preview", preview: true)])
    #expect(try AppUpdateService.evaluate(data, current: current, includePreviews: true) == .upToDate)
    #expect(try AppUpdateService.evaluate(data, current: current, includePreviews: false) == .noCompatibleRelease)
}
