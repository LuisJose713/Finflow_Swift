import SwiftUI

struct GoalsView: View {
    @State private var goals: [FinanceGoal] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingForm = false
    @State private var editingGoal: FinanceGoal?
    @State private var historyGoal: FinanceGoal?
    @State private var fundingGoal: FinanceGoal?
    @State private var fundAmount = ""
    @State private var isFunding = false

    var body: some View {
        NavigationStack {
            ScreenBackground {
                ScrollView {
                    VStack(spacing: 14) {
                        PresentationCard(cardID: "goals.intro", eyebrow: "Tu futuro financiero", title: "Los grandes planes empiezan hoy.", detail: "Haz seguimiento a cada objetivo y celebra tus avances.", symbol: "scope")
                        if let error { ErrorBanner(message: error) }
                        if isLoading { ProgressView().padding(40) }
                        else if goals.isEmpty { EmptyState(icon: "scope", title: "Sin metas todavía", message: "Define un objetivo y convierte tus planes en algo medible.") }
                        ForEach(goals) { goal in goalCard(goal) }
                    }.padding(16)
                }.refreshable { await load() }
            }
            .navigationTitle("Metas financieras")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editingGoal = nil; showingForm = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Nueva meta").accessibilityIdentifier("goals.add") } }
            .task { await load() }
            .sheet(isPresented: $showingForm, onDismiss: { Task { await load() } }) { GoalFormView(goal: editingGoal) }
            .sheet(item: $historyGoal) { goal in GoalHistoryView(goal: goal) }
            .sheet(item: $fundingGoal) { goal in
                NavigationStack {
                    Form {
                        Section(goal.name) {
                            COPAmountField("Monto del aporte", text: $fundAmount)
                            Text("El aporte se registra en pesos colombianos.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let error { ErrorBanner(message: error) }
                    }
                    .navigationTitle("Agregar fondos")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { fundingGoal = nil }.disabled(isFunding)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Agregar") { Task { await addFunds() } }
                                .disabled(isFunding || (Double(fundAmount) ?? 0) <= 0)
                        }
                    }
                    .interactiveDismissDisabled(isFunding)
                }
            }
        }
    }
    private func goalCard(_ goal: FinanceGoal) -> some View {
        SectionCard(title: "\(goal.icon ?? "🎯")  \(goal.name)", subtitle: goal.deadline.isEmpty ? nil : "Fecha objetivo: \(goal.deadline)") {
            HStack(alignment: .firstTextBaseline) { Text(CurrencyFormatter.format(goal.currentAmount)).font(.title3.bold()).foregroundStyle(FinFlowTheme.mint); Spacer(); Text("de \(CurrencyFormatter.format(goal.targetAmount))").font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
            GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(FinFlowTheme.elevated); Capsule().fill(FinFlowTheme.accent).frame(width: proxy.size.width * goal.progress) } }.frame(height: 8)
            HStack { Text("\(Int(goal.progress * 100))% completado").font(.caption).foregroundStyle(FinFlowTheme.secondaryText); Spacer(); Menu { if goal.status == "active" { Button("Agregar fondos", systemImage: "plus.circle") { fundingGoal = goal; fundAmount = "" } }; Button("Historial de aportes", systemImage: "clock.arrow.circlepath") { historyGoal = goal }; Button("Editar", systemImage: "pencil") { editingGoal = goal; showingForm = true }; if goal.status == "active" { Button("Marcar completada", systemImage: "checkmark.circle") { Task { await setStatus(goal, "completed") } }; Button("Cancelar meta", systemImage: "xmark.circle") { Task { await setStatus(goal, "cancelled") } } } else { Button("Reactivar meta", systemImage: "arrow.counterclockwise") { Task { await setStatus(goal, "active") } } }; Button("Eliminar", systemImage: "trash", role: .destructive) { Task { await delete(goal) } } } label: { Image(systemName: "ellipsis.circle").font(.title3) } }
            if let description = goal.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
        }
    }
    private func load() async { isLoading = true; defer { isLoading = false }; do { goals = try await APIClient.shared.request("/goals"); error = nil } catch { self.error = error.localizedDescription } }
    private func delete(_ goal: FinanceGoal) async {
        do { try await APIClient.shared.perform("/goals/\(goal.id)", method: "DELETE"); goals.removeAll { $0.id == goal.id } } catch { self.error = error.localizedDescription }
    }
    private func setStatus(_ goal: FinanceGoal, _ status: String) async {
        do {
            let _: FinanceGoal = try await APIClient.shared.request("/goals/\(goal.id)/status", method: "PATCH", body: GoalStatusChange(status: status))
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func addFunds() async {
        guard let goal = fundingGoal, goal.status == "active", let amount = Double(fundAmount.replacingOccurrences(of: ",", with: ".")), amount.isFinite, amount > 0, amount <= goal.targetAmount - goal.currentAmount else { error = "Ingresa un aporte válido que no supere el saldo pendiente."; fundingGoal = nil; return }
        isFunding = true; defer { isFunding = false }
        do { let updated: FinanceGoal = try await APIClient.shared.request("/goals/\(goal.id)/contribute", method: "PATCH", body: AmountRequest(amount: amount)); if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = updated }; fundingGoal = nil }
        catch { self.error = error.localizedDescription; fundingGoal = nil }
    }
}
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
                Section("Objetivo") { TextField("Nombre de la meta", text: $name); COPAmountField("Monto objetivo (COP)", text: $target); if goal == nil { COPAmountField("Ahorro inicial (COP)", text: $current) } else { LabeledContent("Ahorro acumulado", value: CurrencyFormatter.format(goal?.currentAmount ?? 0)) }; DatePicker("Fecha objetivo", selection: $deadline, displayedComponents: .date); TextField("Descripción (opcional)", text: $description, axis: .vertical) }
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await save() } } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("Guardar meta") }; Spacer() } }.disabled(isSaving)
            }.navigationTitle(goal == nil ? "Nueva meta" : "Editar meta").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() }.disabled(isSaving) } }
                .interactiveDismissDisabled(isSaving)
                .modifier(FinFlowKeyboardDismiss())
        }.onAppear { if let goal { name = goal.name; target = String(goal.targetAmount); current = String(goal.currentAmount); deadline = DateFormatters.parse(goal.deadline) ?? .now; description = goal.description ?? "" } }
    }
    private func save() async {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2, let targetValue = Double(target.replacingOccurrences(of: ",", with: ".")), targetValue.isFinite, targetValue > 0, let currentValue = Double(current.replacingOccurrences(of: ",", with: ".")), currentValue.isFinite, currentValue >= 0, currentValue <= targetValue, (goal == nil || targetValue >= (goal?.currentAmount ?? 0)) else { error = "Revisa el nombre y los montos de la meta."; return }
        isSaving = true; defer { isSaving = false }
        let dto = GoalRequest(title: name, targetAmount: targetValue, currentAmount: goal == nil ? currentValue : nil, deadline: DateFormatters.isoDay.string(from: deadline), description: description.isEmpty ? nil : description)
        do { if let goal { let _: FinanceGoal = try await APIClient.shared.request("/goals/\(goal.id)", method: "PUT", body: dto) } else { let _: FinanceGoal = try await APIClient.shared.request("/goals", method: "POST", body: dto) }; dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct GoalHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: FinanceGoal
    @State private var contributions: [GoalContribution] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenBackground {
                List {
                    Section {
                        LabeledContent("Meta", value: goal.name)
                        LabeledContent("Ahorro actual", value: CurrencyFormatter.format(goal.currentAmount))
                    }
                    if let error { Section { ErrorBanner(message: error) } }
                    if isLoading {
                        ProgressView("Cargando aportes…")
                    } else if contributions.isEmpty {
                        ContentUnavailableView("Sin aportes registrados",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Los aportes que realices aparecerán aquí."))
                    } else {
                        Section("Aportes registrados") {
                            ForEach(contributions) { contribution in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(CurrencyFormatter.format(contribution.amount)).font(.headline)
                                        Spacer()
                                        Text(contribution.createdAt?.prefix(10) ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let note = contribution.note, !note.isEmpty {
                                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Historial de aportes")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contributions = try await APIClient.shared.request("/goals/\(goal.id)/contributions")
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
