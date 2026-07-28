import Foundation

enum AppConfiguration {
    static var apiBaseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BikeGoGoAPIBaseURL") as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        return URL(string: "http://localhost:8080")!
    }

    static var privacyPolicyURL: URL {
        if let value = Bundle.main.object(
            forInfoDictionaryKey: "BikeGoGoPrivacyPolicyURL"
        ) as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        return URL(
            string: "https://github.com/sssnto/bikegogogo/blob/main/docs/PRIVACY_POLICY.md"
        )!
    }
}
