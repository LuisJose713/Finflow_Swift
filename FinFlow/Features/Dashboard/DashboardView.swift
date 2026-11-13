import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats = TransactionStats()
    @State private var transactions: [FinanceTransaction] = []
    @State private var recentCount = 5
    @State private var isLoading = true
    @State private var lastUpdated: Date?
    @State private var requestInFlight = false
    @State private var error: String?
    @State private var hideAmounts = false
    @State private var preparingEntry = false
    @State private var entryError: String?
    @State private var entryCategories: [FinanceCategory] = []
    @State private var entryAccounts: [FinancialAccount] = []
    @State private var entryAccountNotice: String?
    @State private var draft: TransactionDraftKind?

    private enum TransactionDraftKind: String, Identifiable {
        case expense, income
        var id: String { rawValue }
    }

    private var firstName: String {
        session.user?.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Usuario"
    }

    private var recentTransactions: [FinanceTransaction] {
        Array(transactions.sorted {
            let firstDate = DateFormatters.parse($0.date ?? $0.createdAt) ?? .distantPast
            let secondDate = DateFormatters.parse($1.date ?? $1.createdAt) ?? .distantPast
            if firstDate == secondDate { return $0.id > $1.id }
            return firstDate > secondDate
        }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScreenBackground {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if let error {
                            VStack(alignment: .leading, spacing: 10) {
                                ErrorBanner(message: error)
                                Button("Reintentar conexión") { Task { await load() } }
                                    .buttonStyle(.borderedProminent)
                                    .tint(FinFlowTheme.accent)
                                    .disabled(isLoading)
                            }
                            .accessibilityIdentifier("dashboard.error")
                        }
                        if lastUpdated != nil {
                            balanceCard
                            quickActions
                            summaryCards
                            charts
                            recentMovements
                        } else if isLoading {
                            ProgressView("Consultando tus finanzas…")
                                .frame(maxWidth: .infinity).padding(.vertical, 48)
                        } else {
                            EmptyState(icon: "wifi.exclamationmark", title: "Tu resumen no está disponible",
                                       message: "Reintenta la conexión para consultar tus importes. Aún no hemos recibido tus datos.")
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 20).padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
            }
            .navigationTitle("FinFlow").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Label("Actualizar resumen", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .finflowFinanceChanged).receive(on: RunLoop.main)) { _ in
                Task { await load() }
            }
            .sheet(item: $draft, onDismiss: { Task { await load() } }) { kind in
                CreateTransactionView(categories: entryCategories, accounts: entryAccounts,
                                      initialType: kind.rawValue, accountNotice: entryAccountNotice)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TU DINERO, CON UN PLAN")
                    .font(.caption2.weight(.bold)).tracking(1.6).foregroundStyle(FinFlowTheme.accent)
                Text("Hola, \(firstName)").font(.largeTitle.bold())
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(FinFlowTheme.secondaryText)
            }
            Spacer()
            NavigationLink { SettingsView() } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(FinFlowTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Abrir ajustes y perfil")
        }
    }

    private var balanceCard: some View {
        SectionCard(title: "Balance registrado", subtitle: "Todo tu historial · COP") {
            HStack(alignment: .firstTextBaseline) {
                Text(amount(stats.balance)).font(.system(.largeTitle, design: .rounded).bold())
                    .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
                    .accessibilityIdentifier("dashboard.balance")
                    .foregroundStyle(hideAmounts ? Color.primary : (stats.balance >= 0 ? FinFlowTheme.mint : FinFlowTheme.danger))
                    .privacySensitive()
                Spacer(minLength: 8)
                Button { hideAmounts.toggle() } label: {
                    Image(systemName: hideAmounts ? "eye.slash" : "eye")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .tint(FinFlowTheme.accent)
                .accessibilityLabel(hideAmounts ? "Mostrar importes del resumen" : "Ocultar importes del resumen")
                .accessibilityHint("También oculta los gráficos y los importes de movimientos en esta pantalla.")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { incomeMetric; expenseMetric }
                VStack(alignment: .leading, spacing: 14) { incomeMetric; expenseMetric }
            }
            Text("Ingresos menos gastos registrados. No equivale a tu saldo bancario ni descuenta pagos pendientes o dinero para metas.")
                .font(.footnote).foregroundStyle(FinFlowTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let lastUpdated {
                Label(isLoading ? "Actualizando…" : "Actualizado a las \(lastUpdated.formatted(date: .omitted, time: .shortened))",
                      systemImage: isLoading ? "arrow.clockwise" : "checkmark.circle")
                    .font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
            }
        }
    }

    private var incomeMetric: some View {
        metric("Ingresos", amount: stats.totalIncome, icon: "arrow.down.left", color: FinFlowTheme.mint)
    }
    private var expenseMetric: some View {
        metric("Gastos", amount: stats.totalExpenses, icon: "arrow.up.right", color: FinFlowTheme.danger)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registra hoy, decide con claridad").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { expenseButton; incomeButton }
                VStack(spacing: 12) { expenseButton; incomeButton }
            }
            if preparingEntry { ProgressView("Preparando movimiento…").font(.caption) }
            if let entryError {
                ErrorBanner(message: entryError)
                NavigationLink { CategoriesView() } label: {
                    Label("Revisar categorías", systemImage: "square.grid.2x2")
                        .font(.subheadline).frame(minHeight: 44)
                }
            }
            NavigationLink { PlannedExpensesView() } label: {
                Label("Revisar próximos pagos", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
    }

    private var expenseButton: some View {
        Button { Task { await prepareEntry(.expense) } } label: {
            Label("Registrar gasto", systemImage: "minus.circle.fill")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(FinFlowTheme.accent).disabled(preparingEntry)
        .accessibilityIdentifier("dashboard.addExpense")
    }
    private var incomeButton: some View {
        Button { Task { await prepareEntry(.income) } } label: {
            Label("Registrar ingreso", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered).tint(FinFlowTheme.accent).disabled(preparingEntry)
        .accessibilityIdentifier("dashboard.addIncome")
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .top)], spacing: 12) {
            summaryCard("Margen sobre ingresos",
                        value: hideAmounts ? "••••" : (stats.totalIncome > 0 ? String(format: "%.1f%%", stats.savingsRate) : "Sin ingresos"),
                        icon: "chart.line.uptrend.xyaxis",
                        color: stats.savingsRate < 0 ? FinFlowTheme.danger : FinFlowTheme.accent)
            summaryCard("Movimientos registrados", value: "\(transactions.count)",
                        icon: "arrow.left.arrow.right", color: FinFlowTheme.mint)
        }
    }

    @ViewBuilder private var charts: some View {
        if hideAmounts {
            SectionCard(title: "Gráficos del resumen") {
                Label("Importes ocultos en esta pantalla", systemImage: "eye.slash")
                    .font(.subheadline).foregroundStyle(FinFlowTheme.secondaryText)
            }
        } else {
            FinancialSummaryCharts(stats: stats)
        }
    }

    private var recentMovements: some View {
        SectionCard(title: "Movimientos recientes") {
            if !recentTransactions.isEmpty {
                HStack(spacing: 6) {
                    Text("Mostrar").font(.caption)
                        .foregroundStyle(FinFlowTheme.secondaryText)
                    Spacer(minLength: 0)
                    ForEach([2, 3, 5], id: \.self) { count in
                        Button { recentCount = count } label: {
                            Text(String(count))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(recentCount == count ? FinFlowTheme.gold : Color.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(recentCount == count
                                    ? FinFlowTheme.gold.opacity(0.14) : FinFlowTheme.elevated,
                                    in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mostrar los últimos \(count) movimientos")
                    }
                }
                .accessibilityIdentifier("dashboard.recentCount")
                Divider()
            }
            if recentTransactions.isEmpty {
                EmptyState(icon: "tray", title: "Tu plan empieza con un movimiento",
                           message: "Registra tu primer ingreso o gasto con los botones de arriba.")
            }
            ForEach(Array(recentTransactions.prefix(recentCount))) { transaction in
                TransactionRow(transaction: transaction, hideAmount: hideAmounts)
            }
            NavigationLink { TransactionsView() } label: {
                Label("Ver todos los movimientos", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinFlowTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }
    }

    private func amount(_ value: Double) -> String {
        hideAmounts ? "••••" : CurrencyFormatter.format(value)
    }

    private func metric(_ title: String, amount value: Double, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).padding(9)
                .background(color.opacity(0.13), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                Text(amount(value)).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func summaryCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).accessibilityHidden(true)
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    @MainActor private func load() async {
        guard !requestInFlight, let owner = session.user?.id else { return }
        requestInFlight = true
        isLoading = true
        defer { isLoading = false; requestInFlight = false }
        do {
            async let loadedStats: TransactionStats = APIClient.shared.request("/transactions/stats")
            async let loadedTransactions: [FinanceTransaction] = APIClient.shared.request("/transactions")
            // Keep the previous snapshot until both requests succeed. A partial
            // refresh must not pair new totals with stale movements.
            let snapshot = try await (loadedStats, loadedTransactions)
            guard !Task.isCancelled, session.user?.id == owner else { return }
            stats = snapshot.0
            transactions = snapshot.1
            lastUpdated = .now
            error = nil
        } catch {
            guard !Task.isCancelled, session.user?.id == owner else { return }
            self.error = lastUpdated == nil
                ? "No pudimos consultar tus finanzas. Revisa tu conexión e inténtalo de nuevo."
                : "No pudimos actualizar tus finanzas. Se conserva el último resumen cargado."
        }
    }

    @MainActor private func prepareEntry(_ kind: TransactionDraftKind) async {
        guard !preparingEntry else { return }
        preparingEntry = true
        entryError = nil
        defer { preparingEntry = false }
        do {
            async let categories: [FinanceCategory] = APIClient.shared.request("/categories")
            async let accounts: [FinancialAccount] = APIClient.shared.request("/accounts")
            let loadedCategories = try await categories
            let loadedAccounts = try? await accounts
            guard !Task.isCancelled else { return }
            guard loadedCategories.contains(where: { $0.type.lowercased() == kind.rawValue }) else {
                entryError = "Necesitas una categoría de \(kind == .expense ? "gasto" : "ingreso") antes de registrar este movimiento."
                return
            }
            entryCategories = loadedCategories
            entryAccounts = loadedAccounts ?? []
            entryAccountNotice = loadedAccounts == nil
                ? "No pudimos consultar tus billeteras. Este movimiento se registrará sin billetera. Puedes cancelar e intentarlo de nuevo."
                : nil
            draft = kind
        } catch {
            entryError = "No pudimos preparar el movimiento. Revisa tu conexión y vuelve a intentarlo."
        }
    }
}
