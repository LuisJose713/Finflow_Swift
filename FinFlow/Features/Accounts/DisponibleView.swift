import SwiftUI

/// FinFlow Disponible: a user-controlled read-only budget estimate.
/// Input dates and reserve are ephemeral and never persisted or uploaded.
struct DisponibleView: View {
    @State private var accounts: [FinancialAccount] = []
    @State private var plannedExpenses: [PlannedExpense] = []
    @State private var nextPayday = Calendar.current.date(byAdding: .day, value: 15, to: .now) ?? .now
    @State private var reservedText = "0"
    @State private var loading = true
    @State private var error: String?

    private var activeAccounts: [FinancialAccount] {
        accounts.filter { !$0.archived && $0.currency.uppercased() == "COP" }
    }
    private var reserveAmount: Decimal? {
        let value = reservedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Decimal(string: value.replacingOccurrences(of: ",", with: "."),
                       locale: Locale(identifier: "en_US_POSIX"))
    }
    private var snapshot: DisponibleSnapshot? {
        guard let reserveAmount else { return nil }
        return DisponibleCalculator.calculate(
            accounts: accounts, expenses: plannedExpenses,
            reserve: reserveAmount, payday: nextPayday
        )
    }

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("FINFLOW DISPONIBLE", systemImage: "wallet.bifold")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FinFlowTheme.accent)
                        Text("Tu dinero, con claridad.")
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.75)
                        Text("Descubre cuánto podrías gastar antes de tu próximo ingreso, después de separar pagos pendientes y ahorros.")
                            .font(.subheadline)
                            .foregroundStyle(FinFlowTheme.secondaryText)
                    }.padding(.vertical, 8)

                    SectionCard(title: "Tu próximo ingreso", subtitle: "Configura tu quincena o fecha habitual de pago") {
                        VStack(alignment: .leading, spacing: 14) {
                            DatePicker("Próxima fecha de pago",
                                       selection: $nextPayday,
                                       in: Date.now...Date.distantFuture,
                                       displayedComponents: .date)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ahorro que deseas reservar (COP)")
                                    .font(.subheadline.weight(.medium))
                                TextField("0", text: $reservedText)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.decimalPad)
                                    .accessibilityIdentifier("disponible.reserve")
                            }
                            Text("Esta fecha y reserva solo afectan el cálculo visible; no se guardan en tu cuenta.")
                                .font(.caption)
                                .foregroundStyle(FinFlowTheme.secondaryText)
                        }
                    }
                    if loading {
                        ProgressView("Consultando tus datos…")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    }
                    if let error {
                        ErrorBanner(message: error)
                        Button("Volver a consultar") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }

                    if !loading && error == nil {
                        if activeAccounts.isEmpty {
                            SectionCard(title: "Primero, registra una billetera") {
                                EmptyState(icon: "wallet.pass", title: "Sin saldo registrado",
                                           message: "Necesitamos una cuenta en COP con saldo. No queremos mostrar un dinero disponible inventado.")
                                NavigationLink("Ir a mis billeteras") { AccountsView() }
                            }
                        } else if let snapshot {
                            SectionCard(title: "Dinero disponible estimado",
                                        subtitle: "Hasta dentro de \(snapshot.days) día(s)") {
                                Text(CurrencyFormatter.format(NSDecimalNumber(decimal: snapshot.available).doubleValue))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(snapshot.available >= 0 ? FinFlowTheme.mint : FinFlowTheme.danger)
                                    .minimumScaleFactor(0.55)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("disponible.amount")
                                if snapshot.available >= 0 {
                                    Text("Podrías repartir hasta \(CurrencyFormatter.format(NSDecimalNumber(decimal: snapshot.dailyAllowance).doubleValue)) diarios, siempre que no aparezcan otros gastos.")
                                        .font(.subheadline)
                                } else {
                                    Text("Tus obligaciones y reservas superan el saldo registrado. Revisa tus compromisos antes de gastar.")
                                        .font(.subheadline)
                                        .foregroundStyle(FinFlowTheme.danger)
                                }
                            }
                            SectionCard(title: "Así se calcula") {
                                breakdown("Saldo de cuentas activas", snapshot.balance)
                                breakdown("Gastos pendientes (\(snapshot.pendingCount))", -snapshot.pending)
                                breakdown("Ahorro reservado", -snapshot.reserved)
                                Divider()
                                breakdown("Disponible estimado", snapshot.available, bold: true)
                            }
                            SectionCard(title: "Antes de decidir") {
                                Text("Incluimos pagos planificados pendientes, incluso vencidos, con fecha anterior al próximo ingreso. No sumamos ingresos futuros, otros gastos sin registrar ni movimientos recurrentes que podrían duplicar obligaciones.")
                                    .font(.footnote)
                                    .foregroundStyle(FinFlowTheme.secondaryText)
                                if snapshot.missingDateCount > 0 {
                                    Text("Tienes \(snapshot.missingDateCount) gasto(s) pendientes sin fecha; no se pueden ubicar dentro de la quincena.")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(FinFlowTheme.danger)
                                }
                                Text("Marca como ejecutados los pagos que ya descontaste del saldo. Esta es una orientación basada en tus registros, no un saldo bancario certificado.")
                                    .font(.footnote)
                                    .foregroundStyle(FinFlowTheme.secondaryText)
                                NavigationLink("Revisar gastos planificados") { PlannedExpensesView() }
                            }
                        } else {
                            ErrorBanner(message: "Revisa tu ahorro reservado y la fecha. El ingreso debe ser dentro de los próximos 366 días y la reserva debe ser mayor o igual a cero.")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Mi disponible")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func breakdown(_ title: String, _ amount: Decimal, bold: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(bold ? .subheadline.weight(.bold) : .subheadline)
            Spacer(minLength: 8)
            Text(CurrencyFormatter.format(NSDecimalNumber(decimal: amount).doubleValue))
                .font(bold ? .subheadline.weight(.bold) : .subheadline)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let a: [FinancialAccount] = APIClient.shared.request("/accounts")
            async let p: [PlannedExpense] = APIClient.shared.request("/planned-expenses")
            let (accountsResult, expensesResult) = try await (a, p)
            accounts = accountsResult
            plannedExpenses = expensesResult
        } catch {
            self.error = "No pudimos cargar los saldos y compromisos: \(error.localizedDescription)"
        }
    }
}
