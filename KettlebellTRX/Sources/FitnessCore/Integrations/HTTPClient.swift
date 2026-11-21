import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimale HTTP-Abstraktion (testbar, austauschbar).
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme == "https" else { throw ProviderError.network("Nur verschlüsselte Verbindungen (HTTPS) erlaubt") }
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.dataTask(with: request) { d, r, e in
                if let e { cont.resume(throwing: ProviderError.network(e.localizedDescription)); return }
                cont.resume(returning: (d ?? Data(), r!))
            }
            task.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw ProviderError.network("Keine HTTP-Antwort") }
        return (data, http)
    }
}

/// OAuth-Token. Wird ausschließlich im Schlüsselbund (Keychain) gespeichert.
public struct OAuthToken: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scope: String
    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.scope = scope
    }
    public func isExpired(at now: Date, leeway: TimeInterval = 120) -> Bool { now.addingTimeInterval(leeway) >= expiresAt }
}

/// Sicherer Token-Speicher (iOS: Keychain, Tests: im Speicher).
public protocol TokenStore: Sendable {
    func loadToken(for key: String) throws -> OAuthToken?
    func saveToken(_ token: OAuthToken, for key: String) throws
    func deleteToken(for key: String) throws
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var tokens: [String: OAuthToken] = [:]
    private let lock = NSLock()
    public init() {}
    public func loadToken(for key: String) throws -> OAuthToken? { lock.lock(); defer { lock.unlock() }; return tokens[key] }
    public func saveToken(_ token: OAuthToken, for key: String) throws { lock.lock(); tokens[key] = token; lock.unlock() }
    public func deleteToken(for key: String) throws { lock.lock(); tokens[key] = nil; lock.unlock() }
}
