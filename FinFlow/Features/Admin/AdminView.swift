import SwiftUI
import Charts

/// Aggregated and anonymized operating metrics; never displays other users' financial records.
/// Backend always validates ROLE_ADMIN independently from this UI gate.
struct AdminView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var overview: AdminOverview?
    @State private var loading = true
    @State private var error: String?

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
                        if let error {
                            ErrorBanner(message: error)
                            Button("Volver a intentar") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        if loading { ProgressView("Cargando indicadores…").padding(24) }
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
            .refreshable { if session.user?.isAdmin == true { await load() } }
        }
        .navigationTitle("Administración")
        .task { if session.user?.isAdmin == true { await load() } else { loading = false } }
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
