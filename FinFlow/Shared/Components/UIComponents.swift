import SwiftUI

struct ScreenBackground<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ZStack { FinFlowTheme.background.ignoresSafeArea(); content.modifier(FinFlowScreenEntrance()) } }
}
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(FinFlowTheme.secondaryText) }
            }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(FinFlowTheme.accent.opacity(0.13), lineWidth: 1))
    }
}
struct PrimaryButton: View {
    let title: String; var isLoading = false; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { if isLoading { ProgressView().tint(FinFlowTheme.onAction) }; Text(title).fontWeight(.semibold) }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(FinFlowTheme.action, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(FinFlowTheme.onAction)
        }.buttonStyle(FinFlowPressStyle()).disabled(isLoading)
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


/// Native text styles and SF Symbols respect Dynamic Type and VoiceOver.
struct PresentationCard: View {
    let cardID: String
    let eyebrow: String
    let title: String
    let detail: String
    var symbol = "sparkles"
    @EnvironmentObject private var preferences: UiPreferencesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preferences.hiddenCards.contains(cardID) {
                Button {
                    Task { await preferences.setHidden(false, cardID: cardID) }
                } label: {
                    Image(systemName: "rectangle.expand.vertical")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Mostrar presentación de " + eyebrow)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Label(eyebrow.uppercased(), systemImage: symbol)
                            .font(.caption.weight(.semibold)).tracking(1.0)
                            .foregroundStyle(FinFlowTheme.gold)
                            .padding(.top, 12)
                        Spacer(minLength: 0)
                        Button {
                            Task { await preferences.setHidden(true, cardID: cardID) }
                        } label: {
                            Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Ocultar presentación de " + eyebrow)
                    }
                    Text(title).font(.title2.weight(.bold)).fontDesign(.rounded)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(FinFlowTheme.gold.opacity(0.20), lineWidth: 1))
            }
            if let message = preferences.errors[cardID] { ErrorBanner(message: message) }
        }
        .disabled(preferences.saving.contains(cardID))
        .animation(reduceMotion ? nil : FinFlowMotion.panel, value: preferences.hiddenCards.contains(cardID))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A peso remains a peso: typing 25000 never silently becomes 250.00.
struct COPAmountField: View {
    let title: String
    @Binding var value: String
    @FocusState private var focused: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._value = text
    }

    private var display: Binding<String> {
        Binding(get: { COPInput.display(value, padDecimals: !focused) }, set: { input in
            if let normalized = COPInput.normalize(input, previous: value) { value = normalized }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("0,00", text: display).keyboardType(.decimalPad)
                    .focused($focused).monospacedDigit().accessibilityLabel(title)
                    .accessibilityValue(COPInput.display(value, padDecimals: true) + " pesos colombianos")
                Text("COP").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}


struct PasswordInput: View {
    let title: String
    @Binding var text: String
    var isNew = false
    @State private var revealed = false
    init(_ title: String, text: Binding<String>, isNew: Bool = false) {
        self.title = title; self._text = text; self.isNew = isNew
    }
    var body: some View {
        HStack {
            Group {
                if revealed { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }
            .textContentType(isNew ? .newPassword : .password)
            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(revealed ? "Ocultar contraseña" : "Mostrar contraseña")
        }
        .padding(.leading, 15).padding(.trailing, 3).padding(.vertical, 4)
        .background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct FinFlowKeyboardDismiss: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

