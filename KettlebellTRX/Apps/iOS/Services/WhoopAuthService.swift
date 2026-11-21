import Foundation
import AuthenticationServices
import UIKit
import FitnessCore

/// Führt den OAuth-2.0-Autorisierungscode-Ablauf für WHOOP im System-Browser durch.
@MainActor
final class WhoopAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(config: WhoopConfiguration, client: WhoopClient) async throws -> OAuthToken {
        let auth = WhoopAuthorization(config: config)
        let state = WhoopAuthorization.makeState()
        guard let scheme = URL(string: config.redirectURI)?.scheme else { throw WhoopAuthError.missingCode }
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: auth.authorizationURL(state: state), callbackURLScheme: scheme) { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: WhoopAuthError.missingCode) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = true
            session = s
            s.start()
        }
        let code = try auth.code(fromCallback: callback, expectedState: state)
        return try await client.exchange(code: code)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
