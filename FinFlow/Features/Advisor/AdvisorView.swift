import SwiftUI

struct AdvisorView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool
    private let suggestions = ["¿Cómo puedo ahorrar más?", "Analiza mis gastos", "Ayúdame a crear un presupuesto"]

    var body: some View {
        NavigationStack {
            ScreenBackground {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14) {
                                if messages.isEmpty {
                                    VStack(spacing: 15) {
                                        Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(FinFlowTheme.accent).padding(22).background(FinFlowTheme.accent.opacity(0.14), in: Circle())
                                        Text("Tu asesor financiero").font(.title2.bold())
                                        Text("Pregúntame sobre tus hábitos, tus gastos o formas realistas de ahorrar.").font(.subheadline).foregroundStyle(FinFlowTheme.secondaryText).multilineTextAlignment(.center)
                                        ForEach(suggestions, id: \.self) { suggestion in Button(suggestion) { input = suggestion; Task { await send() } }.buttonStyle(.bordered).tint(FinFlowTheme.accent) }
                                    }.padding(.top, 50).padding(.horizontal, 22)
                                }
                                ForEach(messages) { message in messageBubble(message).id(message.id) }
                                if isSending { HStack { ProgressView().tint(FinFlowTheme.accent); Text("El asesor está pensando…").font(.caption).foregroundStyle(FinFlowTheme.secondaryText); Spacer() }.padding(12) }
                                if let error { ErrorBanner(message: error) }
                            }.padding(16)
                        }.onChange(of: messages.count) { _, _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Escribe tu consulta…", text: $input, axis: .vertical).lineLimit(1...5).focused($inputFocused).padding(12).background(FinFlowTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                        Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 46, height: 46).background(FinFlowTheme.accent, in: Circle()) }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }.padding(12).background(FinFlowTheme.surface)
                }
            }
            .navigationTitle("Asesor IA")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Limpiar") { messages.removeAll(); error = nil } } }
        }
    }
    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack { if message.role != "user" { Spacer(minLength: 35) }
            Text(message.content).textSelection(.enabled).padding(13).foregroundStyle(.white).background(message.role == "user" ? FinFlowTheme.accent : FinFlowTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            if message.role == "user" { Spacer(minLength: 35) }
        }
    }
    private func send() async {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !content.isEmpty, !isSending else { return }
        input = ""; error = nil
        messages.append(ChatMessage(content: content, role: "user")); isSending = true
        defer { isSending = false }
        do {
            let result: AdvisorResponse = try await APIClient.shared.request("/ai/chat", method: "POST", body: AdvisorRequest(mensaje: content))
            messages.append(ChatMessage(content: result.respuesta, role: "assistant"))
        } catch { self.error = error.localizedDescription; messages.append(ChatMessage(content: "No pude procesar la consulta. Inténtalo de nuevo.", role: "assistant")) }
    }
}
