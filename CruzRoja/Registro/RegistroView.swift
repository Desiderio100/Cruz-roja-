// HU01 · "Crea tu cuenta": nombre y celular → se manda un código por SMS → VerificacionView.
// Es opcional: "Omitir por ahora" entra a la app sin cuenta y la emergencia funciona igual.

import SwiftUI

struct RegistroView: View {
    @Environment(SesionUsuario.self) private var sesion

    @State private var nombre = Perfil.nombre
    @State private var telefono = Perfil.telefono
    @State private var enviando = false
    @State private var verificando = false
    @State private var mensajeError: String?

    private var valido: Bool { ReglasRegistro.datosValidos(nombre: nombre, telefono: telefono) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Para conectarte con Cruz Roja.")
                        .foregroundStyle(.secondary)

                    Campo("Nombre") {
                        TextField("Ingresa tu nombre", text: $nombre)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    Campo("Número celular") {
                        TextField("Ingresa tu número", text: $telefono)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .onChange(of: telefono) { _, nuevo in
                                // El teclado de teléfono deja escribir * y #; se quitan al escribir.
                                let limpio = String(String.UnicodeScalarView(
                                    nuevo.unicodeScalars.filter { ReglasRegistro.caracteresTelefono.contains($0) }))
                                if limpio != nuevo { telefono = limpio }
                            }
                    }

                    Button {
                        enviarCodigo()
                    } label: {
                        if enviando { ProgressView().tint(.white) } else { Text("Continuar") }
                    }
                    .buttonStyle(BotonRojo())
                    .disabled(!valido || enviando)
                    .padding(.top, 8)

                    Button("Omitir por ahora") { sesion.omitirRegistro() }
                        .buttonStyle(BotonTexto())
                        .disabled(enviando)

                    Text("Te enviaremos un SMS para confirmar tu número. Si omites el registro, la llamada de emergencia funciona igual. Al continuar, aceptas nuestra política de privacidad y el uso de tus datos para brindarte ayuda.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .pantalla("Crea tu cuenta")
            .navigationDestination(isPresented: $verificando) {
                VerificacionView(nombre: nombre, telefono: telefono)
            }
            .alert("No se pudo enviar el código", isPresented: hayError) {
                Button("Aceptar", role: .cancel) { }
            } message: {
                Text(mensajeError ?? "")
            }
        }
    }

    private var hayError: Binding<Bool> {
        Binding(get: { mensajeError != nil }, set: { if !$0 { mensajeError = nil } })
    }

    private func enviarCodigo() {
        enviando = true
        Task {
            defer { enviando = false }
            do {
                try await ClienteAPI.compartido.enviarCodigo(telefono: telefono)
                verificando = true
            } catch {
                mensajeError = error.localizedDescription
            }
        }
    }
}

#Preview {
    RegistroView()
        .environment(SesionUsuario())
}
