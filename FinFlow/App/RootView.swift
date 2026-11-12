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

/// Four compact destinations on iPhone; an adaptive native sidebar on iPad.
struct MainTabView: View {
    var body: some View {
        if #available(iOS 18.0, *) { tabs.tabViewStyle(.sidebarAdaptable) }
        else { tabs }
    }
    private var tabs: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Inicio", systemImage: "chart.pie.fill") }
            TransactionsView()
                .tabItem { Label("Movimientos", systemImage: "arrow.left.arrow.right") }
            GoalsView()
                .tabItem { Label("Metas", systemImage: "scope") }
            MoreView()
                .tabItem { Label("Menú", systemImage: "line.3.horizontal") }
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
