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
    private var expiryObserver: AnyCancellable?

    init() {
        expiryObserver = NotificationCenter.default.publisher(for: .finflowSessionExpired)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, TokenStore.shared.read("token") == nil else { return }
                if let ownerID = self.user?.id { OfflineTransactionStore.shared.clear(userID: ownerID) }
                self.authOperation = UUID()
                self.user = nil
                self.isAuthenticated = false
                self.isLoading = false
                self.errorMessage = "Tu sesión se cerró. Vuelve a iniciar sesión."
            }
    }

    func restoreSession() async {
        let operation = authOperation
        let token = TokenStore.shared.read("token")
        guard token?.isEmpty == false || TokenStore.shared.read("refreshToken")?.isEmpty == false else { return }
        do {
            // Restore only after the API confirms JWT validity and current server-side role.
            let verified: AppUser = try await APIClient.shared.request("/auth/me")
            if TokenStore.shared.read("refreshToken")?.isEmpty != false {
                _ = try? await SessionRenewal.shared.renew(failedToken: TokenStore.shared.read("token"))
            }
            guard authOperation == operation else { return }
            user = verified
            isAuthenticated = true
        } catch {
            // Network outages or a temporary backend failure must not erase
            // a previously valid JWT. Only a confirmed 401 revokes it.
            // An in-flight restore cannot sign out a newer valid session.
            guard authOperation == operation else { return }
            user = nil
            isAuthenticated = false
            if case APIError.unauthorized = error {
                TokenStore.shared.deleteAll()
                errorMessage = "Tu sesión caducó. Vuelve a iniciar sesión."
            } else {
                if let id = TokenStore.shared.read("userId").flatMap(Int.init),
                   let email = TokenStore.shared.read("email"), let name = TokenStore.shared.read("userName") {
                    user = AppUser(id: id, email: email, name: name)
                    isAuthenticated = true
                }
                errorMessage = "Sin conexión. Tu sesión sigue guardada; algunas funciones requieren internet."
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
            try persist(response)
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
            try persist(response)
        } catch {
            if authOperation == operation { errorMessage = error.localizedDescription }
        }
    }
    private func persist(_ response: AuthResponse) throws {
        guard TokenStore.shared.saveCredentials(response) else {
            throw APIError.server("No pudimos guardar tu sesión de forma segura. Desbloquea el dispositivo e inténtalo de nuevo.")
        }
        user = response.user; isAuthenticated = true
    }
    func logout() {
        let refresh = TokenStore.shared.read("refreshToken")
        if let ownerID = user?.id { OfflineTransactionStore.shared.clear(userID: ownerID) }
        authOperation = UUID()
        TokenStore.shared.deleteAll()
        user = nil
        isAuthenticated = false
        isLoading = false
        errorMessage = nil
        if let refresh, !refresh.isEmpty {
            Task { try? await APIClient.shared.perform("/auth/logout", method: "POST", body: ["refreshToken": refresh]) }
        }
    }
}


/// Only presentation choices are stored here. The server binds them to the JWT owner.
@MainActor
final class UiPreferencesStore: ObservableObject {
    @Published private(set) var hiddenCards: Set<String> = []
    @Published private(set) var saving: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    private var owner: Int?
    private var generation = UUID()
    private var edited: Set<String> = []

    private struct Preferences: Decodable { let hiddenCards: [String] }

    func load(userID: Int?) async {
        guard owner != userID else { return }
        owner = userID
        let operation = UUID(); generation = operation
        hiddenCards = []; saving = []; errors = [:]; edited = []
        guard userID != nil else { return }
        do {
            let response: Preferences = try await APIClient.shared.request("/preferences/ui")
            guard generation == operation else { return }
            let persisted = Set(response.hiddenCards)
            hiddenCards = persisted.subtracting(edited).union(hiddenCards.intersection(edited))
        } catch {
            // A failed preferences read must never block the financial screens.
        }
    }

    func setHidden(_ hidden: Bool, cardID: String) async {
        guard owner != nil, !saving.contains(cardID) else { return }
        let operation = generation
        let previous = hiddenCards.contains(cardID)
        edited.insert(cardID); saving.insert(cardID); errors[cardID] = nil
        if hidden { hiddenCards.insert(cardID) } else { hiddenCards.remove(cardID) }
        do {
            try await APIClient.shared.perform("/preferences/ui/" + cardID, method: "PUT", body: ["hidden": hidden])
            guard generation == operation else { return }
            saving.remove(cardID)
        } catch {
            guard generation == operation else { return }
            if previous { hiddenCards.insert(cardID) } else { hiddenCards.remove(cardID) }
            saving.remove(cardID)
            errors[cardID] = "No se guardó el cambio. Revisa tu conexión e inténtalo de nuevo."
        }
    }
}
