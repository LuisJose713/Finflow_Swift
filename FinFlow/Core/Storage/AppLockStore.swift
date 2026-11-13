import Foundation
import Combine
import LocalAuthentication

@MainActor
protocol LocalAuthenticationProviding: AnyObject {
    var isAvailable: Bool { get }
    var name: String { get }
    var symbol: String { get }
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}

/// The system owns biometric data. FinFlow only receives success or failure.
@MainActor
final class DeviceAuthenticator: LocalAuthenticationProviding {
    private var context: LAContext?

    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
    private var biometry: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    var name: String {
        switch biometry {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Código del dispositivo"
        }
    }
    var symbol: String {
        switch biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        context.localizedFallbackTitle = "Usar código"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        defer { if self.context === context { self.context = nil } }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    func cancel() { context?.invalidate(); context = nil }
}

/// A failed/cancelled prompt never grants access. Inactive transitions caused by
/// Face ID do not create a prompt loop; an actual background transition relocks.
@MainActor
final class AppLockStore: ObservableObject {
    @Published private(set) var isLocked = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isEnabled = true
    @Published private(set) var error: String?
    private let authenticator: any LocalAuthenticationProviding
    private let defaults: UserDefaults
    private var ownerID: Int?
    private var operation = UUID()
    private var attemptedAutomatically = false
    private var active = true
    private var protectionArmed = false

    init(authenticator: any LocalAuthenticationProviding = DeviceAuthenticator(), defaults: UserDefaults = .standard) {
        self.authenticator = authenticator
        self.defaults = defaults
    }

    var methodName: String { authenticator.name }
    var symbol: String { authenticator.symbol }
    var isAvailable: Bool { authenticator.isAvailable }
    private var preferenceKey: String { "finflow.localAuthentication.\(ownerID ?? 0)" }

    func prepare(ownerID: Int?) {
        guard self.ownerID != ownerID else { return }
        cancelAttempt()
        self.ownerID = ownerID
        attemptedAutomatically = false
        error = nil
        isEnabled = defaults.object(forKey: preferenceKey) as? Bool ?? true
        protectionArmed = ownerID != nil && isEnabled && isAvailable
        isLocked = protectionArmed
    }

    func becameInactive() { active = false }

    func enteredBackground() {
        active = false
        cancelAttempt()
        attemptedAutomatically = false
        if ownerID != nil && isEnabled {
            // Do not create an impossible lock on a device that never had a
            // passcode. Once protection was available, losing it fails closed.
            protectionArmed = protectionArmed || isAvailable
            isLocked = protectionArmed
        }
    }

    func becameActive() async {
        active = true
        if ownerID != nil && isEnabled && !protectionArmed && isAvailable {
            protectionArmed = true
            isLocked = true
        }
        await unlock(automatically: true)
    }

    func unlock(automatically: Bool = false) async {
        guard active, ownerID != nil, isLocked, !isAuthenticating else { return }
        if automatically {
            guard !attemptedAutomatically else { return }
            attemptedAutomatically = true
        }
        // A device without a passcode cannot offer local authentication.
        // If protection was already active, fail closed until the user signs out.
        guard isAvailable else {
            error = "Activa Face ID o un código en los ajustes del dispositivo, o vuelve a iniciar sesión."
            return
        }
        let current = UUID(); operation = current
        isAuthenticating = true; error = nil
        defer { if operation == current { isAuthenticating = false } }
        do {
            let approved = try await authenticator.authenticate(reason: "Desbloquea tus finanzas en FinFlow")
            guard operation == current, ownerID != nil else { return }
            if approved { isLocked = false }
            else { error = "No se confirmó tu identidad. Inténtalo de nuevo." }
        } catch {
            guard operation == current else { return }
            self.error = "FinFlow sigue bloqueado. Usa \(methodName) o el código del dispositivo para entrar."
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard ownerID != nil, !isAuthenticating, enabled != isEnabled else { return }
        guard isAvailable else { error = "Configura primero un código en los ajustes del dispositivo."; return }
        let current = UUID(); operation = current
        isAuthenticating = true; error = nil
        defer { if operation == current { isAuthenticating = false } }
        do {
            guard try await authenticator.authenticate(reason: "Confirma el cambio de protección de FinFlow"),
                  operation == current else { return }
            defaults.set(enabled, forKey: preferenceKey)
            isEnabled = enabled
            protectionArmed = enabled
        } catch {
            guard operation == current else { return }
            self.error = "No se cambió la protección. Confirma tu identidad para continuar."
        }
    }

    func lockNow() {
        guard ownerID != nil, isEnabled, isAvailable else { return }
        cancelAttempt()
        attemptedAutomatically = true
        protectionArmed = true
        isLocked = true
    }

    private func cancelAttempt() {
        operation = UUID()
        authenticator.cancel()
        isAuthenticating = false
    }
}
