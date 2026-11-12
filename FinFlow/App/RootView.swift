import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var checkingSession = true
    @State private var showPrivacyNotice = false
    @State private var requirePrivacyConsent = false
    @State private var privacyPolicy: PrivacyPolicy?
    @State private var privacyError: String?

    // The informational notice is local to this app install. It never
    // creates a privacy consent record in Neon.
    private let noticeRevision = "ios-privacy-notice-v1"

    var body: some View {
        Group {
            if checkingSession {
                ZStack {
                    FinFlowTheme.background.ignoresSafeArea()
                    ProgressView("Preparando FinFlow…")
                }
            } else if session.isAuthenticated {
                MainTabView()
                    .sheet(isPresented: $showPrivacyNotice) {
                        PrivacyNoticeSheet(policy: privacyPolicy) {
                            acknowledgeNotice()
                        }
                        .interactiveDismissDisabled()
                    }
                    .fullScreenCover(isPresented: $requirePrivacyConsent) {
                        PrivacyConsentGateSheet(
                            policy: privacyPolicy,
                            errorMessage: privacyError,
                            confirm: { marketing in await confirmPrivacyConsent(marketing: marketing) },
                            retry: { await reloadPrivacyForActiveUser() },
                            leave: { requirePrivacyConsent = false; session.logout() }
                        )
                        .interactiveDismissDisabled()
                    }
            } else {
                AuthView()
            }
        }
        .task {
            await session.restoreSession()
            checkingSession = false
        }
        .task(id: session.user?.id) {
            if let currentUser = session.user, session.isAuthenticated {
                await refreshPrivacy(userID: currentUser.id)
            } else {
                showPrivacyNotice = false
                requirePrivacyConsent = false
                privacyPolicy = nil
                privacyError = nil
            }
        }
    }

    @MainActor
    private func refreshPrivacy(userID: Int) async {
        privacyError = nil
        var candidate: PrivacyPolicy?
        do {
            candidate = try await APIClient.shared.request("/privacy/policy")
        } catch {
            // The educational notice remains available when the policy
            // endpoint fails. Do not invent legal publication status.
        }

        guard session.isAuthenticated, session.user?.id == userID else { return }
        privacyPolicy = candidate

        if let candidate, candidate.ready {
            do {
                let status: PrivacyStatus = try await APIClient.shared.request("/privacy/status")
                guard session.isAuthenticated, session.user?.id == userID else { return }
                if !status.policyReady || status.version != candidate.version {
                    privacyError = "No pudimos comprobar la versión de la política. Intenta de nuevo."
                    requirePrivacyConsent = true
                    showPrivacyNotice = false
                    return
                }
                if !status.accepted {
                    requirePrivacyConsent = true
                    showPrivacyNotice = false
                    return
                }
            } catch {
                guard session.isAuthenticated, session.user?.id == userID else { return }
                privacyError = "No pudimos verificar tu autorización. Comprueba la conexión e inténtalo."
                requirePrivacyConsent = true
                showPrivacyNotice = false
                return
            }
        }

        requirePrivacyConsent = false
        let key = noticeKey(userID: userID, policyVersion: candidate?.version ?? "2026-11-09-v1")
        if !UserDefaults.standard.bool(forKey: key) {
            showPrivacyNotice = true
        }
    }

    private func noticeKey(userID: Int, policyVersion: String) -> String {
        "finflow.privacyNotice.\(noticeRevision).\(policyVersion).\(userID)"
    }

    @MainActor
    private func acknowledgeNotice() {
        if let currentUser = session.user {
            let key = noticeKey(userID: currentUser.id,
                                policyVersion: privacyPolicy?.version ?? "2026-11-09-v1")
            UserDefaults.standard.set(true, forKey: key)
        }
        showPrivacyNotice = false
    }

    @MainActor
    private func reloadPrivacyForActiveUser() async {
        guard let currentUser = session.user else { return }
        await refreshPrivacy(userID: currentUser.id)
    }

    @MainActor
    private func confirmPrivacyConsent(marketing: Bool) async -> Bool {
        guard session.isAuthenticated,
              let userID = session.user?.id,
              let policy = privacyPolicy,
              policy.ready,
              privacyError == nil else { return false }
        do {
            let response: PrivacyConsentResponse = try await APIClient.shared.request(
                "/privacy/consent",
                method: "POST",
                body: PrivacyConsentInput(
                    accepted: true,
                    policyVersion: policy.version,
                    marketingConsent: marketing
                )
            )
            guard response.accepted && response.version == policy.version else {
                privacyError = "El servidor no confirmó la autorización."
                return false
            }
            // An actual consent receipt has been saved by the backend.
            let key = noticeKey(userID: userID, policyVersion: policy.version)
            UserDefaults.standard.set(true, forKey: key)
            requirePrivacyConsent = false
            showPrivacyNotice = false
            return true
        } catch {
            privacyError = "No pudimos guardar tu decisión: \(error.localizedDescription)"
            return false
        }
    }
}

/// iPhone keeps the native four-tab shortcuts and gains an optional edge-swipe
/// navigation drawer. iPad keeps Apple's adaptive sidebar.
struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: MainTab = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawerOpen = false
    @State private var drawerOffset: CGFloat?
    @State private var detail: DrawerDestination?

    private enum MainTab: Hashable { case home, transactions, goals, more }
    private enum DrawerDestination: String, Identifiable {
        case accounts, budgets, recurring, categories, planned, reports, plans, advisor, settings, admin, billing
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(CGFloat(320), geometry.size.width * 0.86)
            let offset = drawerOffset ?? (drawerOpen ? 0 : -width)
            let progress = min(1, max(0, 1 + offset / width))
            ZStack(alignment: .leading) {
                tabs
                    .accessibilityHidden(drawerOpen && sizeClass == .compact)

                if sizeClass == .compact {
                    Color.black.opacity(0.55 * progress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeDrawer() }
                        .allowsHitTesting(progress > 0)
                        .accessibilityHidden(true)
                        .zIndex(1)
                    drawer
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background(FinFlowTheme.surface)
                        .shadow(color: .black.opacity(0.22 * progress), radius: 18, x: 8)
                        .offset(x: offset)
                        .allowsHitTesting(progress > 0)
                        .accessibilityHidden(!drawerOpen)
                        .accessibilityAction(.escape) { closeDrawer() }
                        .zIndex(2)
                }
            }
            .background {
                DrawerPanGesture(
                    enabled: sizeClass == .compact && detail == nil,
                    isOpen: drawerOpen,
                    drawerWidth: width,
                    changed: { offset in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { drawerOffset = offset }
                    },
                    ended: { open in setDrawer(open) },
                    cancelled: { setDrawer(drawerOpen) }
                )
            }
            .onChange(of: sizeClass) { _, _ in setDrawer(false) }
            .overlay(alignment: .topLeading) {
                if sizeClass == .compact && !drawerOpen && drawerOffset == nil {
                    Button {
                        setDrawer(true)
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .foregroundStyle(FinFlowTheme.accent)
                    .accessibilityLabel("Abrir menú FinFlow")
                    .padding(.leading, 12)
                    .padding(.top, 2)
                    .zIndex(3)
                }
            }
            .sheet(item: $detail) { destination in
                NavigationStack {
                    detailView(destination)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Cerrar") { detail = nil }
                            }
                        }
                }
            }
        }
    }

    private var tabs: some View {
        let selection = TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Inicio", systemImage: "chart.pie.fill") }
                .tag(MainTab.home)
            TransactionsView()
                .tabItem { Label("Movimientos", systemImage: "arrow.left.arrow.right") }
                .tag(MainTab.transactions)
            GoalsView()
                .tabItem { Label("Metas", systemImage: "scope") }
                .tag(MainTab.goals)
            MoreView()
                .tabItem { Label("Menú", systemImage: "line.3.horizontal") }
                .tag(MainTab.more)
        }
        .toolbarBackground(FinFlowTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        if #available(iOS 18.0, *) {
            return AnyView(selection.tabViewStyle(.sidebarAdaptable))
        } else {
            return AnyView(selection)
        }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                FinFlowBrandSymbol(size: 42)
                FinFlowBrandWordmark()
                    .scaleEffect(0.72, anchor: .leading)
                    .frame(width: 122, height: 42, alignment: .leading)
                Spacer()
                Button { closeDrawer() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Cerrar menú")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                Text(String((session.user?.name ?? "F").prefix(1)).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(FinFlowTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(FinFlowTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.user?.name ?? "Tu espacio financiero")
                        .font(.headline).lineLimit(1)
                    Text("Tus finanzas, con claridad")
                        .font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("TU PANORAMA")
                    tabLink("Inicio", icon: "house", tab: .home)
                    tabLink("Movimientos", icon: "arrow.left.arrow.right", tab: .transactions)
                    tabLink("Metas", icon: "scope", tab: .goals)
                    destinationLink("Gastos planificados", icon: "calendar", destination: .planned)
                    Divider().padding(.vertical, 10)
                    sectionTitle("TU DINERO")
                    destinationLink("Cuentas y billeteras", icon: "wallet.pass", destination: .accounts)
                    destinationLink("Presupuestos", icon: "chart.bar.xaxis", destination: .budgets)
                    destinationLink("Recurrentes", icon: "repeat", destination: .recurring)
                    destinationLink("Categorías", icon: "square.grid.2x2", destination: .categories)
                    destinationLink("Asesor IA", icon: "sparkles", destination: .advisor)
                    destinationLink("Reportes", icon: "doc.text", destination: .reports)
                    Divider().padding(.vertical, 10)
                    sectionTitle("TU CUENTA")
                    destinationLink("Planes", icon: "crown", destination: .plans)
                    destinationLink("Ajustes y privacidad", icon: "gearshape", destination: .settings)
                    if session.user?.isAdmin == true {
                        destinationLink("Administración", icon: "lock.shield", destination: .admin)
                        destinationLink("Planes y promociones", icon: "tag", destination: .billing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            Text("FinFlow · AEVQOR")
                .font(.caption2.weight(.medium))
                .foregroundStyle(FinFlowTheme.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isModal)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.bold)).tracking(1.2)
            .foregroundStyle(FinFlowTheme.secondaryText)
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
    }

    private func menuRow(_ text: String, icon: String, selected: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 24)
            Text(text).font(.body.weight(selected ? .semibold : .medium))
            Spacer()
            if selected { Image(systemName: "checkmark").font(.caption2) }
        }
        .foregroundStyle(selected ? FinFlowTheme.accent : Color.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(selected ? FinFlowTheme.accent.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
    }

    private func tabLink(_ text: String, icon: String, tab: MainTab) -> some View {
        Button {
            selectedTab = tab
            closeDrawer()
        } label: { menuRow(text, icon: icon, selected: selectedTab == tab) }
        .buttonStyle(FinFlowPressStyle())
    }

    private func destinationLink(_ text: String, icon: String, destination: DrawerDestination) -> some View {
        Button {
            closeDrawer()
            detail = destination
        } label: { menuRow(text, icon: icon) }
        .buttonStyle(FinFlowPressStyle())
    }

    private func setDrawer(_ open: Bool) {
        withAnimation(reduceMotion ? nil : FinFlowMotion.panel) {
            drawerOpen = open
            drawerOffset = nil
        }
    }

    private func closeDrawer() { setDrawer(false) }

    @ViewBuilder private func detailView(_ destination: DrawerDestination) -> some View {
        switch destination {
        case .accounts: AccountsView()
        case .budgets: BudgetsView()
        case .recurring: RecurringView()
        case .categories: CategoriesView()
        case .planned: PlannedExpensesView()
        case .reports: ReportsView()
        case .plans: PlansView()
        case .advisor: AdvisorView()
        case .settings: SettingsView()
        case .admin: AdminView()
        case .billing: AdminBillingView()
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
                        NavigationLink { BudgetsView() } label: {
                            Label("Presupuestos", systemImage: "chart.bar.xaxis")
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
                        NavigationLink { ReportsView() } label: {
                            Label("Reportes PDF y Excel", systemImage: "doc.text")
                        }
                        NavigationLink { PlansView() } label: {
                            Label("Planes FinFlow", systemImage: "crown")
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
                            NavigationLink { AdminBillingView() } label: {
                                Label("Planes y promociones", systemImage: "tag")
                            }
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
            .navigationTitle("Menú")
        }
    }
}

private struct PrivacyTextSection: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrivacyPolicyDocument: View {
    let policy: PrivacyPolicy?
    private var owner: String {
        guard let name = policy?.controllerName, !name.isEmpty else { return "SoftDevCode S.A.S." }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Tratamiento de datos personales", systemImage: "hand.raised.square.fill")
                .font(.headline)
                .foregroundStyle(FinFlowTheme.accent)

            PrivacyTextSection(
                title: "Responsable del tratamiento",
                detail: "\(owner) · NIT \(policy?.controllerNit ?? "901796447")\nFinFlow es un producto de AEVQOR."
            )
            if let policy, policy.ready {
                PrivacyTextSection(
                    title: "Contacto del responsable",
                    detail: "\(policy.contactEmail) · \(policy.contactPhone)\n\(policy.contactAddress)"
                )
                Text("Versión \(policy.version) · \(policy.effectiveDate)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label(
                    "Política formal en revisión. Este aviso no constituye una autorización ni acredita aprobación legal.",
                    systemImage: "info.circle"
                )
                .font(.footnote).foregroundStyle(.orange)
            }
            PrivacyTextSection(
                title: "Información utilizada",
                detail: "Nombre, correo electrónico, datos de autenticación y los registros que ingresas: movimientos, cuentas, metas, categorías y presupuestos."
            )
            PrivacyTextSection(
                title: "Finalidades",
                detail: "Permitir el acceso a FinFlow, administrar tus finanzas, mostrar estadísticas, proteger tu cuenta y responder solicitudes relacionadas con tus datos."
            )
            PrivacyTextSection(
                title: "Cómo se protege",
                detail: "Conexiones HTTPS, controles de acceso, contraseñas protegidas con hash y sesiones autenticadas. No afirmamos cifrado de extremo a extremo de toda la información."
            )
            PrivacyTextSection(
                title: "Comunicaciones comerciales",
                detail: "Recibir promociones es opcional y debe decidirse por separado del tratamiento necesario para prestar FinFlow."
            )
            PrivacyTextSection(
                title: "Tus derechos",
                detail: "Puedes solicitar acceso, rectificación, supresión o revocatoria cuando corresponda. Las solicitudes requieren revisión y no eliminan datos de forma automática."
            )
        }
        .textSelection(.enabled)
    }
}

struct PrivacyNoticeSheet: View {
    let policy: PrivacyPolicy?
    let acknowledge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tu información, bajo tu control")
                        .font(.title2.bold())
                    Text("Este aviso aparece una vez para que conozcas qué datos utiliza FinFlow.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    PrivacyPolicyDocument(policy: policy)
                    Text("Cerrar esta ventana solo confirma que se mostró la información. No registra consentimiento para una política pendiente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .background(FinFlowTheme.background)
            .navigationTitle("Privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: acknowledge) {
                    Text("Entendido, continuar a FinFlow")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(FinFlowTheme.accent)
                .padding()
                .frame(maxWidth: 660)
                .background(.regularMaterial)
            }
        }
    }
}

struct PrivacyConsentGateSheet: View {
    let policy: PrivacyPolicy?
    let errorMessage: String?
    let confirm: (Bool) async -> Bool
    let retry: () async -> Void
    let leave: () -> Void

    @State private var accepted = false
    @State private var marketing = false
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tu decisión sobre tus datos")
                        .font(.title2.bold())
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                        Button("Reintentar verificación") {
                            Task { await retry() }
                        }
                        .buttonStyle(.bordered)
                    } else if let policy, policy.ready {
                        PrivacyPolicyDocument(policy: policy)
                        Toggle("Autorizo expresamente el tratamiento necesario para usar FinFlow.", isOn: $accepted)
                        Toggle("Opcional: recibir promociones y novedades.", isOn: $marketing)
                        if let saveError { ErrorBanner(message: saveError) }
                        Button {
                            Task {
                                saving = true
                                saveError = nil
                                let ok = await confirm(marketing)
                                if !ok { saveError = "No se pudo confirmar la autorización. Revisa tu conexión e inténtalo de nuevo." }
                                saving = false
                            }
                        } label: {
                            if saving { ProgressView() }
                            else { Text("Aceptar y continuar") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!accepted || saving)
                    } else {
                        ErrorBanner(message: "La política no está disponible para confirmar tu autorización.")
                        Button("Reintentar") { Task { await retry() } }
                    }
                    Button("No aceptar · Cerrar sesión", role: .destructive, action: leave)
                        .padding(.top, 10)
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .background(FinFlowTheme.background)
            .navigationTitle("Tratamiento de datos")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

