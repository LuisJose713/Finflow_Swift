import SwiftUI

/// Identity changes require the current password. Email additionally needs
/// a server-issued code delivered to the new address before it is updated.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var name = ""
    @State private var email = ""
    @State private var savedName = ""
    @State private var savedEmail = ""
    @State private var currentPassword = ""
    @State private var verificationCode = ""
    @State private var awaitingEmailCode = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        ScreenBackground {
            Form {
                Section {
                    Label("Perfil personal", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("Para guardar un cambio necesitamos tu contraseña actual. Si cambias el correo, también verificaremos que tienes acceso a la nueva dirección.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Datos de tu cuenta") {
                    TextField("Nombre", text: $name)
                        .textContentType(.name)
                    TextField("Correo", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Contraseña actual", text: $currentPassword)
                        .textContentType(.password)
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() }
                            Text(emailHasChanged ? "Solicitar cambio de correo" : "Guardar perfil")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              email.trimmingCharacters(in: .whitespaces).isEmpty || currentPassword.isEmpty)
                }
                if awaitingEmailCode {
                    Section("Confirmar nuevo correo") {
                        Text("Enviamos un código de ocho cifras al nuevo correo. Caduca a los 15 minutos.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextField("Código de verificación", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("Confirmar correo") {
                            Task { await confirmEmail() }
                        }
                        .disabled(saving || verificationCode.count != 8 ||
                                  !verificationCode.allSatisfy({ $0.isNumber }))
                        Button("Cancelar cambio") {
                            awaitingEmailCode = false
                            verificationCode = ""
                            email = savedEmail
                        }
                    }
                }
                if let notice { Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.green) } }
                if let error { Section { ErrorBanner(message: error) } }
                Section {
                    Text("El cambio de correo no se activará hasta comprobar el código. El servidor cerrará las sesiones anteriores después de confirmar el cambio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Mi perfil")
        .task { await load() }
    }

    private var emailHasChanged: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != savedEmail.lowercased()
    }

    private func load() async {
        do {
            let user: AppUser = try await APIClient.shared.request("/auth/me")
            savedName = user.name
            savedEmail = user.email
            name = user.name
            email = user.email
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard !saving else { return }
        notice = nil
        error = nil
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard newName.count >= 2, newEmail.contains("@") else {
            error = "Verifica tu nombre y dirección de correo."
            return
        }
        if emailHasChanged && newName != savedName {
            error = "Guarda primero el nombre. Después verifica el nuevo correo."
            return
        }
        saving = true
        defer { saving = false }
        do {
            if emailHasChanged {
                let _: EmailChallengeResult = try await APIClient.shared.request(
                    "/auth/profile-email/request", method: "POST",
                    body: EmailChallengeInput(newEmail: newEmail, currentPassword: currentPassword))
                currentPassword = ""
                verificationCode = ""
                awaitingEmailCode = true
                notice = "Revisa tu nuevo correo para confirmar el cambio."
            } else {
                let result: ProfileUpdateResult = try await APIClient.shared.request(
                    "/auth/profile", method: "PUT",
                    body: ProfileUpdateInput(
                        name: newName, email: savedEmail,
                        currentPassword: currentPassword))
                currentPassword = ""
                notice = "Perfil actualizado."
                if result.logoutRequired { session.logout() }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func confirmEmail() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let result: EmailConfirmResult = try await APIClient.shared.request(
                "/auth/profile-email/confirm", method: "POST",
                body: EmailConfirmInput(code: verificationCode))
            if result.status == "VERIFIED" {
                awaitingEmailCode = false
                if result.logoutRequired == true { session.logout() }
            } else {
                error = "Código incorrecto. Intentos disponibles: \(result.attemptsRemaining ?? 0)."
            }
        } catch { self.error = error.localizedDescription }
    }
}
