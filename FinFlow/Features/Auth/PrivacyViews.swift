import SwiftUI

/// The responsible party is supplied by the backend. Legal text requires
/// review before public release; displaying it is not a compliance guarantee.
struct PrivacyPolicyDocument: View {
    let policy: PrivacyPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tratamiento de datos personales").font(.headline)
            Text("Versión \(policy.version) · Vigente desde \(policy.effectiveDate)")
                .font(.caption).foregroundStyle(.secondary)
            item("Responsable", "\(policy.controllerName)\nCorreo: \(policy.contactEmail)\nDirección: \(policy.contactAddress)\nTeléfono: \(policy.contactPhone)")
            item("Datos que registras", "Datos de cuenta y credenciales protegidas, movimientos financieros registrados voluntariamente, metas, presupuestos, preferencias y registros técnicos de seguridad.")
            item("Finalidades", "Prestar FinFlow, autenticarte, administrar tus finanzas, calcular presupuestos, mantener la seguridad del servicio y atender las obligaciones legales aplicables.")
            item("Comunicaciones comerciales", "Recibir ofertas es opcional. No necesitas aceptar publicidad para utilizar FinFlow Gratis.")
            item("Proveedores y conservación", "FinFlow utiliza proveedores de infraestructura y alojamiento. La conservación y cualquier tratamiento internacional deben cumplir la normativa aplicable.")
            item("Tus derechos", "Puedes consultar, actualizar, rectificar, solicitar la supresión de tus datos y revocar la autorización cuando proceda, conforme a la Ley 1581 de 2012.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func item(_ heading: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.subheadline).bold()
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct PrivacyConsentGate: View {
    @EnvironmentObject private var session: SessionStore
    @State private var accepted = false
    @State private var marketing = false
    @State private var processing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenBackground {
                Form {
                    Section {
                        Label("Tus datos son tuyos", systemImage: "lock.shield")
                            .font(.headline)
                        Text("Necesitamos registrar tu decisión sobre la política vigente. No se acepta automáticamente por iniciar sesión.")
                            .font(.subheadline)
                    }
                    if let policy = session.privacyPolicy, policy.ready {
                        Section("Lee la política") {
                            DisclosureGroup("Mostrar documento") {
                                PrivacyPolicyDocument(policy: policy)
                                    .padding(.vertical, 8)
                            }
                            if let url = URL(string: "mailto:" + policy.contactEmail) {
                                Link("Consultar derechos por correo", destination: url)
                            }
                        }
                        Section("Autorizaciones") {
                            Toggle("Acepto el tratamiento de datos necesario para usar FinFlow.", isOn: $accepted)
                            Toggle("Opcional: quiero recibir promociones por correo.", isOn: $marketing)
                        }
                        Section {
                            Button {
                                Task { await saveConsent(policy.version) }
                            } label: {
                                HStack {
                                    Spacer()
                                    if processing { ProgressView() }
                                    Text("Aceptar y continuar").fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .disabled(!accepted || processing)
                            Button("No acepto · Cerrar sesión", role: .destructive) { session.logout() }
                        }
                    } else {
                        Section {
                            ErrorBanner(message: "La política legal todavía no está configurada. El acceso permanece protegido.")
                            Button("Cerrar sesión") { session.logout() }
                        }
                    }
                    if let error { Section { ErrorBanner(message: error) } }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Privacidad")
        }
    }

    private func saveConsent(_ version: String) async {
        processing = true
        defer { processing = false }
        error = nil
        await session.acceptPrivacy(policyVersion: version, marketing: marketing)
        if session.privacyAccess != .accepted {
            error = session.privacyError ?? "No se pudo registrar tu decisión."
        }
    }
}

struct PrivacyUnavailableView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        ScreenBackground {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(FinFlowTheme.accent)
                Text("Protegemos tu privacidad").font(.title2).bold()
                Text(session.privacyError ?? "No pudimos validar la política vigente. Inténtalo nuevamente.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                PrimaryButton(title: "Reintentar") {
                    Task { await session.refreshPrivacyAccess() }
                }
                Button("Cerrar sesión", role: .destructive) { session.logout() }
            }
            .padding(24)
            .frame(maxWidth: 450)
        }
    }
}

struct PrivacyRightsView: View {
    @State private var requestType = "ACCESS"
    @State private var details = ""
    @State private var processing = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        ScreenBackground {
            Form {
                Section("Ejercer tus derechos") {
                    Text("Consulta, actualiza o solicita la eliminación o revocación de datos, sin aceptar publicidad.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Solicitud", selection: $requestType) {
                        Text("Consultar datos").tag("ACCESS")
                        Text("Rectificar datos").tag("RECTIFY")
                        Text("Eliminar datos").tag("DELETE")
                        Text("Revocar autorización").tag("REVOKE")
                    }
                    TextField("Detalle", text: $details, axis: .vertical).lineLimit(3...6)
                    Button("Enviar solicitud") { Task { await submit() } }.disabled(processing)
                }
                if let message {
                    Section { Label(message, systemImage: "checkmark.seal").foregroundStyle(.green) }
                }
                if let error { Section { ErrorBanner(message: error) } }
                Section {
                    Text("La solicitud queda registrada para revisión. Su envío no elimina automáticamente tu información.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Tus derechos")
    }

    private func submit() async {
        processing = true
        defer { processing = false }
        error = nil
        do {
            let result: PrivacyRightsResult = try await APIClient.shared.request(
                "/privacy/rights-request", method: "POST",
                body: PrivacyRightsInput(type: requestType, description: String(details.prefix(500))))
            message = result.message
            details = ""
        } catch { self.error = error.localizedDescription }
    }
}
