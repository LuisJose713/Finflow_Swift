import SwiftUI
import Charts

/// Aggregated and anonymized operating metrics; never displays other users' financial records.
/// Backend always validates ROLE_ADMIN independently from this UI gate.
struct AdminView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var overview: AdminOverview?
    @State private var loading = true
    @State private var error: String?
    @State private var platformHealth: AdminPlatformHealth?
    @State private var healthLoading = false
    @State private var healthError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.user?.isAdmin != true {
                        EmptyState(icon: "lock.shield",
                                   title: "Acceso restringido",
                                   message: "Solo la cuenta administradora puede consultar este panel.")
                    } else {
                        PresentationCard(cardID: "admin.intro", eyebrow: "Administración", title: "Una plataforma bajo control.", detail: "Indicadores agregados y estado de los servicios de FinFlow.", symbol: "lock.shield")
                        if let error {
                            ErrorBanner(message: error)
                            Button { Task { await load() } } label: {
                                Text("Volver a intentar").foregroundStyle(FinFlowTheme.onAccent)
                            }
                                .buttonStyle(.borderedProminent)
                        }
                        if loading { ProgressView("Cargando indicadores…").padding(24) }
                        SectionCard(title: "Salud de la plataforma",
                                    subtitle: "Railway · PostgreSQL · Vercel · Asesor IA") {
                            VStack(alignment: .leading, spacing: 12) {
                                if healthLoading && platformHealth == nil {
                                    ProgressView("Comprobando servicios…")
                                }
                                if let healthError {
                                    Text(healthError)
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                                if let platformHealth {
                                    Label(platformHealth.overall == "UP"
                                          ? "Todos los servicios operativos"
                                          : "Algunos servicios requieren atención",
                                          systemImage: platformHealth.overall == "UP"
                                          ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(platformHealth.overall == "UP" ? .green : .orange)
                                    ForEach(platformHealth.services) { service in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: service.icon)
                                                .foregroundStyle(service.tint)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(service.name).font(.subheadline.weight(.semibold))
                                                Text(service.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                if let latency = service.latencyMs {
                                                    Text("\(latency) ms")
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 4)
                                            Text(service.statusLabel)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(service.tint)
                                                .multilineTextAlignment(.trailing)
                                        }
                                        .padding(.vertical, 8)
                                        .accessibilityElement(children: .combine)
                                        Divider()
                                    }
                                    Text("Última comprobación: \(platformHealth.checkedAt.prefix(19).replacingOccurrences(of: "T", with: " ")) UTC")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    Task { await loadHealth() }
                                } label: {
                                    Label("Actualizar servicios", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(healthLoading)
                            }
                        }

                        if let overview {
                            SectionCard(title: "Visión general",
                                        subtitle: "Actividad agregada sin datos financieros personales") {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    metric("Usuarios", value: overview.users, symbol: "person.2.fill")
                                    metric("Nuevos · 30 días", value: overview.newUsers30Days, symbol: "person.crop.circle.badge.plus")
                                    metric("Activos · 30 días", value: overview.activeUsers30Days, symbol: "person.crop.circle.badge.checkmark")
                                    metric("Movimientos", value: overview.transactions, symbol: "arrow.left.arrow.right")
                                    metric("Metas", value: overview.goals, symbol: "target")
                                    metric("Gastos previstos", value: overview.plannedExpenses, symbol: "calendar")
                                    metric("Categorías personales", value: overview.customCategories, symbol: "square.grid.2x2")
                                    metric("Categorías del sistema", value: overview.systemCategories, symbol: "lock")
                                }
                            }

                            SectionCard(title: "Actividad mensual", subtitle: "Últimos seis meses") {
                                if overview.monthlyActivity.isEmpty {
                                    Text("Todavía no hay actividad.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Chart {
                                        ForEach(overview.monthlyActivity) { item in
                                            BarMark(x: .value("Mes", item.month),
                                                    y: .value("Movimientos", item.transactions))
                                                .foregroundStyle(FinFlowTheme.accent)
                                        }
                                    }
                                    .frame(height: 210)
                                    .accessibilityLabel("Gráfico de movimientos mensuales")
                                }
                            }
                            SectionCard(title: "Operación", subtitle: "Eventos de los últimos 30 días") {
                                LabeledContent("Movimientos recientes", value: String(overview.transactions30Days))
                                LabeledContent("Movimientos de ingreso", value: String(overview.incomeTransactions))
                                LabeledContent("Movimientos de gasto", value: String(overview.expenseTransactions))
                                LabeledContent("Gastos pendientes", value: String(overview.pendingExpenses))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                if session.user?.isAdmin == true {
                    await load()
                    await loadHealth()
                }
            }
        }
        .navigationTitle("Administración")
        .task {
            guard session.user?.isAdmin == true else {
                loading = false
                healthLoading = false
                return
            }
            await load()
            await loadHealth()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                await loadHealth()
            }
        }
    }

    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(FinFlowTheme.accent)
            Text(value.formatted()).font(.title2.bold()).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadHealth() async {
        guard session.user?.isAdmin == true, !healthLoading else { return }
        healthLoading = true
        defer { healthLoading = false }
        do {
            let response: AdminPlatformHealth = try await APIClient.shared.request("/admin/monitor")
            platformHealth = response
            healthError = nil
        } catch {
            // Never retain stale green indicators when the monitor is unreachable.
            platformHealth = nil
            healthError = "No pudimos verificar los servicios: \(error.localizedDescription)"
        }
    }

    private func load() async {
        guard session.user?.isAdmin == true else { return }
        loading = true
        defer { loading = false }
        do {
            overview = try await APIClient.shared.request("/admin/overview")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AdminPlatformHealth: Decodable {
    let overall: String
    let checkedAt: String
    let services: [AdminPlatformService]
}

private struct AdminPlatformService: Decodable, Identifiable {
    let key: String
    let name: String
    let status: String
    let latencyMs: Int?
    let detail: String

    var id: String { key }

    var statusLabel: String {
        switch status {
        case "UP": return "Operativo"
        case "DOWN": return "No responde"
        case "NOT_CONFIGURED": return "Sin configurar"
        default: return "Con incidencias"
        }
    }

    var tint: Color {
        switch status {
        case "UP": return .green
        case "DOWN": return .red
        default: return .orange
        }
    }

    var icon: String {
        switch key {
        case "api": return "server.rack"
        case "database": return "externaldrive.fill"
        case "web": return "globe"
        case "ai": return "sparkles"
        default: return "heart.text.square"
        }
    }
}


struct AdminBillingView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var plans: [BillingPlan] = []
    @State private var promotions: [BillingPromotion] = []
    @State private var selectedPlan: BillingPlan?
    @State private var selectedPromotion: BillingPromotion?
    @State private var creatingPromotion = false
    @State private var showingGrant = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScreenBackground {
            if session.user?.isAdmin == true {
                Form {
                    Section {
                        PresentationCard(cardID: "admin-billing.intro", eyebrow: "Administración de planes",
                                         title: "Ofertas claras, control centralizado.",
                                         detail: "Gestiona precios, promociones y accesos desde tu cuenta administradora.", symbol: "tag")
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    if loading { Section { ProgressView("Consultando configuración…") } }
                    if let error { Section { ErrorBanner(message: error) } }
                    Section("Planes") {
                        ForEach(plans) { plan in
                            Button { selectedPlan = plan } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(plan.title).foregroundStyle(.primary)
                                        Text(plan.active ? "Activo" : "Inactivo").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(CurrencyFormatter.format(Double(plan.priceCop))).monospacedDigit().font(.subheadline)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    Section("Promociones") {
                        ForEach(promotions) { promotion in
                            Button { selectedPromotion = promotion } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(promotion.title).foregroundStyle(.primary)
                                    Text("\(promotion.code) · \(promotion.planCode)").font(.caption).foregroundStyle(.secondary)
                                    Text("\(promotion.redemptionCount) usos · " + (promotion.active ? "Activa" : "Inactiva"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                        Button { creatingPromotion = true } label: { Label("Crear promoción", systemImage: "plus") }
                    }
                    Section("Accesos") {
                        Button { showingGrant = true } label: { Label("Asignar acceso a un usuario", systemImage: "person.badge.key") }
                        Text("Cada cambio queda auditado en el servidor.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden).disabled(loading)
                .refreshable { await load() }
            } else {
                EmptyState(icon: "lock.shield", title: "Acceso restringido", message: "Esta sección requiere la cuenta administradora.")
            }
        }
        .navigationTitle("Planes y promociones")
        .task { await load() }
        .sheet(item: $selectedPlan) { plan in
            BillingPlanEditor(plan: plan) { input in
                let _: BillingPlan = try await APIClient.shared.request("/admin/billing/plans/" + plan.code, method: "PUT", body: input)
                await load()
            }
        }
        .sheet(item: $selectedPromotion) { promotion in
            BillingPromotionEditor(promotion: promotion) { input in
                let _: BillingPromotion = try await APIClient.shared.request("/admin/billing/promotions/" + promotion.code, method: "PUT", body: input)
                await load()
            }
        }
        .sheet(isPresented: $creatingPromotion) {
            BillingPromotionEditor(promotion: nil) { input in
                let _: BillingPromotion = try await APIClient.shared.request("/admin/billing/promotions", method: "POST", body: input)
                await load()
            }
        }
        .sheet(isPresented: $showingGrant) { BillingGrantEditor() }
    }

    @MainActor private func load() async {
        guard session.user?.isAdmin == true, !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            async let loadedPlans: [BillingPlan] = APIClient.shared.request("/admin/billing/plans")
            async let loadedPromotions: [BillingPromotion] = APIClient.shared.request("/admin/billing/promotions")
            (plans, promotions) = try await (loadedPlans, loadedPromotions)
        } catch { self.error = error.localizedDescription }
    }
}

private struct BillingPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let plan: BillingPlan
    let onSave: (BillingPlan) async throws -> Void
    @State private var title = ""
    @State private var detail = ""
    @State private var price = ""
    @State private var active = true
    @State private var order = 0
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan " + plan.code) {
                    TextField("Título", text: $title).onChange(of: title) { _, text in title = String(text.prefix(90)) }
                    TextField("Descripción", text: $detail, axis: .vertical)
                        .onChange(of: detail) { _, text in detail = String(text.prefix(240)) }
                    COPAmountField("Precio en COP", text: $price).disabled(plan.code == "FREE")
                    Toggle("Disponible", isOn: $active).disabled(plan.code == "FREE")
                    Stepper("Orden: \(order)", value: $order, in: 0...99)
                }
                if let error { Section { ErrorBanner(message: error) } }
            }
            .disabled(saving)
            .navigationTitle("Editar plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await save() } }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
            .onAppear { title = plan.title; detail = plan.description; price = String(plan.priceCop); active = plan.active; order = plan.sortOrder }
        }
    }

    @MainActor private func save() async {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, let amount = Double(price), amount.isFinite,
              amount.rounded() == amount, amount >= 0, amount <= 10_000_000,
              plan.code == "FREE" ? amount == 0 && active : amount >= 1000 else {
            error = "Revisa el título y el precio. Los planes Pro admiten entre $1.000,00 y $10.000.000,00, en pesos enteros."
            return
        }
        saving = true; error = nil
        defer { saving = false }
        do {
            let input = BillingPlan(code: plan.code, title: cleaned, description: detail.trimmingCharacters(in: .whitespacesAndNewlines), priceCop: Int(amount), active: active, sortOrder: order)
            try await onSave(input); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct BillingPromotionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let promotion: BillingPromotion?
    let onSave: (BillingPromotionInput) async throws -> Void
    @State private var code = ""
    @State private var title = ""
    @State private var planCode = "MONTHLY"
    @State private var discountType = "PERCENT"
    @State private var discount = "10"
    @State private var startsAt = Date()
    @State private var endsAt = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var maximum = ""
    @State private var active = true
    @State private var published = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Promoción") {
                    TextField("Código", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .disabled(promotion != nil)
                        .onChange(of: code) { _, text in code = String(text.uppercased().filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains($0) }.prefix(32)) }
                    TextField("Título", text: $title).onChange(of: title) { _, text in title = String(text.prefix(90)) }
                    Picker("Plan", selection: $planCode) {
                        Text("Mensual").tag("MONTHLY"); Text("Anual").tag("YEARLY"); Text("De por vida").tag("LIFETIME")
                    }
                    Picker("Descuento", selection: $discountType) {
                        Text("Porcentaje").tag("PERCENT"); Text("Valor fijo").tag("FIXED")
                    }
                    .onChange(of: discountType) { _, _ in discount = "" }
                    if discountType == "FIXED" { COPAmountField("Valor del descuento", text: $discount) }
                    else { TextField("Porcentaje (1–100)", text: $discount).keyboardType(.numberPad) }
                }
                Section("Vigencia y disponibilidad") {
                    DatePicker("Desde", selection: $startsAt)
                    DatePicker("Hasta", selection: $endsAt)
                    TextField("Límite de usos (opcional)", text: $maximum).keyboardType(.numberPad)
                    Toggle("Activa", isOn: $active)
                    Toggle("Visible en el catálogo", isOn: $published)
                }
                if let error { Section { ErrorBanner(message: error) } }
            }
            .disabled(saving)
            .navigationTitle(promotion == nil ? "Nueva promoción" : "Editar promoción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await save() } }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                if let promotion {
                    code = promotion.code; title = promotion.title; planCode = promotion.planCode
                    discountType = promotion.discountType; discount = String(promotion.discountValue)
                    startsAt = DateFormatters.parse(promotion.startsAt) ?? .now
                    endsAt = DateFormatters.parse(promotion.endsAt) ?? .now
                    maximum = promotion.maxRedemptions.map(String.init) ?? ""
                    active = promotion.active; published = promotion.published
                }
            }
        }
    }

    @MainActor private func save() async {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...32).contains(code.count), cleaned.count >= 2,
              let amount = Double(discount), amount.isFinite, amount.rounded() == amount,
              amount > 0, amount <= 10_000_000,
              discountType != "PERCENT" || amount <= 100,
              endsAt > startsAt,
              maximum.isEmpty || (Int(maximum).map { (1...100_000).contains($0) } ?? false) else {
            error = "Revisa el código, el descuento, las fechas y el límite de usos."
            return
        }
        saving = true; error = nil
        defer { saving = false }
        let dateFormatter = ISO8601DateFormatter()
        let input = BillingPromotionInput(code: code, title: cleaned, planCode: planCode, discountType: discountType,
                                          discountValue: Int(amount), startsAt: dateFormatter.string(from: startsAt),
                                          endsAt: dateFormatter.string(from: endsAt), maxRedemptions: Int(maximum), active: active, published: published)
        do { try await onSave(input); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct BillingGrantEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userID = ""
    @State private var planCode = "MONTHLY"
    @State private var reason = ""
    @State private var saving = false
    @State private var confirmed = false
    @State private var success = false
    @State private var error: String?
    private var valid: Bool {
        (Int(userID) ?? 0) > 0 && reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Usuario y acceso") {
                    TextField("ID del usuario", text: $userID).keyboardType(.numberPad)
                    Picker("Plan", selection: $planCode) {
                        Text("Mensual").tag("MONTHLY"); Text("Anual").tag("YEARLY"); Text("De por vida").tag("LIFETIME")
                    }
                    TextField("Motivo de la asignación", text: $reason, axis: .vertical)
                        .onChange(of: reason) { _, value in reason = String(value.prefix(240)) }
                    Button("Revisar asignación") { confirmed = true }.disabled(!valid || saving || success)
                }.disabled(saving || success)
                if let error { Section { ErrorBanner(message: error) } }
                if success { Section { Label("Acceso asignado y auditado.", systemImage: "checkmark.shield.fill").foregroundStyle(.green) } }
            }
            .navigationTitle("Asignar acceso").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(success ? "Listo" : "Cancelar") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .confirmationDialog("Asignar \(planCode) al usuario #\(userID)", isPresented: $confirmed, titleVisibility: .visible) {
                Button("Confirmar asignación") { Task { await grant() } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text(reason) }
        }
    }

    @MainActor private func grant() async {
        guard valid, let id = Int(userID), !saving else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            try await APIClient.shared.perform("/admin/billing/grants", method: "POST", body: BillingGrantInput(userId: id, planCode: planCode, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
            success = true
        } catch { self.error = error.localizedDescription }
    }
}
