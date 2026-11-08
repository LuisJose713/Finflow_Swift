import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isChecking = true

    var body: some View {
        Group {
            if isChecking {
                ZStack {
                    FinFlowTheme.background.ignoresSafeArea()
                    ProgressView("Preparando FinFlow…")
                }
            } else if session.isAuthenticated {
                switch session.privacyAccess {
                case .loading:
                    ZStack {
                        FinFlowTheme.background.ignoresSafeArea()
                        ProgressView("Verificando tu privacidad…")
                    }
                case .accepted:
                    MainTabView()
                case .needsConsent:
                    PrivacyConsentGate()
                case .unavailable:
                    PrivacyUnavailableView()
                }
            } else {
                AuthView()
            }
        }
        .task {
            await session.restoreSession()
            isChecking = false
        }
    }
}

/// Five clear destinations on iPhone. Secondary features live in "Más";
/// native SwiftUI navigation adapts naturally to iPad.
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        #if targetEnvironment(macCatalyst)
        FinFlowLargeScreenView()
        #else
        if sizeClass == .regular { FinFlowLargeScreenView() } else { phoneTabs }
        #endif
    }
    private var phoneTabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Inicio", systemImage: "chart.pie.fill") }
            TransactionsView()
                .tabItem { Label("Movimientos", systemImage: "arrow.left.arrow.right") }
            GoalsView()
                .tabItem { Label("Metas", systemImage: "scope") }
            BudgetsView()
                .tabItem { Label("Presupuestos", systemImage: "chart.bar.xaxis") }
            MoreView()
                .tabItem { Label("Más", systemImage: "square.grid.2x2.fill") }
        }
        .toolbarBackground(FinFlowTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}


private enum FinFlowSection: String, Hashable {
    case dashboard, available, transactions, goals, budgets
    case accounts, recurring, planned, categories, advisor, billing, settings, admin
    var label: String {
        switch self {
        case .dashboard: "Inicio"
        case .available: "Mi dinero disponible"
        case .transactions: "Movimientos"
        case .goals: "Metas"
        case .budgets: "Presupuestos"
        case .accounts: "Cuentas y billeteras"
        case .recurring: "Recurrentes"
        case .planned: "Gastos planificados"
        case .categories: "Categorías"
        case .advisor: "Asesor IA"
        case .billing: "Planes"
        case .settings: "Ajustes y privacidad"
        case .admin: "Administración"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "chart.pie.fill"
        case .available: "wallet.bifold.fill"
        case .transactions: "arrow.left.arrow.right"
        case .goals: "scope"
        case .budgets: "chart.bar.xaxis"
        case .accounts: "wallet.pass"
        case .recurring: "repeat"
        case .planned: "calendar.badge.clock"
        case .categories: "square.grid.2x2"
        case .advisor: "sparkles"
        case .billing: "crown"
        case .settings: "gearshape"
        case .admin: "lock.shield"
        }
    }
}
struct FinFlowLargeScreenView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selection: FinFlowSection? = .dashboard
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                section("TU DINERO", [.dashboard, .available, .transactions, .goals, .budgets])
                section("ORGANIZA", [.accounts, .recurring, .planned, .categories])
                section("HERRAMIENTAS", [.advisor, .billing, .settings])
                if session.user?.isAdmin == true { section("ADMINISTRACIÓN", [.admin]) }
            }
            .navigationTitle("FinFlow")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private func section(_ name: String, _ entries: [FinFlowSection]) -> some View {
        Section(name) {
            ForEach(entries, id: \.self) { item in
                Label(item.label, systemImage: item.icon)
                    .tag(item)
            }
        }
    }
    @ViewBuilder private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard: DashboardView()
        case .available: DisponibleView()
        case .transactions: TransactionsView()
        case .goals: GoalsView()
        case .budgets: BudgetsView()
        case .accounts: AccountsView()
        case .recurring: RecurringView()
        case .planned: PlannedExpensesView()
        case .categories: CategoriesView()
        case .advisor: AdvisorView()
        case .billing: BillingView()
        case .settings: SettingsView()
        case .admin:
            if session.user?.isAdmin == true { AdminView() }
            else { DashboardView() }
        }
    }
}

struct MoreView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ScreenBackground {
                List {
                    Section("Organiza tus finanzas") {
                        NavigationLink {
                            DisponibleView()
                        } label: {
                            Label("Mi dinero disponible", systemImage: "wallet.bifold.fill")
                        }
                        NavigationLink {
                            AccountsView()
                        } label: {
                            Label("Cuentas y billeteras", systemImage: "wallet.pass")
                        }
                        NavigationLink {
                            RecurringView()
                        } label: {
                            Label("Movimientos recurrentes", systemImage: "repeat")
                        }
                        NavigationLink {
                            CategoriesView()
                        } label: {
                            Label("Categorías", systemImage: "square.grid.2x2")
                        }
                        NavigationLink {
                            PlannedExpensesView()
                        } label: {
                            Label("Gastos planificados", systemImage: "calendar.badge.clock")
                        }
                    }

                    Section("Más herramientas") {
                        NavigationLink {
                            BillingView()
                        } label: {
                            Label("Planes Free y Pro", systemImage: "crown")
                        }
                        NavigationLink {
                            AdvisorView()
                        } label: {
                            Label("Asesor financiero IA", systemImage: "sparkles")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Ajustes y privacidad", systemImage: "gearshape")
                        }
                    }

                    if session.user?.isAdmin == true {
                        Section("Administración") {
                            NavigationLink {
                                AdminView()
                            } label: {
                                Label("Panel administrador", systemImage: "lock.shield")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Más")
        }
    }
}
