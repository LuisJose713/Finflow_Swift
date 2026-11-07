import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func restoreSession() async {
        guard let token = TokenStore.shared.read("token"), !token.isEmpty else { return }
        do {
            // Restore only after the API confirms JWT validity and current server-side role.
            let verified: AppUser = try await APIClient.shared.request("/auth/me")
            user = verified
            isAuthenticated = true
        } catch {
            // Never treat cached identity as an authenticated session.
            TokenStore.shared.deleteAll()
            user = nil
            isAuthenticated = false
            errorMessage = "Tu sesión caducó. Vuelve a iniciar sesión."
        }
    }

    func login(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response: AuthResponse = try await APIClient.shared.request("/auth/login", method: "POST", body: LoginRequest(email: email, password: password))
            persist(response)
        } catch { errorMessage = error.localizedDescription }
    }
    func register(name: String, email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response: AuthResponse = try await APIClient.shared.request("/auth/register", method: "POST", body: RegisterRequest(name: name, email: email, password: password))
            persist(response)
        } catch { errorMessage = error.localizedDescription }
    }
    private func persist(_ response: AuthResponse) {
        TokenStore.shared.save(response.token, account: "token")
        TokenStore.shared.save(String(response.user.id), account: "userId")
        TokenStore.shared.save(response.user.name, account: "userName")
        TokenStore.shared.save(response.user.email, account: "email")
        user = response.user; isAuthenticated = true
    }
    func logout() { TokenStore.shared.deleteAll(); user = nil; isAuthenticated = false }
}
