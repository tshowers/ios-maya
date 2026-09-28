import Foundation

struct AppConfig {
    let apiBaseURL: URL
    let apiKey: String
    let mayaProductId: String

    static func fromBundle(bundle: Bundle = .main) -> AppConfig {
        let baseURLString = bundle.object(forInfoDictionaryKey: "MAYA_API_BASE_URL") as? String ?? ""
        let apiKey = bundle.object(forInfoDictionaryKey: "MAYA_API_KEY") as? String ?? ""
        let mayaProductId = bundle.object(forInfoDictionaryKey: "MAYA_APP_STORE_PRODUCT_ID") as? String ?? ""

        guard let apiBaseURL = URL(string: baseURLString) else {
            fatalError("Missing MAYA_API_BASE_URL in app configuration.")
        }

        return AppConfig(apiBaseURL: apiBaseURL, apiKey: apiKey, mayaProductId: mayaProductId)
    }
}
