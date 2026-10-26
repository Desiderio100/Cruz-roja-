// Mi perfil (botón de la persona en la pantalla principal): tus datos, tus permisos y,
// para probar, reiniciar la configuración inicial (HU01).

import SwiftUI

struct PerfilView: View {
    @Environment(SesionUsuario.self) private var sesion
    @Environment(\.dismiss) private var cerrar
    @State private var confirmarReinicio = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    datos
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permisos").font(.headline)
                        ListaPermisos()
                    }
                    Button("Reiniciar configuración inicial") { confirmarReinicio = true }
                        .buttonStyle(BotonTexto())
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 24)
            }
            .pantalla("Mi perfil")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
            .confirmationDialog("¿Borrar tus datos de este iPhone?", isPresented: $confirmarReinicio,
                                titleVisibility: .visible) {
                Button("Borrar y empezar de nuevo", role: .destructive) {
                    sesion.reiniciar()
                    cerrar()
                }
            } message: {
                Text("Se borran tu nombre, tu teléfono y el registro de este dispositivo. Sirve para probar el registro desde cero.")
            }
        }
    }

    @ViewBuilder
    private var datos: some View {
        let nombre = Perfil.nombre
        let telefono = Perfil.telefono
        VStack(alignment: .leading, spacing: 10) {
            if nombre.isEmpty && telefono.isEmpty {
                Text("No te has registrado")
                    .font(.headline)
                Text("Puedes pedir ayuda igual. Si te registras, tu nombre y tu número llegan solos al operador cuando llamas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label(nombre.isEmpty ? "Sin nombre" : nombre, systemImage: "person.fill")
                    .font(.headline)
                Label(telefono.isEmpty ? "Sin teléfono" : telefono, systemImage: "phone.fill")
                if sesion.telefonoVerificado {
                    Label("Número verificado por SMS", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
            }
            if !sesion.telefonoVerificado {
                Button("Registrarme y verificar mi número") {
                    cerrar()
                    sesion.volverARegistrarme()
                }
                .buttonStyle(BotonRojo())
                .padding(.top, 4)
            }
        }
        .tarjeta()
    }
}

#Preview {
    PerfilView()
        .environment(SesionUsuario())
        .environment(GestorPermisos())
}
