import SwiftUI

/// Native management for system (read-only) and user-owned categories.
/// Ownership is always enforced again by Spring Boot using the bearer token.
struct CategoriesView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var categories: [FinanceCategory] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: FinanceCategory?
    @State private var showingEditor = false
    @State private var deleting: FinanceCategory?

    private var income: [FinanceCategory] {
        categories.filter { $0.type.lowercased() == "income" }
    }
    private var expenses: [FinanceCategory] {
        categories.filter { $0.type.lowercased() == "expense" }
    }

    var body: some View {
        ScreenBackground {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let error { ErrorBanner(message: error) }
                    if loading { ProgressView("Cargando categorías…").padding(24) }
                    else if categories.isEmpty {
                        EmptyState(icon: "square.grid.2x2", title: "Sin categorías",
                                   message: "Crea categorías para organizar tus ingresos y gastos.")
                    } else {
                        categorySection("Gastos", icon: "arrow.up.right", items: expenses)
                        categorySection("Ingresos", icon: "arrow.down.left", items: income)
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Categorías")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = nil; showingEditor = true } label: {
                    Label("Nueva categoría", systemImage: "plus.circle.fill")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingEditor, onDismiss: { Task { await load() } }) {
            CategoryEditor(category: editing) { input in
                if let editing {
                    let _: FinanceCategory = try await APIClient.shared.request(
                        "/categories/\(editing.id)", method: "PUT", body: input)
                } else {
                    let _: FinanceCategory = try await APIClient.shared.request(
                        "/categories", method: "POST", body: input)
                }
            }
        }
        .confirmationDialog("¿Eliminar esta categoría?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                guard let category = deleting else { return }
                Task { await remove(category) }
            }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: {
            Text("No se puede eliminar una categoría que tenga movimientos o presupuestos asociados.")
        }
    }

    @ViewBuilder
    private func categorySection(_ title: String, icon: String, items: [FinanceCategory]) -> some View {
        if !items.isEmpty {
            SectionCard(title: title, subtitle: "\(items.count) categorías") {
                ForEach(items) { category in
                    HStack(spacing: 12) {
                        Image(systemName: icon).foregroundStyle(FinFlowTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name).font(.subheadline.weight(.semibold))
                            Text(category.isSystem ? "Categoría del sistema" : "Personal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if category.userId == session.user?.id {
                            Menu {
                                Button("Editar", systemImage: "pencil") {
                                    editing = category; showingEditor = true
                                }
                                Button("Eliminar", systemImage: "trash", role: .destructive) {
                                    deleting = category
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3)
                            }
                            .accessibilityLabel("Opciones para \(category.name)")
                        } else {
                            Image(systemName: "lock").foregroundStyle(.secondary)
                                .accessibilityLabel("Solo lectura")
                        }
                    }
                    .padding(.vertical, 4)
                    if category.id != items.last?.id { Divider() }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            categories = try await APIClient.shared.request("/categories")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ category: FinanceCategory) async {
        guard category.userId == session.user?.id else { return }
        do {
            try await APIClient.shared.perform("/categories/\(category.id)", method: "DELETE")
            categories.removeAll { $0.id == category.id }
            deleting = nil
        } catch {
            error = error.localizedDescription
            deleting = nil
        }
    }
}

struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let category: FinanceCategory?
    let onSave: (CategoryMutation) async throws -> Void
    @State private var name = ""
    @State private var type = "expense"
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Detalles") {
                    TextField("Nombre de la categoría", text: $name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Tipo", selection: $type) {
                        Text("Gasto").tag("expense")
                        Text("Ingreso").tag("income")
                    }
                    .pickerStyle(.segmented)
                }
                if let error { Section { ErrorBanner(message: error) } }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() } else { Text("Guardar categoría") }
                            Spacer()
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
            .navigationTitle(category == nil ? "Nueva categoría" : "Editar categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
            }
            .onAppear {
                if let category {
                    name = category.name
                    type = category.type.lowercased()
                }
            }
        }
    }

    private func save() async {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(cleaned.count) else {
            error = "El nombre debe tener entre 2 y 80 caracteres."
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await onSave(CategoryMutation(name: cleaned, type: type))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
