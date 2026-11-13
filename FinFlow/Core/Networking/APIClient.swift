import Foundation

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, server(String), unauthorized, decoding
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "La dirección del servidor no es válida."
        case .invalidResponse: return "El servidor devolvió una respuesta no válida."
        case .server(let message): return message
        case .unauthorized: return "Tu sesión venció. Inicia sesión nuevamente."
        case .decoding: return "No pudimos interpretar la respuesta del servidor."
        }
    }
}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    private let session: URLSession
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 60
        #if DEBUG
        if ProcessInfo.processInfo.environment["FINFLOW_UI_TESTING"] == "1" {
            config.protocolClasses = [PreviewAPIProtocol.self]
        }
        #endif
        session = URLSession(configuration: config)
    }
    init(session: URLSession) { self.session = session }
    // Fixed HTTPS API origin; arbitrary hosts must never receive bearer credentials.
    let baseURL = "https://finflow-backend-production.up.railway.app"

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil, query: [String: String] = [:], responseType: T.Type = T.self) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request, hasJSONBody: body != nil)
        if let body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, response) = try await sendWithRenewal(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                invalidateOnlyTokenUsed(by: request)
                throw APIError.unauthorized
            }
            let serverMessage = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (serverMessage?["message"] as? String) ?? (serverMessage?["error"] as? String)
            throw APIError.server(message.map { String($0.prefix(280)) } ?? "Error HTTP \(http.statusCode)")
        }
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            notifyFinancialChange(path: path, method: method)
            return decoded
        }
        catch { throw APIError.decoding }
    }

    func perform(_ path: String, method: String = "GET", body: Encodable? = nil) async throws {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request, hasJSONBody: body != nil)
        if let body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, response) = try await sendWithRenewal(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                // A delayed response must never revoke a newer Keychain session.
                invalidateOnlyTokenUsed(by: request)
                throw APIError.unauthorized
            }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (payload?["message"] as? String) ?? (payload?["error"] as? String)
            throw APIError.server(message.map { String($0.prefix(280)) } ?? "Error HTTP \(http.statusCode)")
        }
        notifyFinancialChange(path: path, method: method)
    }

    private func notifyFinancialChange(path: String, method: String) {
        guard method != "GET", ["/transactions", "/accounts", "/goals", "/planned-expenses", "/recurring", "/budgets", "/categories"].contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
        NotificationCenter.default.post(name: .finflowFinanceChanged, object: nil)
    }

    private func sendWithRenewal(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await session.data(for: request)
        guard let http = result.1 as? HTTPURLResponse, http.statusCode == 401,
              !["/auth/login", "/auth/register", "/auth/refresh", "/auth/logout"].contains(request.url?.path ?? "") else { return result }
        let sentToken = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
        do {
            if try await SessionRenewal.shared.renew(failedToken: sentToken) {
                var replay = request
                applyHeaders(to: &replay, hasJSONBody: replay.httpBody != nil)
                let renewedResult = try await session.data(for: replay)
                if (renewedResult.1 as? HTTPURLResponse)?.statusCode == 401 {
                    invalidateOnlyTokenUsed(by: replay)
                    throw APIError.unauthorized
                }
                return renewedResult
            }
        } catch APIError.unauthorized {
            invalidateOnlyTokenUsed(by: request)
            throw APIError.unauthorized
        }
        return result
    }

    /// Only the exact token that received a 401 may be removed. A response
    /// from an older request must never terminate a newer login on this device.
    private func invalidateOnlyTokenUsed(by request: URLRequest) {
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              header.hasPrefix("Bearer ") else { return }
        let sentToken = String(header.dropFirst("Bearer ".count))
        TokenStore.shared.deleteSession(ifTokenMatches: sentToken)
    }

    /// The backend resolves ownership exclusively from the verified bearer JWT.
    private func applyHeaders(to request: inout URLRequest, hasJSONBody: Bool) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Type")
        if hasJSONBody { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // Public login/registration must not carry a stale bearer token.
        // A previous authenticated session must not be revoked by a failed login.
        guard !["/auth/login", "/auth/register", "/auth/refresh", "/auth/logout"].contains(request.url?.path ?? "") else { return }
        if let token = TokenStore.shared.read("token"), !token.isEmpty {
            request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
    }

    func download(_ path: String, query: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.invalidURL }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        applyHeaders(to: &request, hasJSONBody: false)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await sendWithRenewal(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            invalidateOnlyTokenUsed(by: request)
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server("No fue posible exportar el archivo.") }
        return data
    }
}

extension Notification.Name {
    static let finflowFinanceChanged = Notification.Name("finflow.financeChanged")
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

/// One in-flight renewal per process; raw credentials remain in Keychain.
actor SessionRenewal {
    static let shared = SessionRenewal()
    private var pending: Task<Bool, Error>?

    func renew(failedToken: String?) async throws -> Bool {
        let current = TokenStore.shared.read("token")
        if current != failedToken { return sameOwner(current, failedToken) }
        if let pending { return try await pending.value }
        let work = Task<Bool, Error> {
            let refresh = TokenStore.shared.read("refreshToken").flatMap { $0.isEmpty ? nil : $0 }
            guard current != nil || refresh != nil else { return false }
            let path = refresh == nil ? "/auth/session" : "/auth/refresh"
            var request = URLRequest(url: URL(string: APIClient.shared.baseURL + path)!)
            request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let refresh { request.httpBody = try JSONEncoder().encode(["refreshToken": refresh]) }
            else {
                if let current { request.setValue("Bearer " + current, forHTTPHeaderField: "Authorization") }
                request.httpBody = Data("{}".utf8)
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
            let (data, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.server("No pudimos renovar la sesión. Revisa tu conexión.") }
            let tokens = try JSONDecoder().decode(AuthResponse.self, from: data)
            return TokenStore.shared.replaceCredentials(tokens, ifTokenMatches: current)
        }
        pending = work
        defer { pending = nil }
        return try await work.value
    }

    private func sameOwner(_ first: String?, _ second: String?) -> Bool {
        func subject(_ token: String?) -> String? {
            guard let encoded = token?.split(separator: ".").dropFirst().first else { return nil }
            var base = String(encoded).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base += String(repeating: "=", count: (4 - base.count % 4) % 4)
            guard let data = Data(base64Encoded: base),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object["sub"] as? String
        }
        guard let firstSubject = subject(first), let secondSubject = subject(second) else { return false }
        return firstSubject == secondSubject
    }
}
