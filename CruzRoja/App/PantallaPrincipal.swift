// Pantalla principal (maqueta "Pantalla principal"):
//   ¿En qué podemos ayudarte? · Emergencia · Donar · Accesos rápidos.
// Las filas de Accesos rápidos salen de Secciones.swift: para agregar una pantalla nueva
// NO hace falta editar este archivo.

import SwiftUI

struct PantallaPrincipal: View {
    @State private var viendoPerfil = false
    @State private var enfoqueEmergencia = EnfoqueEmergencia()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("¿En qué podemos ayudarte?")
                        .font(.largeTitle.bold())
                        .padding(.top, 8)

                    BotonesInicio()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accesos rápidos")
                            .font(.headline)

                        ForEach(Secciones.todas) { seccion in
                            NavigationLink {
                                seccion.pantalla()
                            } label: {
                                AccesoRapido(seccion: seccion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 32)
            }
            .logoArriba()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mi perfil", systemImage: "person.crop.circle") { viendoPerfil = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $viendoPerfil) { PerfilView() }
        }
        .borrosaSalvoEmergencia(enfoqueEmergencia)
    }
}

private struct AccesoRapido: View {
    let seccion: Seccion

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: seccion.icono)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.rojoCruzRoja)
                .frame(width: 26)
            Text(seccion.titulo)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: Medida.radio, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityHint(seccion.detalle)
    }
}

#Preview {
    PantallaPrincipal()
        .environment(SesionUsuario())
        .environment(GestorPermisos())
        .environment(Ubicacion())
        .environment(CapacitacionModelo())
        .environment(Internet())
}
