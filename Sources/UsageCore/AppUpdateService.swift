import Foundation

/// The release formats supported by our publishing workflow; unknown suffixes are ignored.
public struct AppReleaseVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let isPreview: Bool

    public init?(tag: String) {
        guard tag.hasPrefix("v"), tag.count <= 64 else { return nil }
        let preview = tag.hasSuffix("-preview")
        let number = preview ? String(tag.dropFirst().dropLast(8)) : String(tag.dropFirst())
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let value = Int(part) else { return nil }
            values.append(value)
        }
        major = values[0]; minor = values[1]; patch = values[2]; isPreview = preview
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return lhs.isPreview && !rhs.isPreview
    }
}

public struct AppUpdate: Equatable, Sendable {
    public let tag: String
    public let isPreview: Bool
    public let notes: String
    public let releaseURL: URL
    public let downloadURL: URL
}

public enum AppUpdateResult: Equatable, Sendable {
    case available(AppUpdate)
    case upToDate
    case noCompatibleRelease
}

public enum AppUpdateError: Error, LocalizedError, Equatable, Sendable {
    case invalidResponse, responseTooLarge, rateLimited, unavailable, artifactUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "GitHub 发布信息格式无法识别，请稍后重试或查看发布页面。"
        case .responseTooLarge: "发布信息过大，已停止读取。请查看 GitHub 发布页面。"
        case .rateLimited: "GitHub 请求次数受限，请稍后重试或查看发布页面。"
        case .unavailable: "暂时无法获取 GitHub 发布信息，请稍后重试。"
        case .artifactUnavailable: "发现新版本，但对应 DMG 尚不可下载。请稍后重试或查看发布页面。"
        }
    }
}

/// Public release metadata only. No credentials, cookies, telemetry or local usage are sent.
public struct AppUpdateService: Sendable {
    public init() {}

    public func check(current: AppReleaseVersion, includePreviews: Bool) async throws -> AppUpdateResult {
        guard let endpoint = URL(string: "https://api.github.com/repos/koajsj/codexusager/releases?per_page=100") else {
            throw AppUpdateError.invalidResponse
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CodexUsager-UpdateCheck", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == endpoint else {
            throw AppUpdateError.invalidResponse
        }
        if http.statusCode == 403 || http.statusCode == 429 { throw AppUpdateError.rateLimited }
        guard http.statusCode == 200 else { throw AppUpdateError.unavailable }
        let limit = 2 * 1_024 * 1_024
        guard response.expectedContentLength <= Int64(limit) else { throw AppUpdateError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw AppUpdateError.responseTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try Self.evaluate(data, current: current, includePreviews: includePreviews)
    }

    static func evaluate(_ data: Data, current: AppReleaseVersion, includePreviews: Bool) throws -> AppUpdateResult {
        let releases: [Release]
        do { releases = try JSONDecoder().decode([Release].self, from: data) }
        catch { throw AppUpdateError.invalidResponse }
        let candidates = releases.compactMap { release -> (Release, AppReleaseVersion)? in
            guard !release.draft, let version = AppReleaseVersion(tag: release.tag_name),
                  version.isPreview == release.prerelease, includePreviews || !version.isPreview else { return nil }
            return (release, version)
        }
        guard let (release, version) = candidates.max(by: { $0.1 < $1.1 }) else { return .noCompatibleRelease }
        guard version > current else { return .upToDate }
        let base = "https://github.com/koajsj/codexusager/releases"
        let filename = "CodexUsager-\(release.tag_name).dmg"
        let expectedPage = "\(base)/tag/\(release.tag_name)"
        let expectedDownload = "\(base)/download/\(release.tag_name)/\(filename)"
        guard release.html_url == expectedPage, let page = URL(string: expectedPage),
              let download = URL(string: expectedDownload), release.assets.contains(where: {
                  $0.name == filename && $0.state == "uploaded" && $0.size > 0 &&
                      $0.browser_download_url == expectedDownload
              }) else { throw AppUpdateError.artifactUnavailable }
        return .available(AppUpdate(tag: release.tag_name, isPreview: version.isPreview,
            notes: String((release.body ?? "暂无更新说明，请查看发布页面。").prefix(8_000)),
            releaseURL: page, downloadURL: download))
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int64
        let browser_download_url: String
    }
}
