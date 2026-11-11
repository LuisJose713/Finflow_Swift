import SwiftUI

struct TransactionsView: View {
    @State private var transactions: [FinanceTransaction] = []
    @State private var categories: [FinanceCategory] = []
    @State private var accounts: [FinancialAccount] = []
    @State private var search = ""
    @State private var typeFilter = "all"
    @State private var selectedMonth = 0
    @State private var selectedYear = 0
    @State private var selectedCategory = 0
    @State private var error: String?
    @State private var isLoading = true
    @State private var showingCreate = false
    @State private var editingTransaction: FinanceTransaction?
    @State private var deletingTransaction: FinanceTransaction?
    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var isExporting = false
    @State private var isVisible = false
    @State private var exportOperation = UUID()

    private var filtered: [FinanceTransaction] {
        transactions.filter { tx in
            (typeFilter == "all" || tx.type.lowercased() == typeFilter) && (search.isEmpty || tx.description.localizedCaseInsensitiveContains(search)) && (selectedMonth == 0 || Calendar.current.component(.month, from: tx.parsedDate) == selectedMonth) && (selectedYear == 0 || Calendar.current.component(.year, from: tx.parsedDate) == selectedYear) && (selectedCategory == 0 || tx.categoryId == selectedCategory)
        }.sorted { $0.parsedDate > $1.parsedDate }
    }
    var body: some View {
        NavigationStack {
            ScreenBackground {
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        HStack { Image(systemName: "magnifyingglass").foregroundStyle(FinFlowTheme.secondaryText); TextField("Buscar movimiento", text: $search) }
                            .padding(12).background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        HStack {
                            Picker("Tipo", selection: $typeFilter) { Text("Todos").tag("all"); Text("Ingresos").tag("income"); Text("Gastos").tag("expense") }.pickerStyle(.segmented)
                        }
                        HStack {
                            Picker("Mes", selection: $selectedMonth) { Text("Todos los meses").tag(0); ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }.tint(FinFlowTheme.accent)
                            Picker("Año", selection: $selectedYear) { Text("Todos los años").tag(0); ForEach(yearOptions, id: \.self) { Text(String($0)).tag($0) } }.tint(FinFlowTheme.accent)
                        }.font(.caption)
                        if !categories.isEmpty {
                            Picker("Categoría", selection: $selectedCategory) {
                                Text("Todas las categorías").tag(0)
                                ForEach(categories) { Text($0.name).tag($0.id) }
                            }.tint(FinFlowTheme.accent)
                        }
                    }.padding(.horizontal, 16)
                    if let error { ErrorBanner(message: error).padding(.horizontal, 16) }
                    if isExporting { ProgressView("Preparando archivo…") }
                    if isLoading { LoadingView() }
                    else if filtered.isEmpty { EmptyState(icon: "arrow.left.arrow.right", title: "Sin movimientos", message: "Prueba otros filtros o agrega tu primera transacción.") }
                    else {
                        List {
                            ForEach(filtered) { tx in TransactionRow(transaction: tx).listRowBackground(FinFlowTheme.surface).swipeActions {
                                Button("Editar", systemImage: "pencil") { editingTransaction = tx }.tint(FinFlowTheme.accent)
                                Button(role: .destructive) { deletingTransaction = tx } label: { Label("Eliminar", systemImage: "trash") }
                            } }
                        }.scrollContentBackground(.hidden).listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Movimientos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Menu { Button("Exportar PDF", systemImage: "doc.richtext") { Task { await export("pdf") } }; Button("Exportar CSV", systemImage: "tablecells") { Task { await export("csv") } } } label: { Image(systemName: "square.and.arrow.up") }.disabled(isExporting || showingShare) }
                ToolbarItem(placement: .topBarTrailing) { Button { showingCreate = true } label: { Image(systemName: "plus.circle.fill") } }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await load() } }) { CreateTransactionView(categories: categories, accounts: accounts) }
            .sheet(item: $editingTransaction, onDismiss: { Task { await load() } }) { transaction in
                CreateTransactionView(categories: categories, accounts: accounts, editing: transaction)
            }
            .confirmationDialog("¿Eliminar este movimiento?", isPresented: Binding(
                get: { deletingTransaction != nil }, set: { if !$0 { deletingTransaction = nil } }
            ), titleVisibility: .visible) {
                Button("Eliminar definitivamente", role: .destructive) {
                    if let tx = deletingTransaction { Task { await delete(tx); deletingTransaction = nil } }
                }
                Button("Cancelar", role: .cancel) { deletingTransaction = nil }
            } message: { Text("Esta acción modifica tus datos financieros y no se puede deshacer.") }
            .sheet(isPresented: $showingShare, onDismiss: removeTemporaryExport) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .onAppear { isVisible = true }
            .onDisappear {
                isVisible = false
                exportOperation = UUID()
                isExporting = false
                if !showingShare { removeTemporaryExport() }
            }
        }
    }
    private var yearOptions: [Int] { Array(Set(transactions.map { Calendar.current.component(.year, from: $0.parsedDate) })).sorted(by: >) }
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let userID = Int(TokenStore.shared.read("userId") ?? "0") ?? 0
        do {
            async let remote: [FinanceTransaction] = APIClient.shared.request("/transactions")
            async let cats: [FinanceCategory] = APIClient.shared.request("/categories")
            async let wallets: [FinancialAccount] = APIClient.shared.request("/accounts")
            let server = try await remote
            categories = try await cats
            accounts = (try? await wallets) ?? []
            transactions = server
            // Preserve old pending optimistic entries for explicit manual review;
            // never auto-post them after an ambiguous timeout.
            let legacyPending = OfflineTransactionStore.shared.cachedTransactions(userID: userID)
                .filter { $0.id < 0 }
            OfflineTransactionStore.shared.saveTransactions(legacyPending + server, userID: userID)
            self.error = OfflineTransactionStore.shared.hasPendingOperations(userID: userID)
                ? "Hay operaciones pendientes de una versión anterior. Por seguridad no se reenviarán automáticamente: comprueba los registros antes de introducirlos otra vez."
                : nil
        } catch {
            transactions = OfflineTransactionStore.shared.cachedTransactions(userID: userID)
                .filter { $0.id > 0 }
            self.error = transactions.isEmpty
                ? error.localizedDescription
                : "Sin conexión. Mostrando una copia cifrada de tus movimientos. Para registrar cambios debes conectarte."
        }
    }
    private func delete(_ tx: FinanceTransaction) async {
        let userID = Int(TokenStore.shared.read("userId") ?? "0") ?? 0
        do {
            try await APIClient.shared.perform("/transactions/\(tx.id)", method: "DELETE")
            OfflineTransactionStore.shared.removeFromCache(id: tx.id, userID: userID)
            transactions.removeAll { $0.id == tx.id }
        } catch {
            // Never report a deletion as complete when the server could not confirm it.
            self.error = "No se confirmó la eliminación. Comprueba tu conexión y vuelve a cargar los movimientos."
        }
    }
    private func removeTemporaryExport() {
        guard let exportURL else { return }
        try? FileManager.default.removeItem(at: exportURL)
        self.exportURL = nil
    }

    @MainActor private func export(_ kind: String) async {
        guard isVisible, !isExporting, !showingShare,
              let token = TokenStore.shared.read("token"), !token.isEmpty else { return }
        let operation = UUID()
        exportOperation = operation
        isExporting = true
        defer { if exportOperation == operation { isExporting = false } }
        do {
            var query: [String: String] = [:]
            if typeFilter != "all" { query["type"] = typeFilter }
            if selectedMonth != 0 { query["month"] = String(selectedMonth) }
            if selectedYear != 0 { query["year"] = String(selectedYear) }
            if selectedCategory != 0 { query["categoryId"] = String(selectedCategory) }
            if !search.isEmpty { query["search"] = search }
            let data = try await APIClient.shared.download("/transactions/export/\(kind)", query: query)
            // A download started before navigation or logout must not persist
            // the previous session's financial report after it completes.
            guard isVisible, exportOperation == operation,
                  TokenStore.shared.read("token") == token else { return }
            removeTemporaryExport()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("transacciones_finflow_\(UUID().uuidString).\(kind)")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
            showingShare = true
        } catch {
            guard isVisible, exportOperation == operation,
                  TokenStore.shared.read("token") == token else { return }
            self.error = error.localizedDescription
        }
    }
}
struct EmptyResponse: Decodable {}

struct CreateTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [FinanceCategory]
    let accounts: [FinancialAccount]
    var editing: FinanceTransaction? = nil
    var initialType = "expense"
    var accountNotice: String? = nil
    @State private var description = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var categoryId = 0
    @State private var accountId = 0
    @State private var date = Date()
    @State private var isSaving = false
    @State private var error: String?
    private var suitableCategories: [FinanceCategory] { categories.filter { $0.type.lowercased() == (type == "income" ? "income" : "expense") } }
    var body: some View {
        NavigationStack {
            Form {
                if let accountNotice {
                    Section { Text(accountNotice).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Movimiento") {
                    Picker("Tipo", selection: $type) { Text("Gasto").tag("expense"); Text("Ingreso").tag("income") }.pickerStyle(.segmented)
                    TextField("Descripción", text: $description)
                    TextField("Monto en COP", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    if !suitableCategories.isEmpty { Picker("Categoría", selection: $categoryId) { ForEach(suitableCategories) { Text($0.name).tag($0.id) } } }
                    if !accounts.filter({ !$0.archived }).isEmpty { Picker("Billetera", selection: $accountId) { Text("Sin billetera").tag(0); ForEach(accounts.filter { !$0.archived }) { Text($0.name).tag($0.id) } } }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button { Task { await save() } } label: { if isSaving { ProgressView() } else { Text(editing == nil ? "Guardar movimiento" : "Guardar cambios").frame(maxWidth: .infinity) } }.disabled(isSaving) }
            }
            .scrollContentBackground(.hidden).background(FinFlowTheme.background)
            .navigationTitle(editing == nil ? "Nuevo movimiento" : "Editar movimiento").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() }.disabled(isSaving) } }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if let editing {
                    description = editing.description
                    amount = String(editing.amount)
                    type = editing.type
                    categoryId = editing.categoryId
                    accountId = editing.accountId ?? 0
                    date = editing.parsedDate
                } else if categoryId == 0 {
                    type = initialType == "income" ? "income" : "expense"
                    categoryId = suitableCategories.first?.id ?? 0
                }
            }
            .onChange(of: type) { _, newType in categoryId = categories.first(where: { $0.type.lowercased() == newType })?.id ?? 0 }
        }
    }
    private func save() async {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty, suitableCategories.contains(where: { $0.id == categoryId }), let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { error = "Ingresa una descripción y un monto válido."; return }
        isSaving = true; defer { isSaving = false }
        var dto = CreateTransactionRequest(description: description, amount: value, type: type, categoryId: categoryId, date: DateFormatters.isoDay.string(from: date), notes: nil)
        dto.accountId = accountId == 0 ? nil : accountId
        do {
            let path = editing.map { "/transactions/\($0.id)" } ?? "/transactions"
            let method = editing == nil ? "POST" : "PUT"
            let _: FinanceTransaction = try await APIClient.shared.request(path, method: method, body: dto)
            dismiss()
        } catch {
            self.error = OfflineTransactionStore.isConnectivityError(error)
                ? "No pudimos confirmar si el movimiento llegó al servidor. No se reintentará automáticamente para evitar duplicados. Comprueba la lista cuando vuelva Internet."
                : error.localizedDescription
        }
    }
}
