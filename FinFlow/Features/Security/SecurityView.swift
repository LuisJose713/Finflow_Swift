import SwiftUI

/// Changes are authorized by the currently authenticated bearer token and
/// verified again with the account password by the Spring Boot API.
struct SecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var revokePassword = ""
    @State private var changing = false
    @State private var revoking = false
    @State private var showConfirmRevocation = false
    @State private var error: String?
    @State private var information: String?

    var body: some View {
        ScreenBackground {
            Form {
                Section {
                    Label("Tu sesión se valida contra el servidor.", systemImage: "lock.shield")
                        .font(.subheadline)
                    Text("Al cambiar tu contraseña o cerrar las sesiones, los tokens antiguos dejan de funcionar en todos tus dispositivos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Cambiar contraseña") {
                    SecureField("Contraseña actual", text: $currentPassword)
                        .textContentType(.password)
                    SecureField("Nueva contraseña · mínimo 12 caracteres", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirmar contraseña", text: $confirmPassword)
                        .textContentType(.newPassword)
                    Button {
                        Task { await changePassword() }
                    } label: {
                        HStack {
                            Spacer()
                            if changing { ProgressView() } else { Text("Cambiar contraseña") }
                            Spacer()
                        }
                    }
                    .disabled(changing || revoking || currentPassword.isEmpty ||
                              newPassword.count < 12 || confirmPassword != newPassword)
                }
                Section("Cerrar todas las sesiones") {
                    SecureField("Confirma tu contraseña actual", text: $revokePassword)
                        .textContentType(.password)
                    Button("Cerrar sesiones en todos los dispositivos", role: .destructive) {
                        showConfirmRevocation = true
                    }
                    .disabled(changing || revoking || revokePassword.isEmpty)
                    Text("Esta acción te desconectará también de este iPhone. Para volver a entrar deberás iniciar sesión.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { ErrorBanner(message: error) } }
                if let information {
                    Section {
                        Label(information, systemImage: "checkmark.shield")
                            .foregroundStyle(FinFlowTheme.mint)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Seguridad")
        .confirmationDialog("¿Cerrar todas las sesiones?", isPresented: $showConfirmRevocation,
                            titleVisibility: .visible) {
            Button("Invalidar sesiones", role: .destructive) {
                Task { await revokeSessions() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("También se invalidará el acceso desde la web.")
        }
    }

    private func changePassword() async {
        guard newPassword.count >= 12, newPassword == confirmPassword,
              !currentPassword.isEmpty else {
            error = "La contraseña debe tener al menos 12 caracteres y coincidir."
            return
        }
        changing = true
        defer { changing = false }
        error = nil
        do {
            let response: SecurityActionResponse = try await APIClient.shared.request(
                "/auth/change-password", method: "POST",
                body: PasswordChangeRequest(currentPassword: currentPassword,
                                            newPassword: newPassword,
                                            confirmPassword: confirmPassword))
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            information = "Contraseña actualizada."
            if response.logoutRequired { session.logout() }
        } catch { self.error = error.localizedDescription }
    }

    private func revokeSessions() async {
        guard !revokePassword.isEmpty else { return }
        revoking = true
        defer { revoking = false }
        error = nil
        do {
            let response: SecurityActionResponse = try await APIClient.shared.request(
                "/auth/revoke-sessions", method: "POST",
                body: PasswordConfirmation(password: revokePassword))
            revokePassword = ""
            information = "Sesiones invalidadas."
            if response.logoutRequired { session.logout() }
        } catch { self.error = error.localizedDescription }
    }
}
