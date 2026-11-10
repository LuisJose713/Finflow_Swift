import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Guards overlapping login/register tasks from committing stale responses.
    private var authOperation = UUID()

    func restoreSession() async {
        guard let token = TokenStore.shared.read("token"), !token.isEmpty else { return }
        do {
            // Restore only after the API confirms JWT validity and current server-side role.
            let verified: AppUser = try await APIClient.shared.request("/auth/me")
            guard TokenStore.shared.read("token") == token else { return }
            user = verified
            isAuthenticated = true
        } catch {
            // Network outages or a temporary backend failure must not erase
            // a previously valid JWT. Only a confirmed 401 revokes it.
            // An in-flight restore cannot sign out a newer valid session.
            let currentToken = TokenStore.shared.read("token")
            guard currentToken == nil || currentToken == token else { return }
            user = nil
            isAuthenticated = false
            if case APIError.unauthorized = error {
                TokenStore.shared.deleteAll()
                errorMessage = "Tu sesión caducó. Vuelve a iniciar sesión."
            } else {
                errorMessage = "No pudimos comprobar tu sesión. Revisa tu conexión e inténtalo de nuevo."
            }
        }
    }

    func login(email: String, password: String) async {
        let operation = UUID()
        authOperation = operation
        isLoading = true; errorMessage = nil
        defer { if authOperation == operation { isLoading = false } }
        do {
            let response: AuthResponse = try await APIClient.shared.request("/auth/login", method: "POST", body: LoginRequest(email: email, password: password))
            guard authOperation == operation else { return }
            persist(response)
        } catch {
            if authOperation == operation { errorMessage = error.localizedDescription }
        }
    }
    func register(name: String, email: String, password: String,
                  privacyAccepted: Bool? = nil, privacyVersion: String? = nil,
                  marketingConsent: Bool? = nil) async {
        let operation = UUID()
        authOperation = operation
        isLoading = true
        errorMessage = nil
        defer { if authOperation == operation { isLoading = false } }
        do {
            let body = RegisterRequest(name: name, email: email, password: password,
                                       privacyAccepted: privacyAccepted,
                                       privacyVersion: privacyVersion,
                                       marketingConsent: marketingConsent)
            let response: AuthResponse = try await APIClient.shared.request(
                "/auth/register", method: "POST", body: body)
            guard authOperation == operation else { return }
            persist(response)
        } catch {
            if authOperation == operation { errorMessage = error.localizedDescription }
        }
    }
    private func persist(_ response: AuthResponse) {
        TokenStore.shared.save(response.token, account: "token")
        TokenStore.shared.save(String(response.user.id), account: "userId")
        TokenStore.shared.save(response.user.name, account: "userName")
        TokenStore.shared.save(response.user.email, account: "email")
        user = response.user; isAuthenticated = true
    }
    func logout() {
        authOperation = UUID()
        TokenStore.shared.deleteAll()
        user = nil
        isAuthenticated = false
        isLoading = false
        errorMessage = nil
    }
}
