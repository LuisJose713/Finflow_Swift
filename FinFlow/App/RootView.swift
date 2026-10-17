import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isChecking = true

    var body: some View {
        Group {
            if isChecking {
                ZStack { FinFlowTheme.background.ignoresSafeArea(); ProgressView("Preparando FinFlow…") }
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

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Inicio", systemImage: "chart.pie.fill") }
            TransactionsView().tabItem { Label("Movimientos", systemImage: "arrow.left.arrow.right") }
            GoalsView().tabItem { Label("Metas", systemImage: "scope") }
            PlannedExpensesView().tabItem { Label("Planificados", systemImage: "calendar.badge.clock") }
            AdvisorView().tabItem { Label("Asesor IA", systemImage: "sparkles") }
        }
        .toolbarBackground(FinFlowTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
