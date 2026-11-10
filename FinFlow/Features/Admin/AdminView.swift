import SwiftUI
import Charts

/// Aggregated and anonymized operating metrics; never displays other users' financial records.
/// Backend always validates ROLE_ADMIN independently from this UI gate.
struct AdminView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var overview: AdminOverview?
    @State private var loading = true
    @State private var error: String?
    @State private var platformHealth: AdminPlatformHealth?
    @State private var healthLoading = false
    @State private var healthError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.user?.isAdmin != true {
                        EmptyState(icon: "lock.shield",
                                   title: "Acceso restringido",
                                   message: "Solo la cuenta administradora puede consultar este panel.")
                    } else {
                        if let error {
                            ErrorBanner(message: error)
                            Button("Volver a intentar") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        if loading { ProgressView("Cargando indicadores…").padding(24) }
                        SectionCard(title: "Salud de la plataforma",
                                    subtitle: "Railway · PostgreSQL · Vercel · Asesor IA") {
                            VStack(alignment: .leading, spacing: 12) {
                                if healthLoading && platformHealth == nil {
                                    ProgressView("Comprobando servicios…")
                                }
                                if let healthError {
                                    Text(healthError)
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                                if let platformHealth {
                                    Label(platformHealth.overall == "UP"
                                          ? "Todos los servicios operativos"
                                          : "Algunos servicios requieren atención",
                                          systemImage: platformHealth.overall == "UP"
                                          ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(platformHealth.overall == "UP" ? .green : .orange)
                                    ForEach(platformHealth.services) { service in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: service.icon)
                                                .foregroundStyle(service.tint)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(service.name).font(.subheadline.weight(.semibold))
                                                Text(service.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                if let latency = service.latencyMs {
                                                    Text("\(latency) ms")
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 4)
                                            Text(service.statusLabel)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(service.tint)
                                                .multilineTextAlignment(.trailing)
                                        }
                                        .padding(.vertical, 8)
                                        .accessibilityElement(children: .combine)
                                        Divider()
                                    }
                                    Text("Última comprobación: \(platformHealth.checkedAt.prefix(19).replacingOccurrences(of: "T", with: " ")) UTC")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    Task { await loadHealth() }
                                } label: {
                                    Label("Actualizar servicios", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(healthLoading)
                            }
                        }

                        if let overview {
                            SectionCard(title: "Visión general",
                                        subtitle: "Actividad agregada sin datos financieros personales") {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    metric("Usuarios", value: overview.users, symbol: "person.2.fill")
                                    metric("Nuevos · 30 días", value: overview.newUsers30Days, symbol: "person.crop.circle.badge.plus")
                                    metric("Activos · 30 días", value: overview.activeUsers30Days, symbol: "person.crop.circle.badge.checkmark")
                                    metric("Movimientos", value: overview.transactions, symbol: "arrow.left.arrow.right")
                                    metric("Metas", value: overview.goals, symbol: "target")
                                    metric("Gastos previstos", value: overview.plannedExpenses, symbol: "calendar")
                                    metric("Categorías personales", value: overview.customCategories, symbol: "square.grid.2x2")
                                    metric("Categorías del sistema", value: overview.systemCategories, symbol: "lock")
                                }
                            }

                            SectionCard(title: "Actividad mensual", subtitle: "Últimos seis meses") {
                                if overview.monthlyActivity.isEmpty {
                                    Text("Todavía no hay actividad.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Chart {
                                        ForEach(overview.monthlyActivity) { item in
                                            BarMark(x: .value("Mes", item.month),
                                                    y: .value("Movimientos", item.transactions))
                                                .foregroundStyle(FinFlowTheme.accent)
                                        }
                                    }
                                    .frame(height: 210)
                                    .accessibilityLabel("Gráfico de movimientos mensuales")
                                }
                            }
                            SectionCard(title: "Operación", subtitle: "Eventos de los últimos 30 días") {
                                LabeledContent("Movimientos recientes", value: String(overview.transactions30Days))
                                LabeledContent("Movimientos de ingreso", value: String(overview.incomeTransactions))
                                LabeledContent("Movimientos de gasto", value: String(overview.expenseTransactions))
                                LabeledContent("Gastos pendientes", value: String(overview.pendingExpenses))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                if session.user?.isAdmin == true {
                    await load()
                    await loadHealth()
                }
            }
        }
        .navigationTitle("Administración")
        .task {
            guard session.user?.isAdmin == true else {
                loading = false
                healthLoading = false
                return
            }
            await load()
            await loadHealth()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                await loadHealth()
            }
        }
    }

    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(FinFlowTheme.accent)
            Text(value.formatted()).font(.title2.bold()).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadHealth() async {
        guard session.user?.isAdmin == true, !healthLoading else { return }
        healthLoading = true
        defer { healthLoading = false }
        do {
            let response: AdminPlatformHealth = try await APIClient.shared.request("/admin/monitor")
            platformHealth = response
            healthError = nil
        } catch {
            // Never retain stale green indicators when the monitor is unreachable.
            platformHealth = nil
            healthError = "No pudimos verificar los servicios: \(error.localizedDescription)"
        }
    }

    private func load() async {
        guard session.user?.isAdmin == true else { return }
        loading = true
        defer { loading = false }
        do {
            overview = try await APIClient.shared.request("/admin/overview")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AdminPlatformHealth: Decodable {
    let overall: String
    let checkedAt: String
    let services: [AdminPlatformService]
}

private struct AdminPlatformService: Decodable, Identifiable {
    let key: String
    let name: String
    let status: String
    let latencyMs: Int?
    let detail: String

    var id: String { key }

    var statusLabel: String {
        switch status {
        case "UP": return "Operativo"
        case "DOWN": return "No responde"
        case "NOT_CONFIGURED": return "Sin configurar"
        default: return "Con incidencias"
        }
    }

    var tint: Color {
        switch status {
        case "UP": return .green
        case "DOWN": return .red
        default: return .orange
        }
    }

    var icon: String {
        switch key {
        case "api": return "server.rack"
        case "database": return "externaldrive.fill"
        case "web": return "globe"
        case "ai": return "sparkles"
        default: return "heart.text.square"
        }
    }
}
