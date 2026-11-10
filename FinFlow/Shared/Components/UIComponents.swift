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
                Text(title).font(.headline).foregroundStyle(.primary)
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
    var body: some View { Text(message).font(.footnote).foregroundStyle(FinFlowTheme.danger).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(FinFlowTheme.danger.opacity(0.18), in: RoundedRectangle(cornerRadius: 12)) }
}
struct LoadingView: View { var body: some View { ProgressView("Cargando…").tint(FinFlowTheme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) } }


/* Premium FinFlow identity. Vector shapes are independent of external fonts. */
struct FinFlowBrandSymbol: View {
    var size: CGFloat = 86
    private let navy = Color(red: 0.035, green: 0.086, blue: 0.165)
    private let gold = Color(red: 0.84, green: 0.66, blue: 0.30)

    var body: some View {
        Canvas { context, dimensions in
            let k = min(dimensions.width, dimensions.height) / 96
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var letter = Path()
            letter.move(to: point(13, 81))
            letter.addLine(to: point(29, 40))
            letter.addCurve(to: point(60, 17), control1: point(36, 22), control2: point(45, 17))
            letter.addLine(to: point(80, 17))
            letter.addLine(to: point(75, 29))
            letter.addLine(to: point(59, 29))
            letter.addCurve(to: point(39, 42), control1: point(49, 29), control2: point(43, 33))
            letter.addLine(to: point(24, 81))
            letter.closeSubpath()
            context.fill(letter, with: .color(.white))
            var swoosh = Path()
            swoosh.move(to: point(25, 68))
            swoosh.addCurve(to: point(67, 40), control1: point(34, 50), control2: point(48, 40))
            swoosh.addLine(to: point(78, 40))
            swoosh.addLine(to: point(71, 52))
            swoosh.addLine(to: point(60, 52))
            swoosh.addCurve(to: point(25, 68), control1: point(43, 52), control2: point(33, 60))
            swoosh.closeSubpath()
            context.fill(swoosh, with: .color(gold))
        }
        .frame(width: size, height: size)
        .background(navy, in: RoundedRectangle(cornerRadius: size * 0.23))
        .accessibilityLabel("FinFlow")
        .accessibilityAddTraits(.isImage)
    }
}

struct FinFlowBrandWordmark: View {
    private let gold = Color(red: 0.84, green: 0.66, blue: 0.30)
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("F").font(.system(size: 34, weight: .bold, design: .rounded))
            VStack(spacing: 2) {
                Circle().fill(gold).frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 6, height: 24)
            }
            .frame(width: 9, height: 34)
            .accessibilityHidden(true)
            Text("nFlow").font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FinFlow")
    }
}
