import SwiftUI

/// Every mutation is authenticated and authorized by ROLE_ADMIN on Spring Boot.
/// Only price display, promotions and manual grants exist; no checkout.
struct AdminBillingView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var plans: [BillingPlan] = []
    @State private var promotions: [BillingPromotion] = []
    @State private var error: String?
    @State private var success: String?
    @State private var loading = true
    @State private var saving = false

    @State private var editingCode: String?
    @State private var promoCode = ""
    @State private var promoName = ""
    @State private var promoPlan = "MONTHLY"
    @State private var promoType = "PERCENT"
    @State private var promoValue = 20
    @State private var promoStarts = Date()
    @State private var promoEnds = Date().addingTimeInterval(86400 * 14)
    @State private var promoLimit = ""
    @State private var promoActive = true
    @State private var promoPublic = false

    @State private var grantUserID = ""
    @State private var grantPlan = "MONTHLY"
    @State private var grantReason = ""
    @State private var confirmGrant = false

    var body: some View {
        ScreenBackground {
            if session.user?.isAdmin != true {
                EmptyState(icon: "lock.shield", title: "Acceso restringido",
                           message: "Esta función requiere permisos administrativos del servidor.")
            } else {
                Form {
                    Section {
                        Text("Configura precios y promociones desde iOS. Las operaciones son validadas y auditadas por Spring Boot.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Label("Los cobros reales aún están deshabilitados.", systemImage: "creditcard.trianglebadge.exclamationmark")
                            .font(.caption)
                    }
                    if loading { Section { ProgressView("Consultando catálogo…") } }
                    if let error { Section { ErrorBanner(message: error) } }
                    if let success {
                        Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(.green) }
                    }
                    Section("Planes (COP)") {
                        ForEach($plans) { $plan in
                            DisclosureGroup(plan.title) {
                                TextField("Nombre", text: $plan.title)
                                TextField("Descripción", text: $plan.description, axis: .vertical)
                                    .lineLimit(2...3)
                                TextField("Precio en pesos", value: $plan.priceCop, format: .number)
                                    .keyboardType(.numberPad)
                                    .disabled(plan.code == "FREE")
                                Toggle("Disponible", isOn: $plan.active)
                                    .disabled(plan.code == "FREE")
                                Button("Guardar \(plan.code)") {
                                    let copy = plan
                                    Task { await savePlan(copy) }
                                }
                                .disabled(saving)
                            }
                        }
                    }
                    Section(editingCode == nil ? "Nueva promoción" : "Editar promoción") {
                        TextField("Código (4 a 32 caracteres)", text: $promoCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .disabled(editingCode != nil)
                        TextField("Título público", text: $promoName)
                        Picker("Plan", selection: $promoPlan) {
                            Text("Pro mensual").tag("MONTHLY")
                            Text("Pro anual").tag("YEARLY")
                            Text("Pro de por vida").tag("LIFETIME")
                        }
                        Picker("Tipo de descuento", selection: $promoType) {
                            Text("Porcentaje").tag("PERCENT")
                            Text("Valor fijo COP").tag("FIXED")
                        }
                        TextField("Descuento", value: $promoValue, format: .number)
                            .keyboardType(.numberPad)
                        DatePicker("Empieza", selection: $promoStarts)
                        DatePicker("Finaliza", selection: $promoEnds)
                        TextField("Máximo de usos (opcional)", text: $promoLimit)
                            .keyboardType(.numberPad)
                        Toggle("Activa", isOn: $promoActive)
                        Toggle("Mostrar públicamente", isOn: $promoPublic)
                        Button(editingCode == nil ? "Crear promoción" : "Guardar promoción") {
                            Task { await savePromotion() }
                        }
                        .disabled(saving)
                        if editingCode != nil {
                            Button("Cancelar edición") { resetPromotion() }
                        }
                        Text("Los límites de usos no se descuentan hasta habilitar y verificar pagos. La creación de una campaña no activa Pro.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Promociones registradas") {
                        if promotions.isEmpty { Text("No hay promociones todavía.").foregroundStyle(.secondary) }
                        ForEach(promotions) { promo in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(promo.title).font(.headline)
                                Text("\(promo.code) · \(promo.planCode)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(promo.discountType == "PERCENT" ?
                                     "\(promo.discountValue)% de descuento" :
                                     BillingFormatting.cop(promo.discountValue) + " de descuento")
                                    .font(.footnote)
                                Text(promo.active ? "Activa" : "Pausada")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Editar") { edit(promo) }
                                    Spacer()
                                    Button(promo.active ? "Pausar" : "Reactivar") {
                                        Task { await togglePromotion(promo) }
                                    }
                                    .disabled(saving)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    Section("Conceder Pro manualmente") {
                        Text("Concede una cortesía registrada en la auditoría. No equivale a un pago.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("ID del usuario", text: $grantUserID).keyboardType(.numberPad)
                        Picker("Duración", selection: $grantPlan) {
                            Text("1 mes").tag("MONTHLY")
                            Text("1 año").tag("YEARLY")
                            Text("De por vida").tag("LIFETIME")
                        }
                        TextField("Motivo (mínimo 8 caracteres)", text: $grantReason, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Conceder acceso") { confirmGrant = true }
                            .disabled(saving || Int(grantUserID) == nil ||
                                      grantReason.trimmingCharacters(in: .whitespaces).count < 8)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Administrar Pro")
        .task { if session.user?.isAdmin == true { await load() } }
        .confirmationDialog("¿Asignar Pro sin un cobro?",
                            isPresented: $confirmGrant, titleVisibility: .visible) {
            Button("Confirmar asignación") { Task { await grant() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La operación quedará registrada en el historial de auditoría.")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            let latestPlans: [BillingPlan] = try await APIClient.shared.request("/admin/billing/plans")
            let latestPromotions: [BillingPromotion] = try await APIClient.shared.request("/admin/billing/promotions")
            plans = latestPlans
            promotions = latestPromotions
        } catch { self.error = error.localizedDescription }
    }

    private func savePlan(_ plan: BillingPlan) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let _: BillingPlan = try await APIClient.shared.request(
                "/admin/billing/plans/\(plan.code)", method: "PUT", body: plan)
            success = "Plan actualizado."
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func draft(active: Bool? = nil) -> BillingPromotionInput {
        BillingPromotionInput(
            code: promoCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            title: promoName.trimmingCharacters(in: .whitespacesAndNewlines),
            planCode: promoPlan,
            discountType: promoType,
            discountValue: promoValue,
            startsAt: BillingFormatting.isoUTC(promoStarts),
            endsAt: BillingFormatting.isoUTC(promoEnds),
            maxRedemptions: Int(promoLimit),
            active: active ?? promoActive,
            published: promoPublic)
    }

    private func savePromotion() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let path = editingCode.map { "/admin/billing/promotions/" + $0 }
                ?? "/admin/billing/promotions"
            let _: BillingPromotion = try await APIClient.shared.request(
                path, method: editingCode == nil ? "POST" : "PUT",
                body: draft())
            success = "Promoción guardada."
            resetPromotion()
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func togglePromotion(_ promo: BillingPromotion) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let request = BillingPromotionInput(
                code: promo.code, title: promo.title, planCode: promo.planCode,
                discountType: promo.discountType, discountValue: promo.discountValue,
                startsAt: promo.startsAt, endsAt: promo.endsAt,
                maxRedemptions: promo.maxRedemptions, active: !promo.active,
                published: promo.published)
            let _: BillingPromotion = try await APIClient.shared.request(
                "/admin/billing/promotions/\(promo.code)", method: "PUT", body: request)
            success = "Promoción actualizada."
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func edit(_ promo: BillingPromotion) {
        editingCode = promo.code
        promoCode = promo.code
        promoName = promo.title
        promoPlan = promo.planCode
        promoType = promo.discountType
        promoValue = promo.discountValue
        promoStarts = BillingFormatting.readISO(promo.startsAt)
        promoEnds = BillingFormatting.readISO(promo.endsAt)
        promoLimit = promo.maxRedemptions.map(String.init) ?? ""
        promoActive = promo.active
        promoPublic = promo.published
    }

    private func resetPromotion() {
        editingCode = nil
        promoCode = ""
        promoName = ""
        promoPlan = "MONTHLY"
        promoType = "PERCENT"
        promoValue = 20
        promoStarts = .now
        promoEnds = .now.addingTimeInterval(14 * 86400)
        promoLimit = ""
        promoActive = true
        promoPublic = false
    }

    private func grant() async {
        guard !saving,
              let id = Int(grantUserID),
              grantReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let _: BillingGrantResult = try await APIClient.shared.request(
                "/admin/billing/grants", method: "POST",
                body: BillingGrantInput(userId: id, planCode: grantPlan,
                                        reason: grantReason.trimmingCharacters(in: .whitespacesAndNewlines)))
            grantUserID = ""
            grantReason = ""
            success = "Acceso Pro concedido y auditado."
        } catch { self.error = error.localizedDescription }
    }
}
