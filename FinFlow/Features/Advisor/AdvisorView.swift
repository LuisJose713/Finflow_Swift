import SwiftUI

/// FinFlow AI uses the native full-height chat layout and the existing API.
struct AdvisorView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FinFlowBrandSymbol(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FinFlow AI").font(.headline)
                    Text("Tu asistente financiero")
                        .font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Button {
                    messages.removeAll()
                    input = ""
                    error = nil
                    inputFocused = false
                } label: {
                    Label("Nuevo chat", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .disabled(messages.isEmpty || isSending)
                .accessibilityIdentifier("advisor.newChat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(FinFlowTheme.surface)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                FinFlowBrandSymbol(size: 56)
                                Text("¿En qué puedo ayudarte?")
                                    .font(.title2.weight(.semibold))
                                Text("Pregunta lo que quieras sobre tus finanzas.")
                                    .font(.subheadline)
                                    .foregroundStyle(FinFlowTheme.secondaryText)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .accessibilityIdentifier("advisor.welcome")
                        }
                        ForEach(messages) { message in
                            messageBubble(message).id(message.id)
                        }
                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(FinFlowTheme.gold)
                                Text("FinFlow está escribiendo…")
                                    .font(.footnote).foregroundStyle(FinFlowTheme.secondaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }
                        if let error { ErrorBanner(message: error).padding(.horizontal, 16) }
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 9) {
                    TextField("Escribe tu mensaje…", text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(FinFlowTheme.elevated,
                                    in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("advisor.input")
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .foregroundStyle(FinFlowTheme.onAccent)
                            .frame(width: 46, height: 46)
                            .background(FinFlowTheme.accent,
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityLabel("Enviar mensaje")
                    .accessibilityIdentifier("advisor.send")
                }
                Text("La IA puede equivocarse. Verifica la información importante.")
                    .font(.caption2)
                    .foregroundStyle(FinFlowTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(FinFlowTheme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinFlowTheme.background)
        .navigationTitle("Asesor IA")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        let fromUser = message.role == "user"
        return HStack(alignment: .bottom, spacing: 9) {
            if fromUser { Spacer(minLength: 38) }
            if !fromUser { FinFlowBrandSymbol(size: 28) }
            Text(message.content)
                .textSelection(.enabled)
                .font(.body)
                .padding(13)
                .foregroundStyle(fromUser ? FinFlowTheme.onAccent : Color.primary)
                .background(fromUser ? FinFlowTheme.accent : FinFlowTheme.surface,
                            in: RoundedRectangle(cornerRadius: 15))
            if !fromUser { Spacer(minLength: 38) }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func send() async {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        input = ""
        error = nil
        messages.append(ChatMessage(content: content, role: "user"))
        isSending = true
        defer { isSending = false }
        do {
            let result: AdvisorResponse = try await APIClient.shared.request(
                "/ai/chat", method: "POST", body: AdvisorRequest(mensaje: content))
            messages.append(ChatMessage(content: result.respuesta, role: "assistant"))
        } catch {
            self.error = "No se pudo conectar con el asesor. Comprueba tu conexión e inténtalo de nuevo."
        }
    }
}
