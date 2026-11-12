import SwiftUI

struct AccountsView: View {
    @State private var accounts: [FinancialAccount] = []
    @State private var transfers: [FinancialTransfer] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: FinancialAccount?
    @State private var showAccountEditor = false
    @State private var showTransferEditor = false
    @State private var archiving: FinancialAccount?
    private var active: [FinancialAccount] { accounts.filter { !$0.archived } }
    private var balance: Double { active.reduce(0) { $0 + $1.balance } }

    var body: some View {
        ScreenBackground {
            ScrollView {
                LazyVStack(spacing: 16) {
                        PresentationCard(cardID: "accounts.intro", eyebrow: "Cuentas y billeteras", title: "Cada cuenta, en su lugar.", detail: "Organiza tus billeteras y conoce tu saldo disponible.", symbol: "wallet.pass")
                    if let error { ErrorBanner(message: error) }
                    SectionCard(title: "Saldo en tus cuentas", subtitle: "Billeteras y bancos en pesos colombianos") {
                        Text(CurrencyFormatter.format(balance))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65).lineLimit(1)
                        Text("Los saldos se calculan en el servidor, no en este dispositivo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if loading { ProgressView("Cargando billeteras…").padding(28) }
                    else if accounts.isEmpty {
                        EmptyState(icon: "wallet.pass", title: "Sin billeteras",
                                   message: "Registra una cuenta bancaria, una billetera de efectivo o tus ahorros.")
                    } else {
                        ForEach(accounts) { account in
                            SectionCard(title: account.name, subtitle: label(account.type) + (account.archived ? " · Archivada" : "")) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Saldo actual").font(.caption).foregroundStyle(.secondary)
                                        Text(CurrencyFormatter.format(account.balance))
                                            .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Editar", systemImage: "pencil") {
                                            editing = account
                                            showAccountEditor = true
                                        }
                                        Button(account.archived ? "Restaurar" : "Archivar",
                                               systemImage: account.archived ? "tray.and.arrow.up" : "archivebox") {
                                            archiving = account
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                                }
                                Text("Saldo inicial: \(CurrencyFormatter.format(account.openingBalance))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !transfers.isEmpty {
                            SectionCard(title: "Transferencias recientes", subtitle: "Movimientos entre tus billeteras") {
                                ForEach(transfers.prefix(20)) { transfer in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(name(transfer.fromAccountId)) → \(name(transfer.toAccountId))")
                                            .font(.subheadline.weight(.semibold))
                                        HStack {
                                            Text(transfer.date).font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            Text(CurrencyFormatter.format(transfer.amount)).font(.subheadline.bold())
                                        }
                                        if let note = transfer.note, !note.isEmpty {
                                            Text(note).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if transfer.id != transfers.prefix(20).last?.id { Divider() }
                                    }.padding(.vertical, 3)
                                }
                            }
                        }
                    }
                }.padding(16)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Cuentas y billeteras")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Nueva billetera", systemImage: "plus") {
                        editing = nil; showAccountEditor = true
                    }
                    Button("Transferir fondos", systemImage: "arrow.left.arrow.right") {
                        showTransferEditor = true
                    }.disabled(active.count < 2)
                } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAccountEditor, onDismiss: { Task { await load() } }) {
            FinancialAccountEditor(account: editing) { name, type, opening in
                if let editing {
                    let _: FinancialAccount = try await APIClient.shared.request(
                        "/accounts/\(editing.id)", method: "PUT",
                        body: UpdateFinancialAccount(name: name, type: type))
                } else {
                    let _: FinancialAccount = try await APIClient.shared.request(
                        "/accounts", method: "POST",
                        body: CreateFinancialAccount(name: name, type: type, openingBalance: opening))
                }
            }
        }
        .sheet(isPresented: $showTransferEditor, onDismiss: { Task { await load() } }) {
            FinancialTransferEditor(accounts: active) { request in
                let _: FinancialTransfer = try await APIClient.shared.request(
                    "/accounts/transfers", method: "POST", body: request)
            }
        }
        .confirmationDialog("¿Cambiar el estado de esta billetera?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }
        ), titleVisibility: .visible) {
            Button(archiving?.archived == true ? "Restaurar" : "Archivar") {
                if let account = archiving { Task { await archive(account) } }
            }
            Button("Cancelar", role: .cancel) { archiving = nil }
        } message: {
            Text("Archivar evita nuevas operaciones, pero conserva tus movimientos.")
        }
    }

    private func label(_ type: String) -> String {
        ["cash": "Efectivo", "bank": "Banco", "savings": "Ahorro", "other": "Otra"].first { $0.key == type }?.value ?? "Cuenta"
    }
    private func name(_ id: Int) -> String { accounts.first { $0.id == id }?.name ?? "Cuenta \(id)" }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let loadedAccounts: [FinancialAccount] = APIClient.shared.request("/accounts")
            async let loadedTransfers: [FinancialTransfer] = APIClient.shared.request("/accounts/transfers")
            accounts = try await loadedAccounts
            transfers = try await loadedTransfers
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func archive(_ account: FinancialAccount) async {
        defer { archiving = nil }
        do {
            let _: FinancialAccount = try await APIClient.shared.request(
                "/accounts/\(account.id)/archive", method: "PATCH",
                body: ArchiveFinancialAccount(archived: !account.archived))
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct FinancialAccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    let account: FinancialAccount?
    let onSave: (String, String, Double) async throws -> Void
    @State private var name = ""
    @State private var type = "bank"
    @State private var openingBalance = "0"
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    TextField("Nombre", text: $name)
                    Picker("Tipo", selection: $type) {
                        Text("Efectivo").tag("cash")
                        Text("Banco").tag("bank")
                        Text("Ahorro").tag("savings")
                        Text("Otra").tag("other")
                    }
                    if account == nil {
                        COPAmountField("Saldo inicial COP", text: $openingBalance)
                    } else {
                        LabeledContent("Saldo inicial", value: CurrencyFormatter.format(account?.openingBalance ?? 0))
                        Text("Para mantener la trazabilidad, no se modifica el saldo inicial después de crear la cuenta.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { ErrorBanner(message: error) }
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() } else { Text("Guardar cuenta") }
                        Spacer()
                    }
                }.disabled(saving)
            }
            .navigationTitle(account == nil ? "Nueva billetera" : "Editar billetera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear {
                if let account {
                    name = account.name
                    type = account.type
                    openingBalance = String(account.openingBalance)
                }
            }
        }
    }
    private func save() async {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(cleaned.count),
              let amount = Double(openingBalance.replacingOccurrences(of: ",", with: ".")),
              amount.isFinite, amount >= 0, amount <= 999_999_999_999.99 else {
            error = "Escribe un nombre y un saldo inicial válido."
            return
        }
        saving = true
        defer { saving = false }
        do { try await onSave(cleaned, type, amount); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct FinancialTransferEditor: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [FinancialAccount]
    let onSave: (TransferFunds) async throws -> Void
    @State private var fromID = 0
    @State private var toID = 0
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Entre cuentas propias") {
                    Picker("Origen", selection: $fromID) {
                        ForEach(accounts) { account in Text(account.name).tag(account.id) }
                    }
                    Picker("Destino", selection: $toID) {
                        ForEach(accounts.filter { $0.id != fromID }) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    COPAmountField("Monto COP", text: $amount)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    TextField("Nota (opcional)", text: $note)
                }
                if let error { ErrorBanner(message: error) }
                Button { Task { await save() } } label: {
                    HStack { Spacer(); if saving { ProgressView() } else { Text("Transferir") }; Spacer() }
                }.disabled(saving)
            }
            .navigationTitle("Transferencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .onAppear {
                fromID = accounts.first?.id ?? 0
                toID = accounts.first { $0.id != fromID }?.id ?? 0
            }
            .onChange(of: fromID) { _, _ in
                if toID == fromID {
                    toID = accounts.first { $0.id != fromID }?.id ?? 0
                }
            }
        }
    }

    private func save() async {
        guard fromID > 0, toID > 0, fromID != toID,
              let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0,
              value <= (accounts.first { $0.id == fromID }?.balance ?? 0),
              note.count <= 255 else {
            error = "Revisa origen, destino, saldo disponible y monto."
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await onSave(TransferFunds(fromAccountId: fromID, toAccountId: toID,
                                           amount: value, date: DateFormatters.isoDay.string(from: date),
                                           note: note.isEmpty ? nil : note))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
