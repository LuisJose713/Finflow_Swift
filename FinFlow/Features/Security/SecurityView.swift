import SwiftUI

/// Changes are authorized by the currently authenticated bearer token and
/// verified again with the account password by the Spring Boot API.
struct SecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appLock: AppLockStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var revokePassword = ""
    @State private var deletePassword = ""
    @State private var deletePhrase = ""
    @State private var deleting = false
    @State private var showConfirmDeletion = false
    @State private var changing = false
    @State private var revoking = false
    @State private var showConfirmRevocation = false
    @State private var error: String?
    @State private var information: String?

    var body: some View {
        ScreenBackground {
            Form {
                Section {
                    PresentationCard(cardID: "security.intro", eyebrow: "Protección de cuenta", title: "Tu información, bajo tu control.", detail: "Gestiona tu contraseña y las sesiones activas de tu cuenta.", symbol: "lock.shield")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section("Acceso al dispositivo") {
                    Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { enabled in
                        Task { await appLock.setEnabled(enabled) }
                    })) {
                        Label("Proteger con \(appLock.methodName)", systemImage: appLock.symbol)
                    }
                    .disabled(!appLock.isAvailable || appLock.isAuthenticating)
                    .accessibilityIdentifier("security.biometricToggle")
                    Text(appLock.isAvailable
                         ? "Se solicita al abrir FinFlow y cada vez que vuelves desde otra app. Si hace falta, iOS permite usar el código del dispositivo."
                         : "Configura un código y Face ID o Touch ID en los ajustes del dispositivo para proteger tu sesión.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if appLock.isEnabled && appLock.isAvailable {
                        Button("Bloquear FinFlow ahora") { appLock.lockNow() }
                            .accessibilityIdentifier("security.lockNow")
                    }
                    if let message = appLock.error { ErrorBanner(message: message) }
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
                    .disabled(changing || revoking || deleting || currentPassword.isEmpty ||
                              newPassword.count < 12 || newPassword.utf8.count > 72 ||
                              currentPassword.utf8.count > 72 || confirmPassword != newPassword)
                }
                Section("Cerrar todas las sesiones") {
                    SecureField("Confirma tu contraseña actual", text: $revokePassword)
                        .textContentType(.password)
                    Button("Cerrar sesiones en todos los dispositivos", role: .destructive) {
                        showConfirmRevocation = true
                    }
                    .disabled(changing || revoking || deleting || revokePassword.isEmpty || revokePassword.utf8.count > 72)
                    Text("Esta acción te desconectará también de este iPhone. Para volver a entrar deberás iniciar sesión.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Eliminar mi cuenta") {
                    Text("Borraremos tu perfil, movimientos, billeteras, presupuestos y metas, y cerraremos todas tus sesiones. Esta acción no se puede deshacer.")
                        .font(.footnote).foregroundStyle(.secondary)
                    SecureField("Contraseña actual", text: $deletePassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("security.deletePassword")
                    TextField("Escribe ELIMINAR", text: $deletePhrase)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("security.deleteConfirmation")
                    Button("Eliminar mi cuenta definitivamente", role: .destructive) {
                        showConfirmDeletion = true
                    }
                    .disabled(changing || revoking || deleting || deletePassword.isEmpty ||
                              deletePhrase != "ELIMINAR" ||
                              deletePassword.utf8.count > 72)
                    Text("Tu contraseña se verifica en el servidor antes de eliminar los datos.")
                        .font(.caption2).foregroundStyle(.secondary)
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
            .scrollDismissesKeyboard(.interactively)
            .modifier(FinFlowKeyboardDismiss())
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
        .confirmationDialog("¿Eliminar tu cuenta definitivamente?",
                            isPresented: $showConfirmDeletion,
                            titleVisibility: .visible) {
            Button("Sí, eliminar cuenta", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán permanentemente tus datos financieros de FinFlow y se cerrarán tus sesiones.")
        }
    }

    private func deleteAccount() async {
        guard !deletePassword.isEmpty, deletePassword.utf8.count <= 72,
              deletePhrase == "ELIMINAR", !deleting, !changing, !revoking else { return }
        deleting = true
        defer { deleting = false }
        error = nil
        do {
            try await APIClient.shared.perform(
                "/auth/account", method: "DELETE",
                body: PasswordConfirmation(password: deletePassword))
            deletePassword = ""
            deletePhrase = ""
            session.logout()
        } catch {
            self.error = "No pudimos confirmar la eliminación. Comprueba tu cuenta antes de reintentar."
        }
    }

    private func changePassword() async {
        guard newPassword.count >= 12, newPassword == confirmPassword,
              newPassword.utf8.count <= 72, currentPassword.utf8.count <= 72,
              !currentPassword.isEmpty, !changing, !revoking, !deleting else {
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
        guard !revokePassword.isEmpty, revokePassword.utf8.count <= 72,
              !changing, !revoking, !deleting else { return }
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
