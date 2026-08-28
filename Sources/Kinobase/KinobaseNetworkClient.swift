import Foundation
import Alamofire

public final class KinobaseNetworkClient: @unchecked Sendable {
    public static let baseURL = "https://kinobase.org"

    private let session: Session = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        ]
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        return Session(configuration: config)
    }()
    
    public func get(url: String, headers: HTTPHeaders? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: .get, headers: headers).responseData { response in
                continuation.resume(with: response.result.mapError { $0 as Error })
            }
        }
    }
    
    public func getString(url: String, parameters: Parameters? = nil, headers: HTTPHeaders? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: .get, parameters: parameters, headers: headers).responseString { response in
                continuation.resume(with: response.result.mapError { $0 as Error })
            }
        }
    }
    
    public func post(
        url: String,
        parameters: Parameters,
        headers: HTTPHeaders? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: .post, parameters: parameters, headers: headers)
                .responseData { response in
                    continuation.resume(with: response.result.mapError { $0 as Error })
                }
        }
    }
    
    public func postDecodable<T: Decodable>(
        url: String,
        parameters: Parameters,
        headers: HTTPHeaders? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: .post, parameters: parameters, headers: headers)
                .responseDecodable(of: type) { response in
                    continuation.resume(with: response.result.mapError { $0 as Error })
                }
        }
    }
    
    public func cookiesString(for urlString: String) -> String {
        guard let url = URL(string: urlString),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return "" }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
    }
    
    public init() {}
}
