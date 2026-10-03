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
            let auth = try await ProcessRunner.run(executable, arguments: ["auth", "status"], allowNonzero: true)
            guard let object = try JSONSerialization.jsonObject(with: auth) as? [String: Any],
                  object["loggedIn"] as? Bool == true, let email = object["email"] as? String else { print("额度暂不可用"); return }
            let saved = try ClaudeQuotaBridge.capture(data, accountIdentity: email)
            // A minimal status line remains visible when this helper is used as the command.
            print(saved ? "额度已同步" : "额度暂不可用")
        } catch { print("用量快照暂不可用") }
    }
}
