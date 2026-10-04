import Foundation
import UsageCore

@main struct ClaudeQuotaBridgeCommand {
    static func main() async {
        do {
            var data = Data()
            while let part = try FileHandle.standardInput.read(upToCount: 16 * 1024), !part.isEmpty {
                guard data.count + part.count <= 2 * 1024 * 1024 else { return }
                data.append(part)
            }
            guard let executable = ExecutableLocator.locate("claude") else { print("额度暂不可用"); return }
            guard let key = try await ClaudeBridgeAccountCache.resolve(executable: executable) else { print("额度暂不可用"); return }
            let saved = try ClaudeQuotaBridge.captureBound(data, accountKey: key)
            // A minimal status line remains visible when this helper is used as the command.
            print(saved ? "额度已同步" : "额度暂不可用")
        } catch { print("用量快照暂不可用") }
    }
}
