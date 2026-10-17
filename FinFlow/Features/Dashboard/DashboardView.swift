import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats = TransactionStats()
    @State private var transactions: [FinanceTransaction] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenBackground {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) { Text("Hola, \(session.user?.name.components(separatedBy: " ").first ?? "Usuario") 👋").font(.title2.bold()); Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(FinFlowTheme.secondaryText) }
                            Spacer(); NavigationLink { SettingsView() } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 30)).foregroundStyle(FinFlowTheme.accent) }
                        }
                        if let error { ErrorBanner(message: error) }
                        SectionCard(title: "Balance total", subtitle: "Resumen de tus finanzas") {
                            Text(CurrencyFormatter.format(stats.balance)).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(stats.balance >= 0 ? FinFlowTheme.mint : FinFlowTheme.danger)
                            HStack(spacing: 12) {
                                metric("Ingresos", amount: stats.totalIncome, icon: "arrow.down.left", color: FinFlowTheme.mint)
                                metric("Gastos", amount: stats.totalExpenses, icon: "arrow.up.right", color: FinFlowTheme.danger)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            summaryCard("Tasa de ahorro", value: String(format: "%.1f%%", stats.savingsRate), icon: "chart.line.uptrend.xyaxis", color: FinFlowTheme.accent)
                            summaryCard("Movimientos", value: "\(transactions.count)", icon: "arrow.left.arrow.right", color: FinFlowTheme.mint)
                        }
                        if !stats.monthlyData.isEmpty {
                            SectionCard(title: "Evolución mensual", subtitle: "Ingresos y gastos registrados") {
                                HStack(spacing: 16) {
                                    Label("Ingresos", systemImage: "circle.fill").font(.caption).foregroundStyle(FinFlowTheme.mint)
                                    Label("Gastos", systemImage: "circle.fill").font(.caption).foregroundStyle(FinFlowTheme.danger)
                                }
                                Chart {
                                    ForEach(stats.monthlyData) { month in
                                        LineMark(x: .value("Mes", month.month), y: .value("Ingresos", month.income), series: .value("Serie", "Ingresos"))
                                            .foregroundStyle(FinFlowTheme.mint).symbol(Circle())
                                        LineMark(x: .value("Mes", month.month), y: .value("Gastos", month.expenses), series: .value("Serie", "Gastos"))
                                            .foregroundStyle(FinFlowTheme.danger).symbol(Circle())
                                    }
                                }
                                .chartLegend(.hidden)
                                .frame(height: 190)
                            }
                        }
                        SectionCard(title: "Últimos movimientos", subtitle: "Tus transacciones recientes") {
                            if transactions.isEmpty && !isLoading { EmptyState(icon: "tray", title: "Aún no hay movimientos", message: "Registra tus ingresos y gastos para verlos aquí.") }
                            ForEach(Array(transactions.prefix(5))) { transaction in TransactionRow(transaction: transaction) }
                            NavigationLink { TransactionsView() } label: { Text("Ver todos los movimientos →").font(.subheadline.weight(.semibold)).foregroundStyle(FinFlowTheme.accent).frame(maxWidth: .infinity, alignment: .trailing) }
                        }
                    }.padding(18)
                }
                .refreshable { await load() }
                .overlay { if isLoading { ProgressView().tint(FinFlowTheme.accent) } }
            }
            .navigationTitle("FinFlow").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } } }
            .task { await load() }
        }
    }
    private func metric(_ title: String, amount: Double, icon: String, color: Color) -> some View {
        HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(color).padding(9).background(color.opacity(0.13), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(FinFlowTheme.secondaryText); Text(CurrencyFormatter.compact(amount)).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75) } }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func summaryCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).foregroundStyle(color).font(.title3); Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedStats: TransactionStats = APIClient.shared.request("/transactions/stats")
            async let loadedTransactions: [FinanceTransaction] = APIClient.shared.request("/transactions")
            stats = try await loadedStats; transactions = try await loadedTransactions; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
