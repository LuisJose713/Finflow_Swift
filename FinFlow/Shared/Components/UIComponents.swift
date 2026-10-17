import SwiftUI

struct ScreenBackground<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ZStack { FinFlowTheme.background.ignoresSafeArea(); content } }
}
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
            }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
struct PrimaryButton: View {
    let title: String; var isLoading = false; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { if isLoading { ProgressView().tint(.white) }; Text(title).fontWeight(.semibold) }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(FinFlowTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }.disabled(isLoading)
    }
}
struct EmptyState: View {
    let icon: String; let title: String; let message: String
    var body: some View { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 34)).foregroundStyle(FinFlowTheme.accent); Text(title).font(.headline); Text(message).font(.subheadline).foregroundStyle(FinFlowTheme.secondaryText).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(28) }
}
struct ErrorBanner: View {
    let message: String
    var body: some View { Text(message).font(.footnote).foregroundStyle(.white).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(FinFlowTheme.danger.opacity(0.18), in: RoundedRectangle(cornerRadius: 12)) }
}
struct LoadingView: View { var body: some View { ProgressView("Cargando…").tint(FinFlowTheme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) } }
