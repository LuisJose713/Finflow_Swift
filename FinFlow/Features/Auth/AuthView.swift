import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 45)
                    ZStack { RoundedRectangle(cornerRadius: 24).fill(FinFlowTheme.accent.opacity(0.18)).frame(width: 86, height: 86); Image(systemName: "chart.pie.fill").font(.system(size: 38)).foregroundStyle(FinFlowTheme.accent) }
                    VStack(spacing: 6) { Text("FinFlow").font(.system(size: 34, weight: .bold, design: .rounded)); Text("Tus finanzas, bajo control").foregroundStyle(FinFlowTheme.secondaryText) }
                    VStack(spacing: 15) {
                        if isRegistering { field("Nombre completo", text: $name, icon: "person") }
                        field("Correo electrónico", text: $email, icon: "envelope", contentType: .emailAddress)
                        SecureField("Contraseña", text: $password).textContentType(isRegistering ? .newPassword : .password).textInputAutocapitalization(.never).padding(15).background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                        if isRegistering { SecureField("Confirmar contraseña", text: $confirmPassword).textContentType(.newPassword).padding(15).background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13)) }
                        if let error = session.errorMessage { ErrorBanner(message: error) }
                        PrimaryButton(title: isRegistering ? "Crear cuenta" : "Iniciar sesión", isLoading: session.isLoading) { Task { await submit() } }
                        Button(isRegistering ? "Ya tengo cuenta · Iniciar sesión" : "¿No tienes cuenta? Regístrate") { withAnimation { isRegistering.toggle(); session.errorMessage = nil } }.font(.subheadline).foregroundStyle(FinFlowTheme.accent)
                    }
                    .padding(20).background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    Text("Seguro · Simple · Para ti").font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                }.padding(22).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
        }
    }
    private func field(_ placeholder: String, text: Binding<String>, icon: String, contentType: UITextContentType? = nil) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(FinFlowTheme.secondaryText); TextField(placeholder, text: text).textContentType(contentType).keyboardType(contentType == .emailAddress ? .emailAddress : .default).textInputAutocapitalization(contentType == .emailAddress ? .never : .words).autocorrectionDisabled() }
            .padding(15).background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
    }
    private func submit() async {
        guard email.contains("@"), password.count >= 6 else { session.errorMessage = "Ingresa un correo válido y una contraseña de al menos 6 caracteres."; return }
        if isRegistering {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { session.errorMessage = "Escribe tu nombre."; return }
            guard password == confirmPassword else { session.errorMessage = "Las contraseñas no coinciden."; return }
            await session.register(name: name, email: email, password: password)
        } else { await session.login(email: email, password: password) }
    }
}
