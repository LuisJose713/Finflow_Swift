import Foundation
import Combine

enum PrivacyAccessState: Equatable {
    case loading
    case accepted
    case needsConsent
    case unavailable
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var privacyAccess: PrivacyAccessState = .loading
    @Published private(set) var privacyPolicy: PrivacyPolicy?
    @Published private(set) var privacyError: String?

    func restoreSession() async {
        guard let token = TokenStore.shared.read("token"), !token.isEmpty else { return }
        do {
            let verified: AppUser = try await APIClient.shared.request("/auth/me")
            user = verified
            isAuthenticated = true
            await refreshPrivacyAccess()
        } catch {
            TokenStore.shared.deleteAll()
            user = nil
            isAuthenticated = false
            errorMessage = "Tu sesión caducó. Vuelve a iniciar sesión."
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: AuthResponse = try await APIClient.shared.request(
                "/auth/login", method: "POST",
                body: LoginRequest(email: email, password: password))
            persist(response)
            await refreshPrivacyAccess()
        } catch { errorMessage = error.localizedDescription }
    }

    func register(name: String, email: String, password: String,
                  privacyVersion: String, marketingConsent: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard !privacyVersion.isEmpty else {
            errorMessage = "La política de privacidad no está disponible."
            return
        }
        do {
            let response: AuthResponse = try await APIClient.shared.request(
                "/auth/register", method: "POST",
                body: RegisterRequest(
                    name: name, email: email, password: password,
                    privacyAccepted: true, privacyVersion: privacyVersion,
                    marketingConsent: marketingConsent))
            persist(response)
            await refreshPrivacyAccess()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshPrivacyAccess() async {
        guard isAuthenticated else { return }
        privacyAccess = .loading
        privacyError = nil
        do {
            let status: PrivacyStatus = try await APIClient.shared.request("/privacy/status")
            guard status.policyReady else {
                privacyAccess = .unavailable
                privacyError = "El responsable del tratamiento de datos todavía no ha publicado los datos legales requeridos."
                return
            }
            if status.accepted {
                privacyPolicy = nil
                privacyAccess = .accepted
            } else {
                let policy: PrivacyPolicy = try await APIClient.shared.request("/privacy/policy")
                guard policy.ready, policy.version == status.version else {
                    privacyAccess = .unavailable
                    privacyError = "La política vigente no pudo validarse."
                    return
                }
                privacyPolicy = policy
                privacyAccess = .needsConsent
            }
        } catch {
            privacyError = "No se pudo comprobar tu autorización: \(error.localizedDescription)"
            privacyAccess = .unavailable
        }
    }

    func acceptPrivacy(policyVersion: String, marketing: Bool) async {
        guard isAuthenticated,
              privacyAccess == .needsConsent,
              privacyPolicy?.version == policyVersion else { return }
        privacyError = nil
        do {
            let response: PrivacyConsentResult = try await APIClient.shared.request(
                "/privacy/consent", method: "POST",
                body: PrivacyConsentInput(
                    accepted: true, policyVersion: policyVersion,
                    marketingConsent: marketing))
            if response.accepted && response.version == policyVersion {
                privacyAccess = .accepted
                privacyPolicy = nil
            } else {
                privacyError = "El servidor no confirmó tu aceptación."
            }
        } catch { privacyError = error.localizedDescription }
    }

    private func persist(_ response: AuthResponse) {
        TokenStore.shared.save(response.token, account: "token")
        TokenStore.shared.save(String(response.user.id), account: "userId")
        TokenStore.shared.save(response.user.name, account: "userName")
        TokenStore.shared.save(response.user.email, account: "email")
        user = response.user
        isAuthenticated = true
        privacyAccess = .loading
    }

    func logout() {
        TokenStore.shared.deleteAll()
        user = nil
        isAuthenticated = false
        privacyPolicy = nil
        privacyError = nil
        privacyAccess = .loading
    }
}
