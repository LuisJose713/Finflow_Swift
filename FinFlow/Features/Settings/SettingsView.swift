import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogout = false
    @AppStorage("finflow.appearance") private var appearance = "system"
    var body: some View {
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
                    Section("Acerca de") {
                        LabeledContent("Aplicación", value: "FinFlow iOS")
                        LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Ajustes")
            .confirmationDialog("¿Cerrar sesión?", isPresented: $showingLogout, titleVisibility: .visible) { Button("Cerrar sesión", role: .destructive) { session.logout() }; Button("Cancelar", role: .cancel) {} } message: { Text("Se eliminará la sesión guardada de este dispositivo.") }
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


struct PlansView: View {
    @State private var catalog: BillingCatalog?
    @State private var entitlement: BillingEntitlement?
    @State private var selection = ""
    @State private var coupon = ""
    @State private var quote: BillingOffer?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        ScreenBackground {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if loading { ProgressView("Consultando planes…") }
                    if let error { ErrorBanner(message: error) }
                    if let entitlement {
                        SectionCard(title: "Tu plan actual", subtitle: entitlement.pro ? "Beneficios Pro activos" : "Plan gratuito") {
                            Text(entitlement.planCode).font(.title2.bold())
                            if let until = entitlement.validUntil {
                                Text("Vigente hasta: " + String(until.prefix(10))).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(catalog?.offers ?? []) { offer in
                        SectionCard(title: offer.title, subtitle: offer.description) {
                            Text(CurrencyFormatter.format(Double(offer.priceCop)))
                                .font(.title.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6)
                            if offer.savingsPercent > 0 {
                                Label("Ahorra \(offer.savingsPercent)%", systemImage: "tag")
                                    .font(.footnote.weight(.medium)).foregroundStyle(FinFlowTheme.accent)
                            }
                            if let promotion = offer.promoTitle { Text(promotion).font(.footnote) }
                            Button("Consultar este plan") { selection = offer.code; quote = nil; coupon = "" }
                                .buttonStyle(.bordered).disabled(loading)
                        }
                    }
                    if !selection.isEmpty {
                        SectionCard(title: "Consultar oferta") {
                            TextField("Código promocional (opcional)", text: $coupon)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: coupon) { _, value in coupon = String(value.prefix(32)) }
                            Button("Consultar precio") { Task { await consult() } }.disabled(loading)
                            if let quote {
                                LabeledContent("Precio cotizado", value: CurrencyFormatter.format(Double(quote.priceCop)))
                                if let title = quote.promoTitle { Text(title).font(.footnote) }
                            }
                        }
                    }
                    Text("Los planes y promociones son informativos. El pago y la activación de suscripciones todavía no están disponibles.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 760).padding(16).frame(maxWidth: .infinity)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Planes FinFlow")
        .task { await load() }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { catalog = try await APIClient.shared.request("/billing/catalog") }
        catch { self.error = error.localizedDescription }
        do { entitlement = try await APIClient.shared.request("/billing/me") }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func consult() async {
        guard !loading else { return }
        loading = true; error = nil; quote = nil
        defer { loading = false }
        do {
            quote = try await APIClient.shared.request("/billing/quote", query: ["planCode": selection, "promoCode": coupon.trimmingCharacters(in: .whitespacesAndNewlines)])
        } catch { self.error = error.localizedDescription }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var type = ""
    @State private var month = 0
    @State private var year = 0
    @State private var search = ""
    @State private var working = false
    @State private var error: String?
    @State private var reportURL: URL?
    @State private var sharing = false
    @State private var operation = UUID()
    @State private var visible = false

    var body: some View {
        ScreenBackground {
            Form {
                Section("Filtros del informe") {
                    Picker("Movimientos", selection: $type) {
                        Text("Todos").tag("")
                        Text("Ingresos").tag("income")
                        Text("Gastos").tag("expense")
                    }
                    Picker("Mes", selection: $month) {
                        Text("Todos los meses").tag(0)
                        ForEach(1...12, id: \.self) { value in Text(Calendar.current.monthSymbols[value - 1]).tag(value) }
                    }
                    Picker("Año", selection: $year) {
                        Text("Todos los años").tag(0)
                        ForEach(Array((2000...max(2100, Calendar.current.component(.year, from: .now))).reversed()), id: \.self) { Text(String($0)).tag($0) }
                    }
                    TextField("Buscar por título", text: $search)
                        .onChange(of: search) { _, value in search = String(value.prefix(120)) }
                }
                Section {
                    Button { Task { await export("pdf") } } label: { Label("Compartir PDF", systemImage: "doc.richtext") }
                    Button { Task { await export("xlsx") } } label: { Label("Compartir Excel", systemImage: "tablecells") }
                    if working { ProgressView("Preparando informe…") }
                } footer: {
                    Text("Los informes usan los mismos datos y plantillas de FinFlow Web. El Excel es editable.")
                }
                .disabled(working || sharing)
                if let error { Section { ErrorBanner(message: error) } }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Reportes")
        .onAppear { visible = true }
        .onDisappear { visible = false; operation = UUID(); working = false; if !sharing { cleanup() } }
        .sheet(isPresented: $sharing, onDismiss: cleanup) {
            if let reportURL { ShareSheet(items: [reportURL]) }
        }
    }

    @MainActor private func export(_ kind: String) async {
        guard visible, !working, let owner = session.user?.id else { return }
        let current = UUID(); operation = current; working = true; error = nil
        defer { if operation == current { working = false } }
        var query: [String: String] = [:]
        if !type.isEmpty { query["type"] = type }
        if month > 0 { query["month"] = String(month) }
        if year > 0 { query["year"] = String(year) }
        if !search.isEmpty { query["search"] = search }
        do {
            let data = try await APIClient.shared.download("/transactions/export/" + kind, query: query)
            guard visible, operation == current, session.user?.id == owner else { return }
            cleanup()
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("FinFlow_Movimientos_\(UUID().uuidString).\(kind)")
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            reportURL = file; sharing = true
        } catch {
            guard visible, operation == current, session.user?.id == owner else { return }
            self.error = error.localizedDescription
        }
    }
    private func cleanup() {
        if let reportURL { try? FileManager.default.removeItem(at: reportURL) }
        reportURL = nil
    }
}
