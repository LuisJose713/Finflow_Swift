import SwiftUI

struct AppLockView: View {
    @EnvironmentObject private var appLock: AppLockStore
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ScreenBackground {
            ScrollView {
                VStack(spacing: 24) {
                    FinFlowBrandSymbol(size: 76)
                    VStack(spacing: 10) {
                        Text("Tu tranquilidad, protegida.")
                            .font(.title2.bold()).fontDesign(.rounded)
                        Text("Desbloquea FinFlow para consultar tus finanzas.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Image(systemName: appLock.symbol)
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(FinFlowTheme.gold)
                        .accessibilityHidden(true)
                    PrimaryButton(title: "Desbloquear con \(appLock.methodName)", isLoading: appLock.isAuthenticating) {
                        Task { await appLock.unlock() }
                    }
                    .accessibilityIdentifier("lock.unlock")
                    Text("También puedes usar el código del dispositivo.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = appLock.error { ErrorBanner(message: error) }
                    Button("Entrar con otra cuenta") { session.logout() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("lock.logout")
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(28)
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
            }
        }
        .accessibilityIdentifier("lock.screen")
        .task { await appLock.unlock(automatically: true) }
    }
}
