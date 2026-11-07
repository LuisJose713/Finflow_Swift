import SwiftUI

/// Public catalog is read from Spring Boot. iOS purchases remain disabled until
/// StoreKit 2 receipts are verified on the backend and App Store rules are met.
struct BillingView: View {
    @State private var catalog: BillingCatalog?
    @State private var entitlement: BillingEntitlement?
    @State private var selectedPlan = "MONTHLY"
    @State private var couponCode = ""
    @State private var quotedOffer: BillingOffer?
    @State private var fetching = true
    @State private var applying = false
    @State private var error: String?

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("FINFLOW PRO", systemImage: "crown.fill")
                            .font(.caption).bold().foregroundStyle(FinFlowTheme.accent)
                        Text("Tus finanzas, tu futuro.").font(.largeTitle).bold()
                        Text("Empieza gratis, prueba las funciones Pro durante tu primer mes y decide después. Sin tarjeta y sin cobros automáticos por la prueba.")
                            .foregroundStyle(FinFlowTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let entitlement {
                        SectionCard(title: "Mi plan", subtitle: "Confirmado por FinFlow") {
                            Label(planName(entitlement.planCode), systemImage: entitlement.pro ? "checkmark.seal.fill" : "checkmark.circle")
                                .foregroundStyle(FinFlowTheme.accent)
                            if entitlement.planCode == "TRIAL" {
                                Text("Disfrutas de la prueba Pro. Al terminar puedes seguir en Gratis sin pagar.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if fetching { ProgressView("Consultando planes…").frame(maxWidth: .infinity) }
                    if let error { ErrorBanner(message: error) }
                    if let catalog {
                        ForEach(catalog.offers) { offer in
                            SectionCard(title: offer.title, subtitle: offer.description) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if offer.originalCop > offer.priceCop {
                                        Text(BillingFormatting.cop(offer.originalCop))
                                            .strikethrough().font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(BillingFormatting.cop(offer.priceCop))
                                        .font(.system(size: 31, weight: .bold, design: .rounded))
                                        .minimumScaleFactor(0.7).lineLimit(1)
                                    Text(period(offer.code)).font(.caption).foregroundStyle(.secondary)
                                    if let promo = offer.promoTitle {
                                        Label("\(promo) · ahorra \(offer.savingsPercent)%", systemImage: "tag.fill")
                                            .font(.footnote).foregroundStyle(FinFlowTheme.mint)
                                    }
                                    if entitlement?.planCode == offer.code {
                                        Label("Este es tu plan actual", systemImage: "checkmark.circle.fill")
                                            .font(.subheadline).foregroundStyle(.green)
                                    }
                                    if offer.code != "FREE" {
                                        Label("Compra aún no disponible en iOS", systemImage: "lock.shield")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Las funciones esenciales de FinFlow siguen siendo gratuitas.")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        SectionCard(title: "¿Tienes un código promocional?") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Plan", selection: $selectedPlan) {
                                    ForEach(catalog.offers.filter { $0.code != "FREE" }) { offer in
                                        Text(offer.title).tag(offer.code)
                                    }
                                }
                                .pickerStyle(.menu)
                                TextField("Código promocional", text: $couponCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    Task { await quotePromotion() }
                                } label: {
                                    if applying { ProgressView() }
                                    else { Label("Consultar descuento", systemImage: "tag") }
                                }
                                .disabled(applying || couponCode.trimmingCharacters(in: .whitespaces).isEmpty)
                                if let quotedOffer {
                                    Text("Precio calculado: \(BillingFormatting.cop(quotedOffer.priceCop)). La compra no está habilitada todavía.")
                                        .font(.subheadline).foregroundStyle(FinFlowTheme.accent)
                                }
                            }
                        }
                        SectionCard(title: "¿Prefieres apoyar sin pagar Pro?", subtitle: "Donaciones voluntarias") {
                            Text("Puedes seguir en Gratis. Más adelante podrás aportar la cantidad que quieras para apoyar los servidores y el desarrollo, sin cambiar de plan.")
                                .font(.subheadline)
                            Label("Donaciones todavía no habilitadas", systemImage: "heart")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Los importes provienen del servidor y pueden cambiar. Los pagos digitales en iOS se habilitarán únicamente cuando exista integración segura y compatible con App Store.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Planes y precios")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        fetching = true
        defer { fetching = false }
        error = nil
        do {
            let response: BillingCatalog = try await APIClient.shared.request("/billing/catalog")
            catalog = response
            if !response.offers.contains(where: { $0.code == selectedPlan && $0.code != "FREE" }) {
                selectedPlan = response.offers.first(where: { $0.code != "FREE" })?.code ?? "MONTHLY"
            }
        } catch { self.error = "No fue posible consultar los planes: \(error.localizedDescription)" }
        // The account plan is server-confirmed; the client never sets it.
        entitlement = try? await APIClient.shared.request("/billing/me")
    }

    private func quotePromotion() async {
        applying = true
        defer { applying = false }
        error = nil
        quotedOffer = nil
        do {
            let result: BillingOffer = try await APIClient.shared.request(
                "/billing/quote",
                query: ["planCode": selectedPlan, "promoCode": couponCode.trimmingCharacters(in: .whitespacesAndNewlines)])
            quotedOffer = result
        } catch { self.error = "La promoción no es válida o está vencida: \(error.localizedDescription)" }
    }

    private func planName(_ code: String) -> String {
        switch code {
        case "FREE": return "FinFlow Gratis"
        case "TRIAL": return "Un mes de prueba Pro"
        case "MONTHLY": return "Pro mensual"
        case "YEARLY": return "Pro anual"
        case "LIFETIME": return "Pro de por vida"
        default: return "FinFlow"
        }
    }

    private func period(_ code: String) -> String {
        switch code {
        case "MONTHLY": return "por mes"
        case "YEARLY": return "por año"
        case "LIFETIME": return "pago único"
        default: return "para siempre"
        }
    }
}
