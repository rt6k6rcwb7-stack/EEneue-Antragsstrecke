import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Konfiguration der WHOOP-Anbindung.
///
/// Das OAuth-Client-Secret liegt NICHT in der App. Der Austausch Code → Token und die
/// Token-Erneuerung laufen über einen eigenen, minimalen Token-Broker (Backend/whoop-token-broker),
/// der das Secret serverseitig verwahrt.
public struct WhoopConfiguration: Codable, Hashable, Sendable {
    public var clientId: String
    public var redirectURI: String
    public var brokerBaseURL: URL
    public var authorizeURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    public var apiBaseURL = URL(string: "https://api.prod.whoop.com/developer")!
    /// `offline` wird für den Erhalt eines Refresh-Tokens benötigt.
    public var scopes = ["read:recovery", "read:sleep", "read:cycles", "read:workout", "offline"]

    public init(clientId: String, redirectURI: String, brokerBaseURL: URL) {
        self.clientId = clientId; self.redirectURI = redirectURI; self.brokerBaseURL = brokerBaseURL
    }

    public var isComplete: Bool { !clientId.isEmpty && !redirectURI.isEmpty && brokerBaseURL.scheme == "https" }
}

public enum WhoopAuthError: Error, LocalizedError, Equatable {
    case stateMismatch, missingCode, accessDenied(String)
    public var errorDescription: String? {
        switch self {
        case .stateMismatch: return "Sicherheitsprüfung (state) fehlgeschlagen."
        case .missingCode: return "Kein Autorisierungscode erhalten."
        case .accessDenied(let r): return "Zugriff verweigert: \(r)"
        }
    }
}

public struct WhoopAuthorization: Sendable {
    public static let tokenKey = "whoop.oauth"
    public var config: WhoopConfiguration
    public init(config: WhoopConfiguration) { self.config = config }

    /// Zufälliger `state` (≥ 8 Zeichen, von WHOOP gefordert) gegen CSRF.
    public static func makeState() -> String {
        (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8) }.joined()
    }

    public func authorizationURL(state: String) -> URL {
        var c = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return c.url!
    }

    /// Wertet die Rückleitung aus und prüft den `state`.
    public func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        if let e = v("error") { throw WhoopAuthError.accessDenied(v("error_description") ?? e) }
        guard v("state") == expectedState else { throw WhoopAuthError.stateMismatch }
        guard let code = v("code"), !code.isEmpty else { throw WhoopAuthError.missingCode }
        return code
    }
}

/// Client für Token-Broker und WHOOP API v2.
public final class WhoopClient: @unchecked Sendable {
    public let config: WhoopConfiguration
    let http: HTTPClient
    let tokens: TokenStore
    let now: @Sendable () -> Date
    public var pageLimit = 25

    public init(config: WhoopConfiguration, http: HTTPClient = URLSessionHTTPClient(), tokens: TokenStore,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config; self.http = http; self.tokens = tokens; self.now = now
    }

    // MARK: Token

    public func exchange(code: String) async throws -> OAuthToken {
        let token = try await brokerRequest(path: "whoop/token", body: ["code": code, "redirect_uri": config.redirectURI])
        try tokens.saveToken(token, for: WhoopAuthorization.tokenKey)
        return token
    }

    func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard let rt = token.refreshToken else { throw ProviderError.notAuthorized }
        var fresh = try await brokerRequest(path: "whoop/refresh", body: ["refresh_token": rt])
        if fresh.refreshToken == nil { fresh.refreshToken = rt }
        try tokens.saveToken(fresh, for: WhoopAuthorization.tokenKey)
        return fresh
    }

    private func brokerRequest(path: String, body: [String: String]) async throws -> OAuthToken {
        var req = URLRequest(url: config.brokerBaseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await http.send(req)
        guard (200..<300).contains(resp.statusCode) else {
            throw resp.statusCode == 400 || resp.statusCode == 401 ? ProviderError.notAuthorized : ProviderError.server(status: resp.statusCode)
        }
        do { return try JSONDecoder().decode(WhoopTokenResponse.self, from: data).token(issuedAt: now()) }
        catch { throw ProviderError.decoding("Token-Antwort") }
    }

    func validToken() async throws -> OAuthToken {
        guard let t = try tokens.loadToken(for: WhoopAuthorization.tokenKey) else { throw ProviderError.notAuthorized }
        return t.isExpired(at: now()) ? try await refresh(t) : t
    }

    public var isConnected: Bool { ((try? tokens.loadToken(for: WhoopAuthorization.tokenKey)) ?? nil) != nil }

    /// Widerruf: WHOOP-Zugriff serverseitig beenden (sofern möglich) und Token lokal löschen.
    public func disconnect() async {
        if let t = try? await validToken() {
            var req = URLRequest(url: config.apiBaseURL.appendingPathComponent("v2/user/access"))
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await http.send(req)
        }
        try? tokens.deleteToken(for: WhoopAuthorization.tokenKey)
    }

    // MARK: API

    func get(_ path: String, query: [URLQueryItem], retryOnAuth: Bool = true) async throws -> Data {
        let token = try await validToken()
        var c = URLComponents(url: config.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await http.send(req)
        switch resp.statusCode {
        case 200..<300: return data
        case 401 where retryOnAuth:
            _ = try await refresh(token)
            return try await get(path, query: query, retryOnAuth: false)
        case 401, 403: throw ProviderError.notAuthorized
        case 429:
            let ra = (resp.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
            throw ProviderError.rateLimited(retryAfter: ra)
        default: throw ProviderError.server(status: resp.statusCode)
        }
    }

    /// Lädt alle Seiten einer Sammlung im Zeitraum.
    public func collection<T: Decodable & Sendable>(_ path: String, start: Date, end: Date, as: T.Type, maxPages: Int = 40) async throws -> [T] {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var all: [T] = []
        var next: String?
        var pages = 0
        repeat {
            var q = [URLQueryItem(name: "limit", value: String(pageLimit)),
                     URLQueryItem(name: "start", value: iso.string(from: start)),
                     URLQueryItem(name: "end", value: iso.string(from: end))]
            if let n = next { q.append(URLQueryItem(name: "nextToken", value: n)) }
            let data = try await get(path, query: q)
            let page: WhoopPage<T>
            do { page = try WhoopDate.decoder.decode(WhoopPage<T>.self, from: data) }
            catch { throw ProviderError.decoding("\(path): \(error)") }
            all += page.records
            next = page.nextToken?.isEmpty == false ? page.nextToken : nil
            pages += 1
        } while next != nil && pages < maxPages
        return all
    }
}

/// Abbildung von WHOOP-Daten auf das geräteunabhängige Modell. Nicht bewertete Datensätze
/// (PENDING_SCORE, UNSCORABLE) erzeugen KEINE Werte.
public enum WhoopMapper {
    public static func samples(recoveries: [WhoopRecovery], sleeps: [WhoopSleep], cycles: [WhoopCycle],
                               workouts: [WhoopWorkout], importedAt: Date = Date()) -> [VitalSample] {
        var out: [VitalSample] = []
        let sleepById = Dictionary(sleeps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for r in recoveries where r.scoreState == .scored {
            guard let s = r.score else { continue }
            let quality: MeasurementQuality = s.userCalibrating == true ? .calibrating : .derived
            let sleep = r.sleepId.flatMap { sleepById[$0] }
            let start = sleep?.start ?? r.createdAt
            let end = sleep?.end ?? r.createdAt
            let rid = r.sleepId ?? r.cycleId.map(String.init) ?? "\(r.createdAt.timeIntervalSince1970)"
            func add(_ t: VitalType, _ v: Double?, q: MeasurementQuality) {
                guard let v else { return }
                out.append(VitalSample(type: t, value: v, start: start, end: end, source: .whoop, channel: .whoopAPI,
                                       sourceRecordId: "recovery-\(rid)", quality: q, importedAt: importedAt))
            }
            add(.recoveryScore, s.recoveryScore, q: quality)
            add(.restingHeartRate, s.restingHeartRate, q: s.userCalibrating == true ? .calibrating : .measured)
            add(.hrvRMSSD, s.hrvRmssdMilli, q: s.userCalibrating == true ? .calibrating : .measured)
            add(.oxygenSaturation, s.spo2Percentage, q: .measured)
        }

        for s in sleeps where s.scoreState == .scored && !s.nap {
            guard let st = s.score?.stageSummary else { continue }
            func minutes(_ ms: Double?) -> Double? { ms.map { $0 / 60000 } }
            let light = minutes(st.totalLightSleepTimeMilli), deep = minutes(st.totalSlowWaveSleepTimeMilli), rem = minutes(st.totalRemSleepTimeMilli)
            let total: Double? = (light == nil && deep == nil && rem == nil) ? nil : (light ?? 0) + (deep ?? 0) + (rem ?? 0)
            func add(_ t: VitalType, _ v: Double?) {
                guard let v else { return }
                out.append(VitalSample(type: t, value: v, start: s.start, end: s.end, source: .whoop, channel: .whoopAPI,
                                       sourceRecordId: "sleep-\(s.id)", quality: .derived, importedAt: importedAt))
            }
            add(.sleepDuration, total)
            add(.sleepLight, light); add(.sleepDeep, deep); add(.sleepREM, rem)
            add(.sleepAwake, minutes(st.totalAwakeTimeMilli))
            add(.respiratoryRate, s.score?.respiratoryRate)
        }

        for c in cycles where c.scoreState == .scored {
            guard let strain = c.score?.strain else { continue }
            out.append(VitalSample(type: .strain, value: strain, start: c.start, end: c.end, source: .whoop, channel: .whoopAPI,
                                   sourceRecordId: "cycle-\(c.id)", quality: .derived, importedAt: importedAt))
        }

        for w in workouts {
            out.append(VitalSample(type: .workoutDuration, value: w.end.timeIntervalSince(w.start) / 60, start: w.start, end: w.end,
                                   source: .whoop, channel: .whoopAPI, deviceId: w.sportName,
                                   sourceRecordId: "workout-\(w.id)", quality: .measured, importedAt: importedAt))
        }
        return out
    }
}

/// WHOOP als Vitaldatenquelle für den SyncCoordinator.
public struct WhoopProvider: VitalDataProvider {
    public let kind = IntegrationKind.whoop
    let client: WhoopClient
    public init(client: WhoopClient) { self.client = client }

    public func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch {
        let start = since ?? until.addingTimeInterval(-30 * 86400)
        async let rec = client.collection("v2/recovery", start: start, end: until, as: WhoopRecovery.self)
        async let slp = client.collection("v2/activity/sleep", start: start, end: until, as: WhoopSleep.self)
        async let cyc = client.collection("v2/cycle", start: start, end: until, as: WhoopCycle.self)
        async let wo = client.collection("v2/activity/workout", start: start, end: until, as: WhoopWorkout.self)
        let samples = try await WhoopMapper.samples(recoveries: rec, sleeps: slp, cycles: cyc, workouts: wo)
        return ProviderBatch(samples: samples, cursor: nil, syncedUntil: until)
    }
}
