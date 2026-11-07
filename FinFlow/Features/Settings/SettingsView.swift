import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingLogout = false
    @AppStorage("finflow.appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            ScreenBackground {
                Form {
                    Section("Cuenta") {
                        LabeledContent("Nombre", value: session.user?.name ?? "Usuario")
                        LabeledContent("Correo", value: session.user?.email ?? "")
                        Button("Cerrar sesión", role: .destructive) { showingLogout = true }
                    }
                    Section("Apariencia") {
                        Picker("Tema", selection: $appearance) {
                            Text("Del sistema").tag("system")
                            Text("Claro").tag("light")
                            Text("Oscuro").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Conexión segura") {
                        Label("Servidor oficial de FinFlow", systemImage: "lock.shield")
                        Text(APIClient.shared.baseURL).font(.caption).foregroundStyle(.secondary)
                        Text("Por seguridad, la app no envía tus credenciales a servidores personalizados.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Acerca de") {
                        LabeledContent("Aplicación", value: "FinFlow iOS")
                        LabeledContent("Versión", value: "1.0.0")
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Ajustes")
            .confirmationDialog("¿Cerrar sesión?", isPresented: $showingLogout, titleVisibility: .visible) { Button("Cerrar sesión", role: .destructive) { session.logout() }; Button("Cancelar", role: .cancel) {} } message: { Text("Se eliminará la sesión guardada de este dispositivo.") }
        }
    }
}
