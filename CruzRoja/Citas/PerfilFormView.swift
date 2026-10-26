import SwiftUI

// Pide nombre y teléfono la primera vez que se agenda, solo si la persona omitió el registro
// (si se registró, Perfil ya los tiene). Se guardan en Perfil (Comun/Dispositivo.swift).
struct PerfilFormView: View {
    let alGuardar: () -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var nombre = Perfil.nombre
    @State private var telefono = Perfil.telefono

    private var valido: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty
            && Perfil.telefonoValido(Perfil.limpiarTelefono(telefono))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tus datos")
                .font(.title2.bold())

            Text("Los necesitamos para tu cita. Solo los pedimos esta vez.")
                .foregroundStyle(.secondary)

            Campo("Nombre") {
                TextField("Tu nombre completo", text: $nombre)
                    .textContentType(.name)
            }

            Campo("Teléfono") {
                TextField("10 dígitos", text: $telefono)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            Spacer(minLength: 0)

            Button("Guardar y continuar") {
                Perfil.nombre = nombre.trimmingCharacters(in: .whitespaces)
                Perfil.telefono = Perfil.limpiarTelefono(telefono)
                cerrar()
                alGuardar()
            }
            .buttonStyle(BotonRojo())
            .disabled(!valido)
        }
        .padding(Medida.margen)
        .presentationDetents([.medium])
    }
}
