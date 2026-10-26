// HU01 · "Verifica tu número": la persona escribe el código de 6 dígitos que le llegó por SMS.
// Si es correcto, el servidor guarda el teléfono verificado en su dispositivo y la app
// pasa a Permisos.
//Tonchez

import SwiftUI

struct VerificacionView: View {
    @Environment(SesionUsuario.self) private var sesion
    @Environment(\.dismiss) private var cerrar

    let nombre: String
    let telefono: String

    @State private var codigo = ""
    @State private var trabajando = false
    @State private var espera = 60
    @State private var envios = 0
    @State private var mensajeError: String?
    @FocusState private var enfocado: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Te enviamos un código de 6 dígitos por SMS al \(telefono).")
                    .foregroundStyle(.secondary)

                Campo("Código SMS de verificación") {
                    TextField("000000", text: $codigo)
                        .font(.title2.weight(.semibold).monospaced())
                        .multilineTextAlignment(.center)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($enfocado)
                        .onChange(of: codigo) { _, nuevo in
                            let limpio = String(nuevo.filter { $0.isASCII && $0.isNumber }.prefix(6))
                            if limpio != nuevo { codigo = limpio }
                        }
                }

                Button {
                    verificar()
                } label: {
                    if trabajando { ProgressView().tint(.white) } else { Text("Verificar") }
                }
                .buttonStyle(BotonRojo())
                .disabled(codigo.count != 6 || trabajando)
                .padding(.top, 8)

                Button(espera > 0 ? "Reenviar código en \(espera) s" : "Reenviar código") { reenviar() }
                    .buttonStyle(BotonTexto())
                    .disabled(espera > 0 || trabajando)

                Button("Cambiar número") { cerrar() }
                    .buttonStyle(BotonTexto())
                    .disabled(trabajando)

                Text("El código vence en 5 minutos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                #if DEBUG
                Label("En desarrollo no se manda SMS: el código aparece en la terminal donde corre el backend (npm run dev).",
                      systemImage: "terminal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tarjeta()
                #endif
            }
            .padding(.horizontal, Medida.margen)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .pantalla("Verifica tu número")
        .onAppear { enfocado = true }
        // Cuenta regresiva para reenviar; vuelve a empezar con cada envío.
        .task(id: envios) {
            while espera > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                espera -= 1
            }
        }
        .alert("No se pudo verificar", isPresented: hayError) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(mensajeError ?? "")
        }
    }

    private var hayError: Binding<Bool> {
        Binding(get: { mensajeError != nil }, set: { if !$0 { mensajeError = nil } })
    }

    private func verificar() {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await ClienteAPI.compartido.verificarCodigo(telefono: telefono, codigo: codigo)
                // Marca el registro como listo: la app pasa sola a Permisos.
                sesion.registrar(nombre: nombre, telefono: telefono)
            } catch {
                codigo = ""
                mensajeError = error.localizedDescription
            }
        }
    }

    private func reenviar() {
        trabajando = true
        Task {
            defer { trabajando = false }
            do {
                try await ClienteAPI.compartido.enviarCodigo(telefono: telefono)
                codigo = ""
                espera = 60
                envios += 1
            } catch {
                mensajeError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        VerificacionView(nombre: "Ana", telefono: "8112345678")
    }
    .environment(SesionUsuario())
}
