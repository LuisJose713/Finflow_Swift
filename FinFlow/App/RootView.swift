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
                MainTabView()
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
    var body: some View {
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

struct MoreView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ScreenBackground {
                List {
                    Section("Organiza tus finanzas") {
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
