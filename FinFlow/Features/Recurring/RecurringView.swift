import SwiftUI

struct RecurringView: View {
    @State private var rules: [RecurringRule] = []
    @State private var categories: [FinanceCategory] = []
    @State private var accounts: [FinancialAccount] = []
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var information: String?
    @State private var showEditor = false
    @State private var ruleToDelete: RecurringRule?
    @State private var confirmRun = false

    var body: some View {
        ScreenBackground {
            ScrollView {
                LazyVStack(spacing: 16) {
                        PresentationCard(cardID: "recurring.intro", eyebrow: "Movimientos recurrentes", title: "Tus hábitos financieros, organizados.", detail: "Programa tus movimientos y revisa las próximas ejecuciones.", symbol: "repeat")
                    if let error { ErrorBanner(message: error) }
                    if let information {
                        Label(information, systemImage: "checkmark.circle")
                            .foregroundStyle(FinFlowTheme.mint)
                            .font(.subheadline).padding(12)
                    }
                    SectionCard(title: "Movimientos recurrentes",
                                subtitle: "Ingresos y gastos automáticos, del día 1 al 28 de cada mes") {
                        Text("La próxima ejecución la calcula el servidor de FinFlow con horario de Colombia.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Procesar vencidos ahora") { confirmRun = true }
                            .buttonStyle(.bordered)
                            .disabled(working || rules.filter { $0.active }.isEmpty)
                    }

                    if loading { ProgressView("Cargando recurrencias…").padding(28) }
                    else if rules.isEmpty {
                        EmptyState(icon: "repeat", title: "Aún sin recurrencias",
                                   message: "Programa arriendo, nómina, servicios o tus aportes mensuales.")
                    }
                    ForEach(rules) { rule in
                        SectionCard(title: rule.title,
                                    subtitle: (rule.type == "income" ? "Ingreso" : "Gasto") +
                                              " · Día \(rule.dayOfMonth) de cada mes") {
                            HStack {
                                Text(CurrencyFormatter.format(rule.amount))
                                    .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer()
                                Text(rule.active ? "Activa" : "Pausada")
                                    .font(.caption.bold())
                                    .foregroundStyle(rule.active ? FinFlowTheme.mint : .secondary)
                            }
                            Text("Próxima fecha: \(rule.nextDueDate)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Categoría: \(categories.first { $0.id == rule.categoryId }?.name ?? "No disponible")")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(rule.active ? "Pausar" : "Activar") {
                                    Task { await toggle(rule) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(working)
                                Spacer()
                                Button("Eliminar", role: .destructive) { ruleToDelete = rule }
                                    .buttonStyle(.bordered)
                                    .disabled(working)
                            }
                        }
                    }
                }.padding(16)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Recurrentes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Label("Programar movimiento", systemImage: "plus.circle.fill")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            RecurringEditor(categories: categories, accounts: accounts) { value in
                let _: RecurringRule = try await APIClient.shared.request(
                    "/recurring", method: "POST", body: value)
            }
        }
        .confirmationDialog("¿Eliminar recurrencia?", isPresented: Binding(
            get: { ruleToDelete != nil },
            set: { if !$0 { ruleToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let rule = ruleToDelete { Task { await remove(rule) } }
            }
            Button("Cancelar", role: .cancel) { ruleToDelete = nil }
        } message: {
            Text("No se borrarán movimientos ya registrados.")
        }
        .confirmationDialog("¿Ejecutar movimientos pendientes?", isPresented: $confirmRun, titleVisibility: .visible) {
            Button("Ejecutar ahora") { Task { await processDue() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Solo se procesarán las reglas vencidas. El servidor impide duplicar el mismo vencimiento.")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let a: [RecurringRule] = APIClient.shared.request("/recurring")
            async let b: [FinanceCategory] = APIClient.shared.request("/categories")
            async let c: [FinancialAccount] = APIClient.shared.request("/accounts")
            rules = try await a
            categories = try await b
            accounts = try await c
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func toggle(_ rule: RecurringRule) async {
        working = true
        defer { working = false }
        do {
            let _: RecurringRule = try await APIClient.shared.request(
                "/recurring/\(rule.id)/active", method: "PATCH",
                body: RecurringActivation(active: !rule.active))
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ rule: RecurringRule) async {
        working = true
        defer { working = false; ruleToDelete = nil }
        do {
            try await APIClient.shared.perform("/recurring/\(rule.id)", method: "DELETE")
            rules.removeAll { $0.id == rule.id }
        } catch { self.error = error.localizedDescription }
    }
    private func processDue() async {
        working = true
        defer { working = false }
        do {
            let response: ProcessRecurringResult = try await APIClient.shared.request(
                "/recurring/process-due", method: "POST")
            information = response.created == 0
                ? "No hay movimientos vencidos."
                : "Se registraron \(response.created) movimientos."
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct RecurringEditor: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [FinanceCategory]
    let accounts: [FinancialAccount]
    let onSave: (CreateRecurringRule) async throws -> Void
    @State private var title = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var categoryID = 0
    @State private var accountID = 0
    @State private var day = min(Calendar.current.component(.day, from: .now), 28)
    @State private var saving = false
    @State private var error: String?

    private var availableCategories: [FinanceCategory] {
        categories.filter { $0.type.lowercased() == type }
    }
    private var activeAccounts: [FinancialAccount] { accounts.filter { !$0.archived } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Movimiento periódico") {
                    TextField("Nombre (ej. arriendo)", text: $title)
                    Picker("Tipo", selection: $type) {
                        Text("Gasto").tag("expense")
                        Text("Ingreso").tag("income")
                    }.pickerStyle(.segmented)
                    COPAmountField("Monto COP", text: $amount)
                    Picker("Categoría", selection: $categoryID) {
                        Text("Seleccionar").tag(0)
                        ForEach(availableCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    Picker("Billetera (opcional)", selection: $accountID) {
                        Text("Sin billetera").tag(0)
                        ForEach(activeAccounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Picker("Día del mes", selection: $day) {
                        ForEach(1...28, id: \.self) { value in
                            Text("Día \(value)").tag(value)
                        }
                    }
                }
                Section {
                    Text("El servidor registra la operación únicamente cuando vence. Puedes pausarla o eliminarla después.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { ErrorBanner(message: error) }
                Button {
                    Task { await save() }
                } label: {
                    HStack { Spacer(); if saving { ProgressView() } else { Text("Guardar recurrencia") }; Spacer() }
                }.disabled(saving)
            }
            .navigationTitle("Nueva recurrencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear { categoryID = availableCategories.first?.id ?? 0 }
            .onChange(of: type) { _, _ in categoryID = availableCategories.first?.id ?? 0 }
        }
    }

    private func save() async {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(cleaned.count),
              availableCategories.contains(where: { $0.id == categoryID }),
              let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0, value <= 999_999_999_999.99 else {
            error = "Revisa nombre, categoría y monto positivo."
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await onSave(CreateRecurringRule(title: cleaned, amount: value,
                                                  type: type, categoryId: categoryID,
                                                  accountId: accountID == 0 ? nil : accountID,
                                                  dayOfMonth: day))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
