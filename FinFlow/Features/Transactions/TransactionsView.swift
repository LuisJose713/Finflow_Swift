import SwiftUI

struct TransactionsView: View {
    @State private var transactions: [FinanceTransaction] = []
    @State private var categories: [FinanceCategory] = []
    @State private var search = ""
    @State private var typeFilter = "all"
    @State private var selectedMonth = 0
    @State private var selectedYear = 0
    @State private var selectedCategory = 0
    @State private var error: String?
    @State private var isLoading = true
    @State private var showingCreate = false
    @State private var exportURL: URL?
    @State private var showingShare = false

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
                    if isLoading { LoadingView() }
                    else if filtered.isEmpty { EmptyState(icon: "arrow.left.arrow.right", title: "Sin movimientos", message: "Prueba otros filtros o agrega tu primera transacción.") }
                    else {
                        List {
                            ForEach(filtered) { tx in TransactionRow(transaction: tx).listRowBackground(FinFlowTheme.surface).swipeActions {
                                Button(role: .destructive) { Task { await delete(tx) } } label: { Label("Eliminar", systemImage: "trash") }
                            } }
                        }.scrollContentBackground(.hidden).listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Movimientos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Menu { Button("Exportar PDF", systemImage: "doc.richtext") { Task { await export("pdf") } }; Button("Exportar CSV", systemImage: "tablecells") { Task { await export("csv") } } } label: { Image(systemName: "square.and.arrow.up") } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingCreate = true } label: { Image(systemName: "plus.circle.fill") } }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await load() } }) { CreateTransactionView(categories: categories) }
            .sheet(isPresented: $showingShare) { if let exportURL { ShareSheet(items: [exportURL]) } }
        }
    }
    private var yearOptions: [Int] { Array(Set(transactions.map { Calendar.current.component(.year, from: $0.parsedDate) })).sorted(by: >) }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        let userID = Int(TokenStore.shared.read("userId") ?? "0") ?? 0
        do {
            await OfflineTransactionStore.shared.synchronize(userID: userID)
            async let txs: [FinanceTransaction] = APIClient.shared.request("/transactions")
            async let cats: [FinanceCategory] = APIClient.shared.request("/categories")
            let serverTransactions = try await txs
            categories = (try? await cats) ?? []
            // Keep local optimistic writes that are still waiting to sync.
            let pendingLocal = OfflineTransactionStore.shared.cachedTransactions(userID: userID).filter { $0.id < 0 }
            let pendingDeletes = OfflineTransactionStore.shared.pendingDeleteIDs(userID: userID)
            transactions = pendingLocal + serverTransactions.filter { remote in
                !pendingDeletes.contains(remote.id) && !pendingLocal.contains(where: { $0.id == remote.id })
            }
            OfflineTransactionStore.shared.saveTransactions(transactions, userID: userID)
            error = OfflineTransactionStore.shared.hasPendingOperations(userID: userID) ? "Hay cambios pendientes de sincronizar. Se reintentará al actualizar." : nil
        } catch {
            transactions = OfflineTransactionStore.shared.cachedTransactions(userID: userID)
            self.error = transactions.isEmpty ? error.localizedDescription : "Sin conexión. Mostrando movimientos guardados en este dispositivo."
        }
    }
    private func delete(_ tx: FinanceTransaction) async {
        let userID = Int(TokenStore.shared.read("userId") ?? "0") ?? 0
        do {
            if tx.id < 0 {
                OfflineTransactionStore.shared.queueDelete(transaction: tx, userID: userID)
            } else {
                try await APIClient.shared.perform("/transactions/\(tx.id)", method: "DELETE")
                OfflineTransactionStore.shared.removeFromCache(id: tx.id, userID: userID)
            }
            transactions.removeAll { $0.id == tx.id }
        } catch {
            guard OfflineTransactionStore.isConnectivityError(error) else { self.error = error.localizedDescription; return }
            OfflineTransactionStore.shared.queueDelete(transaction: tx, userID: userID)
            transactions.removeAll { $0.id == tx.id }
            self.error = "Eliminación guardada. Se sincronizará cuando vuelva la conexión."
        }
    }
    private func export(_ kind: String) async {
        do {
            var query: [String: String] = [:]
            if typeFilter != "all" { query["type"] = typeFilter }
            if selectedMonth != 0 { query["month"] = String(selectedMonth) }
            if selectedYear != 0 { query["year"] = String(selectedYear) }
            if selectedCategory != 0 { query["categoryId"] = String(selectedCategory) }
            if !search.isEmpty { query["search"] = search }
            let data = try await APIClient.shared.download("/transactions/export/\(kind)", query: query)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("transacciones_finflow.\(kind)")
            try data.write(to: url); exportURL = url; showingShare = true
        } catch { self.error = error.localizedDescription }
    }
}
struct EmptyResponse: Decodable {}

struct CreateTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [FinanceCategory]
    @State private var description = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var categoryId = 0
    @State private var date = Date()
    @State private var isSaving = false
    @State private var error: String?
    private var suitableCategories: [FinanceCategory] { categories.filter { $0.type.lowercased() == (type == "income" ? "income" : "expense") } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Movimiento") {
                    Picker("Tipo", selection: $type) { Text("Gasto").tag("expense"); Text("Ingreso").tag("income") }.pickerStyle(.segmented)
                    TextField("Descripción", text: $description)
                    TextField("Monto en COP", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    if !suitableCategories.isEmpty { Picker("Categoría", selection: $categoryId) { ForEach(suitableCategories) { Text($0.name).tag($0.id) } } }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button { Task { await save() } } label: { if isSaving { ProgressView() } else { Text("Guardar movimiento").frame(maxWidth: .infinity) } }.disabled(isSaving) }
            }
            .scrollContentBackground(.hidden).background(FinFlowTheme.background)
            .navigationTitle("Nuevo movimiento").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear { if categoryId == 0 { categoryId = suitableCategories.first?.id ?? 0 } }
            .onChange(of: type) { _, newType in categoryId = categories.first(where: { $0.type.lowercased() == newType })?.id ?? 0 }
        }
    }
    private func save() async {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty, let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { error = "Ingresa una descripción y un monto válido."; return }
        isSaving = true; defer { isSaving = false }
        let dto = CreateTransactionRequest(description: description, amount: value, type: type, categoryId: categoryId, date: DateFormatters.isoDay.string(from: date), notes: nil)
        do {
            let _: FinanceTransaction = try await APIClient.shared.request("/transactions", method: "POST", body: dto)
            dismiss()
        } catch {
            guard OfflineTransactionStore.isConnectivityError(error),
                  let userID = Int(TokenStore.shared.read("userId") ?? "") else {
                self.error = error.localizedDescription
                return
            }
            _ = OfflineTransactionStore.shared.addPendingCreate(dto, userID: userID)
            dismiss()
        }
    }
}
