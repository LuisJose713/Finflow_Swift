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
    private let defaultsKey = "finflow.apiBaseURL"
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "https://finflow-backend-yqhi.onrender.com" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: defaultsKey) }
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil, query: [String: String] = [:], responseType: T.Type = T.self) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request, hasJSONBody: body != nil)
        if let body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { TokenStore.shared.deleteAll(); throw APIError.unauthorized }
            let serverMessage = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (serverMessage?["message"] as? String) ?? (serverMessage?["error"] as? String) ?? String(data: data, encoding: .utf8) ?? "Error HTTP \(http.statusCode)"
            throw APIError.server(message)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.server("La respuesta de \(path) no coincide con el modelo esperado: \(error.localizedDescription)") }
    }

    func perform(_ path: String, method: String = "GET", body: Encodable? = nil) async throws {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request, hasJSONBody: body != nil)
        if let body { request.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { TokenStore.shared.deleteAll(); throw APIError.unauthorized }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError.server((payload?["message"] as? String) ?? "Error HTTP \(http.statusCode)")
        }
    }

    /// All protected endpoints use the same auth context. The backend's goal and
    /// planned-expense controllers additionally require X-User-Id.
    private func applyHeaders(to request: inout URLRequest, hasJSONBody: Bool) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Client-Type")
        if hasJSONBody { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token = TokenStore.shared.read("token"), !token.isEmpty {
            request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        if let userId = TokenStore.shared.read("userId"), !userId.isEmpty {
            request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        }
    }

    func download(_ path: String, query: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.invalidURL }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        applyHeaders(to: &request, hasJSONBody: false)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.server("No fue posible exportar el archivo.") }
        return data
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
