import SwiftUI

struct PlannedExpensesView: View {
    @State private var expenses: [PlannedExpense] = []
    @State private var categories: [FinanceCategory] = []
    @State private var filter = "all"
    @State private var editing: PlannedExpense?
    @State private var showingForm = false
    @State private var executeTarget: PlannedExpense?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isWorking = false

    private var filtered: [PlannedExpense] { expenses.filter { filter == "all" || $0.status == filter } }
    private var pendingTotal: Double { expenses.filter { $0.status == "pending" }.reduce(0) { $0 + $1.amount } }
    private var doneTotal: Double { expenses.filter { $0.status == "done" }.reduce(0) { $0 + $1.amount } }
    private var overdue: [PlannedExpense] { expenses.filter { $0.status == "pending" && ($0.parsedDueDate ?? .distantFuture) < Calendar.current.startOfDay(for: .now) } }

    var body: some View {
        NavigationStack {
            ScreenBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        if let error { ErrorBanner(message: error) }
                        if !overdue.isEmpty {
                            Label("Tienes \(overdue.count) gasto(s) vencido(s)", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold()).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }
                        HStack(spacing: 12) {
                            totalCard("Por ejecutar", value: pendingTotal, color: FinFlowTheme.accent)
                            totalCard("Ejecutado", value: doneTotal, color: FinFlowTheme.mint)
                        }
                        Picker("Estado", selection: $filter) {
                            Text("Todos").tag("all"); Text("Pendientes").tag("pending")
                            Text("Ejecutados").tag("done"); Text("Cancelados").tag("cancelled")
                        }.pickerStyle(.segmented)
                        if isLoading { ProgressView().padding(40) }
                        else if filtered.isEmpty { EmptyState(icon: "calendar.badge.clock", title: "Sin gastos planificados", message: "Planifica un gasto futuro para tenerlo en el radar.") }
                        ForEach(filtered) { expense in expenseCard(expense) }
                    }.padding(16)
                }.refreshable { await load() }
            }
            .navigationTitle("Gastos planificados")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editing = nil; showingForm = true } label: { Image(systemName: "plus.circle.fill") } } }
            .task { await load() }
            .sheet(isPresented: $showingForm, onDismiss: { Task { await load() } }) {
                PlannedExpenseForm(expense: editing, categories: categories) { request in
                    try await save(request, editing: editing)
                }
            }
            .confirmationDialog("¿Ejecutar este gasto? Se registrará como una transacción.", isPresented: Binding(get: { executeTarget != nil }, set: { if !$0 { executeTarget = nil } }), titleVisibility: .visible) {
                Button("Ejecutar gasto") { if let target = executeTarget { Task { await execute(target) } } }
                Button("Cancelar", role: .cancel) { executeTarget = nil }
            }
            .overlay { if isWorking { ProgressView().padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        }
    }

    private func totalCard(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
            Text(CurrencyFormatter.format(value)).font(.title3.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func expenseCard(_ expense: PlannedExpense) -> some View {
        let categoryName = categories.first(where: { $0.id == expense.categoryId })?.name ?? "Sin categoría"
        return SectionCard(title: expense.title, subtitle: "\(categoryName)\(expense.parsedDueDate.map { " · " + DateFormatters.display.string(from: $0) } ?? "")") {
            HStack {
                Text(CurrencyFormatter.format(expense.amount)).font(.title3.bold())
                Spacer()
                Text(statusLabel(expense.status)).font(.caption.bold()).foregroundStyle(statusColor(expense.status))
                    .padding(.horizontal, 9).padding(.vertical, 5).background(statusColor(expense.status).opacity(0.12), in: Capsule())
            }
            if let notes = expense.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
            HStack {
                if expense.status == "pending" {
                    Button("Ejecutar") { executeTarget = expense }.buttonStyle(.borderedProminent).tint(FinFlowTheme.accent)
                    Button("Editar") { editing = expense; showingForm = true }.buttonStyle(.bordered)
                }
                Spacer()
                Menu {
                    if expense.status == "pending" { Button("Cancelar gasto", role: .destructive) { Task { await cancel(expense) } } }
                    Button("Eliminar", role: .destructive) { Task { await delete(expense) } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func statusLabel(_ status: String) -> String { ["pending":"Pendiente", "done":"Ejecutado", "cancelled":"Cancelado"][status] ?? status }
    private func statusColor(_ status: String) -> Color { status == "done" ? FinFlowTheme.mint : status == "cancelled" ? FinFlowTheme.secondaryText : FinFlowTheme.accent }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedExpenses: [PlannedExpense] = APIClient.shared.request("/planned-expenses")
            async let loadedCategories: [FinanceCategory] = APIClient.shared.request("/categories")
            expenses = try await loadedExpenses
            categories = (try? await loadedCategories) ?? []
            error = nil
        } catch { error = error.localizedDescription }
    }

    private func save(_ request: PlannedExpenseRequest, editing: PlannedExpense?) async throws {
        isWorking = true; defer { isWorking = false }
        let path = editing.map { "/planned-expenses/\($0.id)" } ?? "/planned-expenses"
        let method = editing == nil ? "POST" : "PUT"
        let _: PlannedExpense = try await APIClient.shared.request(path, method: method, body: request)
    }

    private func execute(_ expense: PlannedExpense) async {
        isWorking = true; defer { isWorking = false }
        do {
            let updated: PlannedExpense = try await APIClient.shared.request("/planned-expenses/\(expense.id)/execute", method: "PATCH")
            replace(updated); executeTarget = nil
            // Backend creates the matching expense transaction atomically.
        } catch { error = error.localizedDescription; executeTarget = nil }
    }

    private func cancel(_ expense: PlannedExpense) async {
        isWorking = true; defer { isWorking = false }
        do { let updated: PlannedExpense = try await APIClient.shared.request("/planned-expenses/\(expense.id)/cancel", method: "PATCH"); replace(updated) }
        catch { error = error.localizedDescription }
    }

    private func delete(_ expense: PlannedExpense) async {
        isWorking = true; defer { isWorking = false }
        do { try await APIClient.shared.perform("/planned-expenses/\(expense.id)", method: "DELETE"); expenses.removeAll { $0.id == expense.id } }
        catch { error = error.localizedDescription }
    }

    private func replace(_ updated: PlannedExpense) {
        if let index = expenses.firstIndex(where: { $0.id == updated.id }) { expenses[index] = updated }
        else { expenses.insert(updated, at: 0) }
    }
}

struct PlannedExpenseForm: View {
    @Environment(\.dismiss) private var dismiss
    let expense: PlannedExpense?
    let categories: [FinanceCategory]
    let onSave: (PlannedExpenseRequest) async throws -> Void

    @State private var title = ""
    @State private var amount = ""
    @State private var categoryId = 0
    @State private var dueDate = Date()
    @State private var hasDate = true
    @State private var remind = false
    @State private var remindAt = Date()
    @State private var notes = ""
    @State private var error: String?

    private var expenseCategories: [FinanceCategory] { categories.filter { ["expense", "expenses"].contains($0.type.lowercased()) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detalle") {
                    TextField("Nombre del gasto", text: $title)
                    TextField("Monto (COP)", text: $amount).keyboardType(.decimalPad)
                    if !expenseCategories.isEmpty {
                        Picker("Categoría", selection: $categoryId) {
                            Text("Sin categoría").tag(0)
                            ForEach(expenseCategories) { Text($0.name).tag($0.id) }
                        }
                    }
                    Toggle("Definir fecha límite", isOn: $hasDate)
                    if hasDate { DatePicker("Fecha", selection: $dueDate, displayedComponents: .date) }
                    Toggle("Recordatorio", isOn: $remind)
                    if remind { DatePicker("Recordar el", selection: $remindAt, displayedComponents: .date) }
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section { Button("Guardar gasto") { save() }.frame(maxWidth: .infinity).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount.isEmpty) }
            }
            .navigationTitle(expense == nil ? "Nuevo gasto planificado" : "Editar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let expense else {
            categoryId = expenseCategories.first?.id ?? 0
            return
        }
        title = expense.title
        amount = String(expense.amount)
        categoryId = expense.categoryId ?? 0
        if let parsed = expense.parsedDueDate { dueDate = parsed } else { hasDate = false }
        notes = expense.notes ?? ""
        if let remindDate = DateFormatters.parse(expense.remindAt) { remind = true; remindAt = remindDate }
    }

    private func save() {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { error = "Ingresa un monto válido."; return }
        let request = PlannedExpenseRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: value,
            categoryId: categoryId == 0 ? nil : categoryId,
            dueDate: hasDate ? DateFormatters.isoDay.string(from: dueDate) : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            remindAt: remind ? DateFormatters.isoDay.string(from: remindAt) : nil
        )
        Task {
            do { try await onSave(request); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
