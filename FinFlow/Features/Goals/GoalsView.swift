import SwiftUI

struct GoalsView: View {
    @State private var goals: [FinanceGoal] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingForm = false
    @State private var editingGoal: FinanceGoal?
    @State private var fundingGoal: FinanceGoal?
    @State private var fundAmount = ""
    @State private var isFunding = false

    var body: some View {
        NavigationStack {
            ScreenBackground {
                ScrollView {
                    VStack(spacing: 14) {
                        if let error { ErrorBanner(message: error) }
                        if isLoading { ProgressView().padding(40) }
                        else if goals.isEmpty { EmptyState(icon: "scope", title: "Sin metas todavía", message: "Define un objetivo y convierte tus planes en algo medible.") }
                        ForEach(goals) { goal in goalCard(goal) }
                    }.padding(16)
                }.refreshable { await load() }
            }
            .navigationTitle("Metas financieras")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editingGoal = nil; showingForm = true } label: { Image(systemName: "plus.circle.fill") } } }
            .task { await load() }
            .sheet(isPresented: $showingForm, onDismiss: { Task { await load() } }) { GoalFormView(goal: editingGoal) }
            .alert("Agregar fondos", isPresented: Binding(get: { fundingGoal != nil }, set: { if !$0 { fundingGoal = nil } })) {
                TextField("Monto en COP", text: $fundAmount).keyboardType(.decimalPad)
                Button("Cancelar", role: .cancel) { fundingGoal = nil }
                Button("Agregar") { Task { await addFunds() } }
            } message: { Text("¿Cuánto quieres aportar a esta meta?") }
        }
    }
    private func goalCard(_ goal: FinanceGoal) -> some View {
        SectionCard(title: "\(goal.icon ?? "🎯")  \(goal.name)", subtitle: goal.deadline.isEmpty ? nil : "Fecha objetivo: \(goal.deadline)") {
            HStack(alignment: .firstTextBaseline) { Text(CurrencyFormatter.format(goal.currentAmount)).font(.title3.bold()).foregroundStyle(FinFlowTheme.mint); Spacer(); Text("de \(CurrencyFormatter.format(goal.targetAmount))").font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
            GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(FinFlowTheme.elevated); Capsule().fill(FinFlowTheme.accent).frame(width: proxy.size.width * goal.progress) } }.frame(height: 8)
            HStack { Text("\(Int(goal.progress * 100))% completado").font(.caption).foregroundStyle(FinFlowTheme.secondaryText); Spacer(); Menu { Button("Agregar fondos", systemImage: "plus.circle") { fundingGoal = goal; fundAmount = "" }; Button("Editar", systemImage: "pencil") { editingGoal = goal; showingForm = true }; Button("Eliminar", systemImage: "trash", role: .destructive) { Task { await delete(goal) } } } label: { Image(systemName: "ellipsis.circle").font(.title3) } }
            if let description = goal.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
        }
    }
    private func load() async { isLoading = true; defer { isLoading = false }; do { goals = try await APIClient.shared.request("/goals"); error = nil } catch { self.error = error.localizedDescription } }
    private func delete(_ goal: FinanceGoal) async {
        do { try await APIClient.shared.perform("/goals/\(goal.id)", method: "DELETE"); goals.removeAll { $0.id == goal.id } } catch { error = error.localizedDescription }
    }
    private func addFunds() async {
        guard let goal = fundingGoal, let amount = Double(fundAmount.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        isFunding = true; defer { isFunding = false }
        do { let updated: FinanceGoal = try await APIClient.shared.request("/goals/\(goal.id)/contribute", method: "PATCH", body: AmountRequest(amount: amount)); if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = updated }; fundingGoal = nil }
        catch { error = error.localizedDescription; fundingGoal = nil }
    }
}
struct AmountRequest: Encodable { let amount: Double }

struct GoalFormView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: FinanceGoal?
    @State private var name = ""
    @State private var target = ""
    @State private var current = "0"
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo") { TextField("Nombre de la meta", text: $name); TextField("Monto objetivo (COP)", text: $target).keyboardType(.decimalPad); TextField("Monto ahorrado (COP)", text: $current).keyboardType(.decimalPad); DatePicker("Fecha objetivo", selection: $deadline, displayedComponents: .date); TextField("Descripción (opcional)", text: $description, axis: .vertical) }
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await save() } } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("Guardar meta") }; Spacer() } }.disabled(isSaving)
            }.navigationTitle(goal == nil ? "Nueva meta" : "Editar meta").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
        }.onAppear { if let goal { name = goal.name; target = String(goal.targetAmount); current = String(goal.currentAmount); deadline = DateFormatters.parse(goal.deadline) ?? .now; description = goal.description ?? "" } }
    }
    private func save() async {
        guard !name.isEmpty, let targetValue = Double(target.replacingOccurrences(of: ",", with: ".")), targetValue > 0, let currentValue = Double(current.replacingOccurrences(of: ",", with: ".")) else { error = "Revisa el nombre y los montos de la meta."; return }
        isSaving = true; defer { isSaving = false }
        let dto = GoalRequest(title: name, targetAmount: targetValue, currentAmount: currentValue, deadline: DateFormatters.isoDay.string(from: deadline), description: description.isEmpty ? nil : description)
        do { if let goal { let _: FinanceGoal = try await APIClient.shared.request("/goals/\(goal.id)", method: "PUT", body: dto) } else { let _: FinanceGoal = try await APIClient.shared.request("/goals", method: "POST", body: dto) }; dismiss() } catch { self.error = error.localizedDescription }
    }
}
