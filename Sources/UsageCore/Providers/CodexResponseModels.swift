import Foundation

struct CodexAccountResponse: Decodable {
    let account: CodexAccount?

    enum CodingKeys: String, CodingKey { case account }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.account) else { throw ProviderError.unsupportedVersion }
        account = try container.decodeIfPresent(CodexAccount.self, forKey: .account)
    }
}

struct CodexAccount: Decodable {
    let type: String?
    let email: String?
    let planType: String?
}
