import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var policy: PrivacyPolicy?
    @State private var policyLoadError: String?
    @State private var showingPrivacyReview = false
    @State private var acceptedNecessaryTreatment = false
    @State private var acceptsMarketing = false
    @State private var reviewedCurrentPolicy = false

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 45)
                    FinFlowBrandSymbol()
                    VStack(spacing: 6) { FinFlowBrandWordmark(); Text("Tus finanzas, bajo control").foregroundStyle(FinFlowTheme.secondaryText) }
                    VStack(spacing: 15) {
                        if isRegistering { field("Nombre completo", text: $name, icon: "person") }
                        field("Correo electrónico", text: $email, icon: "envelope", contentType: .emailAddress)
                        PasswordInput("Contraseña", text: $password, isNew: isRegistering)
                        if isRegistering { PasswordInput("Confirmar contraseña", text: $confirmPassword, isNew: true) }
                        if isRegistering {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Tratamiento de datos personales", systemImage: "lock.shield")
                                    .font(.subheadline.weight(.semibold))
                                Text("SoftDevCode S.A.S. · NIT 901796447 · FinFlow / AEVQOR")
                                    .font(.caption).foregroundStyle(.secondary)
                                if policy?.ready == true {
                                    Text("Antes de crear tu cuenta debes leer la política vigente y decidir sobre las promociones por separado.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    if reviewedCurrentPolicy {
                                        Label("Autorización revisada", systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(.green)
                                    }
                                } else {
                                    Text("La política legal formal está en revisión. Tras crear tu cuenta te mostraremos una ventana informativa; todavía no se registran autorizaciones.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Button(policy?.ready == true ? "Leer política y autorizar" : "Consultar tratamiento de datos") {
                                    showingPrivacyReview = true
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(FinFlowTheme.accent)
                                if let policyLoadError {
                                    Text(policyLoadError).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                        }
                        if let error = session.errorMessage { ErrorBanner(message: error) }
                        PrimaryButton(title: isRegistering ? "Crear cuenta" : "Iniciar sesión", isLoading: session.isLoading) { Task { await submit() } }
                        Button(isRegistering ? "Ya tengo cuenta · Iniciar sesión" : "¿No tienes cuenta? Regístrate") { withAnimation { isRegistering.toggle(); session.errorMessage = nil } }.font(.subheadline).foregroundStyle(FinFlowTheme.accent)
                    }
                    .padding(20).background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    Text("Seguro · Simple · Para ti").font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                }.padding(22).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
        }
        .task { await loadPrivacyPolicy() }
        .sheet(isPresented: $showingPrivacyReview) {
            RegistrationPrivacySheet(
                policy: policy,
                accepted: $acceptedNecessaryTreatment,
                marketing: $acceptsMarketing
            ) {
                if policy?.ready == true {
                    reviewedCurrentPolicy = acceptedNecessaryTreatment
                }
                showingPrivacyReview = false
            }
            .interactiveDismissDisabled()
        }
    }

    private func loadPrivacyPolicy() async {
        do {
            let latest: PrivacyPolicy = try await APIClient.shared.request("/privacy/policy")
            if policy?.version != latest.version {
                acceptedNecessaryTreatment = false
                acceptsMarketing = false
                reviewedCurrentPolicy = false
            }
            policy = latest
            policyLoadError = nil
        } catch {
            policy = nil
            policyLoadError = "No se pudo consultar la política. La autorización legal no está disponible."
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, icon: String, contentType: UITextContentType? = nil) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(FinFlowTheme.secondaryText); TextField(placeholder, text: text).textContentType(contentType).keyboardType(contentType == .emailAddress ? .emailAddress : .default).textInputAutocapitalization(contentType == .emailAddress ? .never : .words).autocorrectionDisabled() }
            .padding(15).background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
    }
    private func submit() async {
        guard password.utf8.count <= 72 else { session.errorMessage = "La contraseña supera el máximo de 72 bytes. Los acentos y emojis pueden ocupar más de un byte."; return }
        guard email.contains("@"), password.count >= 8 else { session.errorMessage = "Ingresa un correo válido y una contraseña de al menos 8 caracteres."; return }
        if isRegistering {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { session.errorMessage = "Escribe tu nombre."; return }
            guard password == confirmPassword else { session.errorMessage = "Las contraseñas no coinciden."; return }
            if let policy, policy.ready, (!acceptedNecessaryTreatment || !reviewedCurrentPolicy) {
                session.errorMessage = "Lee y acepta expresamente la política vigente para registrarte."
                showingPrivacyReview = true
                return
            }
            await session.register(
                name: name, email: email, password: password,
                privacyAccepted: policy?.ready == true ? true : nil,
                privacyVersion: policy?.ready == true ? policy?.version : nil,
                marketingConsent: policy?.ready == true ? acceptsMarketing : nil
            )
        } else { await session.login(email: email, password: password) }
    }
}

private struct RegistrationPrivacySheet: View {
    let policy: PrivacyPolicy?
    @Binding var accepted: Bool
    @Binding var marketing: Bool
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tratamiento de datos personales").font(.title2.bold())
                    PrivacyPolicyDocument(policy: policy)
                    if policy?.ready == true {
                        Toggle("Autorizo expresamente el tratamiento necesario para usar FinFlow.", isOn: $accepted)
                        Toggle("Opcional: deseo recibir promociones y novedades.", isOn: $marketing)
                    } else {
                        Text("Este documento aún está en revisión. Cerrar esta ventana no registra tu consentimiento.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: done) {
                    Text(policy?.ready == true ? "Confirmar mi decisión" : "Entendido")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FinFlowTheme.accent)
                .disabled(policy?.ready == true && !accepted)
                .padding()
                .frame(maxWidth: 650)
                .background(.regularMaterial)
            }
        }
    }
}
