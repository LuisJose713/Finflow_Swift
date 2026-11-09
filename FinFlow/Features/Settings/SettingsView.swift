import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogout = false
    @AppStorage("finflow.appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            ScreenBackground {
                Form {
                    Section("Cuenta") {
                        LabeledContent("Nombre", value: session.user?.name ?? "Usuario")
                        LabeledContent("Correo", value: session.user?.email ?? "")
                        Button("Cerrar sesión", role: .destructive) { showingLogout = true }
                    }
                    Section("Privacidad y protección") {
                        NavigationLink {
                            SecurityView()
                        } label: {
                            Label("Contraseña y sesiones", systemImage: "lock.shield")
                        }
                        NavigationLink {
                            PrivacyRightsCenterView()
                        } label: {
                            Label("Mis datos, autorizaciones y solicitudes", systemImage: "hand.raised")
                        }
                    }
                    Section("Apariencia") {
                        Picker("Tema", selection: $appearance) {
                            Text("Del sistema").tag("system")
                            Text("Claro").tag("light")
                            Text("Oscuro").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Conexión segura") {
                        Label("Servidor oficial de FinFlow", systemImage: "lock.shield")
                        Text(APIClient.shared.baseURL).font(.caption).foregroundStyle(.secondary)
                        Text("Por seguridad, la app no envía tus credenciales a servidores personalizados.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Acerca de") {
                        LabeledContent("Aplicación", value: "FinFlow iOS")
                        LabeledContent("Versión", value: "1.0.0")
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Ajustes")
            .confirmationDialog("¿Cerrar sesión?", isPresented: $showingLogout, titleVisibility: .visible) { Button("Cerrar sesión", role: .destructive) { session.logout() }; Button("Cancelar", role: .cancel) {} } message: { Text("Se eliminará la sesión guardada de este dispositivo.") }
        }
    }
}


/// Available in Ajustes, not in the finance tab navigation.
/// Rights requests are registered for human handling; nothing is erased
/// automatically and dismissing information never creates legal consent.
struct PrivacyRightsCenterView: View {
    @State private var policy: PrivacyPolicy?
    @State private var consentStatus: PrivacyStatus?
    @State private var consentHistory: [PrivacyConsentRecord] = []
    @State private var requests: [PrivacyRightRecord] = []
    @State private var marketing = false
    @State private var requestType = "ACCESS"
    @State private var details = ""
    @State private var isWorking = false
    @State private var feedback: String?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Tratamiento de datos personales") {
                PrivacyPolicyDocument(policy: policy)
                if policy?.ready != true {
                    Text("La política formal todavía no está publicada. Esta información no equivale a consentimiento.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Mi autorización") {
                if let consentStatus, consentStatus.accepted {
                    LabeledContent("Versión", value: consentStatus.version)
                    Toggle("Recibir promociones opcionales", isOn: $marketing)
                    Button("Guardar preferencia") {
                        Task { await updateMarketing() }
                    }
                    .disabled(isWorking)
                } else {
                    Text("No hay una autorización de la versión vigente confirmada por el servidor.")
                        .foregroundStyle(.secondary)
                }
                if !consentHistory.isEmpty {
                    ForEach(consentHistory) { receipt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Versión \(receipt.policyVersion)")
                            Text("Registrada: \(receipt.acceptedAt)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(receipt.marketingOptIn ? "Promociones autorizadas al registrar" : "Sin autorización comercial al registrar")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Ejercer mis derechos") {
                Text("Puedes solicitar acceso, corrección, eliminación o revocatoria. Cada caso requiere revisión.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Tipo de solicitud", selection: $requestType) {
                    Text("Consultar datos").tag("ACCESS")
                    Text("Corregir información").tag("RECTIFY")
                    Text("Solicitar supresión").tag("DELETE")
                    Text("Solicitar revocatoria").tag("REVOKE")
                }
                TextField("Descripción de tu solicitud", text: $details, axis: .vertical)
                    .lineLimit(2...5)
                    .onChange(of: details) { _, newValue in
                        if newValue.count > 500 { details = String(newValue.prefix(500)) }
                    }
                Text("No incluyas contraseñas ni datos bancarios.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Registrar solicitud") {
                    Task { await submitRightsRequest() }
                }
                .disabled(isWorking)
            }

            if let feedback {
                Section {
                    Label(feedback, systemImage: "checkmark.shield")
                        .foregroundStyle(.green)
                }
            }
            if let errorText {
                Section { ErrorBanner(message: errorText) }
            }

            if !requests.isEmpty {
                Section("Solicitudes anteriores") {
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(request.id) · \(request.requestType)")
                            Text("Estado: \(request.status)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let created = request.createdAt {
                                Text(created).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mis datos")
        .task { await refresh() }
    }

    @MainActor private func refresh() async {
        do {
            let response: PrivacyPolicy = try await APIClient.shared.request("/privacy/policy")
            policy = response
        } catch {
            errorText = "No pudimos cargar el documento de privacidad."
        }
        do {
            let status: PrivacyStatus = try await APIClient.shared.request("/privacy/status")
            consentStatus = status
            marketing = status.marketingConsent
        } catch {
            errorText = "No pudimos verificar el estado de tus autorizaciones."
        }
        if let receipt: PrivacyReceipt = try? await APIClient.shared.request("/privacy/receipt") {
            consentHistory = receipt.consents
        }
        if let rows: [PrivacyRightRecord] = try? await APIClient.shared.request("/privacy/rights-requests") {
            requests = rows
        }
    }

    @MainActor private func updateMarketing() async {
        guard consentStatus?.accepted == true else { return }
        isWorking = true
        errorText = nil
        feedback = nil
        defer { isWorking = false }
        do {
            let saved: PrivacyMarketingResponse = try await APIClient.shared.request(
                "/privacy/marketing", method: "POST",
                body: PrivacyMarketingInput(marketingConsent: marketing))
            guard saved.saved else { throw APIError.invalidResponse }
            feedback = "Tu preferencia comercial quedó registrada."
            await refresh()
        } catch {
            errorText = "No se guardó tu decisión: \(error.localizedDescription)"
        }
    }

    @MainActor private func submitRightsRequest() async {
        isWorking = true
        errorText = nil
        feedback = nil
        defer { isWorking = false }
        do {
            let saved: PrivacyRightsResponse = try await APIClient.shared.request(
                "/privacy/rights-request", method: "POST",
                body: PrivacyRightsInput(type: requestType,
                                         description: String(details.prefix(500))))
            feedback = "Solicitud #\(saved.id) registrada para revisión."
            details = ""
            await refresh()
        } catch {
            errorText = "No se pudo registrar la solicitud: \(error.localizedDescription)"
        }
    }
}
