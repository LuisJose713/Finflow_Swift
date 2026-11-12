import SwiftUI

/// Monthly COP budgets: the API calculates expenses and alerts for the signed-in user.
struct BudgetsView: View {
    @State private var budgets: [BudgetOverview] = []
    @State private var categories: [FinanceCategory] = []
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var loading = true
    @State private var error: String?
    @State private var showingEditor = false
    @State private var editing: BudgetOverview?
    @State private var deleting: BudgetOverview?

    private var remaining: Double { budgets.reduce(0) { $0 + $1.remaining } }
    private var totalLimit: Double { budgets.reduce(0) { $0 + $1.limitAmount } }
    private var totalSpent: Double { budgets.reduce(0) { $0 + $1.spent } }
    private var years: [Int] { Array((year - 2)...(year + 2)) }

    var body: some View {
            ScreenBackground {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        PresentationCard(cardID: "budgets.intro", eyebrow: "Presupuestos", title: "Dale un rumbo a cada peso.", detail: "Define límites por categoría y acompaña tu progreso mensual.", symbol: "chart.bar.xaxis")
                        HStack {
                            Picker("Mes", selection: $month) {
                                ForEach(1...12, id: \.self) { value in
                                    Text(Calendar.current.monthSymbols[value - 1]).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            Picker("Año", selection: $year) {
                                ForEach(years, id: \.self) { value in
                                    Text(String(value)).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, 12)
                        .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                        if let error { ErrorBanner(message: error) }
                        if loading { ProgressView("Consultando presupuestos…").padding(24) }
                        else {
                            if budgets.isEmpty {
                                EmptyState(icon: "chart.pie", title: "Sin presupuestos",
                                           message: "Define límites por categoría para \(Calendar.current.monthSymbols[month - 1]).")
                            } else {
                                SectionCard(title: "Tu presupuesto mensual", subtitle: "Solo gastos completados en COP") {
                                    Text(CurrencyFormatter.format(totalSpent))
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                    Text("Gastado de \(CurrencyFormatter.format(totalLimit))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Label("Disponible: \(CurrencyFormatter.format(remaining))",
                                          systemImage: "wallet.pass")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(remaining < 0 ? FinFlowTheme.danger : FinFlowTheme.mint)
                                }
                                ForEach(budgets) { budget in budgetCard(budget) }
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            }
            .navigationTitle("Presupuestos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        showingEditor = true
                    } label: { Label("Crear presupuesto", systemImage: "plus.circle.fill") }
                }
            }
            .task { await load() }
            .onChange(of: month) { _, _ in Task { await load() } }
            .onChange(of: year) { _, _ in Task { await load() } }
            .sheet(isPresented: $showingEditor, onDismiss: { Task { await load() } }) {
                BudgetEditor(
                    budget: editing,
                    categories: categories.filter { category in
                        category.type.lowercased() == "expense" &&
                        !budgets.contains(where: { $0.categoryId == category.id })
                    },
                    year: year, month: month
                ) { selectedCategory, amount in
                    if let editing {
                        let _: CreatedBudget = try await APIClient.shared.request(
                            "/budgets/\(editing.id)", method: "PUT",
                            body: UpdateBudgetLimitRequest(amount: amount))
                    } else {
                        let _: CreatedBudget = try await APIClient.shared.request(
                            "/budgets", method: "POST",
                            body: CreateBudgetRequest(categoryId: selectedCategory,
                                                      year: year, month: month, amount: amount))
                    }
                }
            }
            .confirmationDialog("¿Eliminar presupuesto?", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    if let deleting { Task { await remove(deleting) } }
                }
                Button("Cancelar", role: .cancel) { deleting = nil }
            } message: {
                Text("Eliminar el presupuesto no elimina tus movimientos.")
            }
    }

    private func budgetCard(_ budget: BudgetOverview) -> some View {
        SectionCard(title: budget.categoryName,
                    subtitle: "\(budget.percentUsed)% utilizado · \(budget.currency)") {
            HStack {
                Text(CurrencyFormatter.format(budget.spent)).font(.title3.bold())
                Spacer()
                Text("de \(CurrencyFormatter.format(budget.limitAmount))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: budget.progress)
                .tint(statusColor(budget.status))
            HStack {
                Label(budget.remaining < 0 ? "Excedido" : "Disponible",
                      systemImage: budget.remaining < 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(statusColor(budget.status))
                Text(CurrencyFormatter.format(budget.remaining))
                    .font(.caption.weight(.semibold))
                Spacer()
                Menu {
                    Button("Editar límite", systemImage: "pencil") {
                        editing = budget; showingEditor = true
                    }
                    Button("Eliminar", systemImage: "trash", role: .destructive) {
                        deleting = budget
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
            if budget.status == "near" {
                Label("Atención: alcanzaste el 80% de tu límite",
                      systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            } else if budget.status == "over" {
                Label("Superaste el límite de esta categoría",
                      systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(FinFlowTheme.danger)
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "over": return FinFlowTheme.danger
        case "near": return .orange
        default: return FinFlowTheme.mint
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let remoteBudgets: [BudgetOverview] = APIClient.shared.request(
                "/budgets", query: ["year": String(year), "month": String(month)])
            async let remoteCategories: [FinanceCategory] = APIClient.shared.request("/categories")
            let loadedBudgets = try await remoteBudgets
            let loadedCategories = try await remoteCategories
            budgets = loadedBudgets
            categories = loadedCategories
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ budget: BudgetOverview) async {
        do {
            try await APIClient.shared.perform("/budgets/\(budget.id)", method: "DELETE")
            budgets.removeAll { $0.id == budget.id }
            deleting = nil
        } catch {
            self.error = error.localizedDescription
            deleting = nil
        }
    }
}

/// Response shape for POST and PUT: the backend returns MonthlyBudget, not BudgetOverview.
struct CreatedBudget: Decodable {
    let id: Int
}

struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    let budget: BudgetOverview?
    let categories: [FinanceCategory]
    let year: Int
    let month: Int
    let onSave: (Int, Double) async throws -> Void
    @State private var categoryID = 0
    @State private var amount = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Límite mensual") {
                    LabeledContent("Periodo", value: "\(month)/\(year)")
                    if let budget {
                        LabeledContent("Categoría", value: budget.categoryName)
                    } else {
                        Picker("Categoría", selection: $categoryID) {
                            Text("Seleccionar").tag(0)
                            ForEach(categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                    }
                    COPAmountField("Monto máximo (COP)", text: $amount)
                }
                if let error { ErrorBanner(message: error) }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() } else { Text("Guardar presupuesto") }
                            Spacer()
                        }
                    }.disabled(saving)
                }
            }
            .navigationTitle(budget == nil ? "Nuevo presupuesto" : "Editar límite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear {
                if let budget {
                    categoryID = budget.categoryId
                    amount = String(budget.limitAmount)
                } else {
                    categoryID = categories.first?.id ?? 0
                }
            }
        }
    }

    private func save() async {
        guard categoryID != 0,
              let parsed = Double(amount.replacingOccurrences(of: ",", with: ".")),
              parsed.isFinite, parsed > 0, parsed <= 999_999_999_999.99 else {
            error = "Selecciona una categoría e ingresa un límite positivo válido."
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await onSave(categoryID, parsed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
