// Las tarjetas salen de Secciones.swift: para agregar una pantalla nueva
// NO hace falta editar este archivo.

import SwiftUI

struct PantallaPrincipal: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LogoCruzRoja()
                        .padding(.top, 16)

                    Text("¿En qué\npodemos ayudarte?")
                        .font(.largeTitle.bold())
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    MaquetaInicio()
                        .padding(.bottom, 16)

                    Text("Información")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)

                    ForEach(Secciones.todas) { seccion in
                        NavigationLink {
                            seccion.pantalla()
                        } label: {
                            AccesoRapido(seccion: seccion)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color.rojoCruzRoja)
    }
}

/// Logo oficial. Para que aparezca: arrastra el PNG/PDF oficial de Cruz Roja
/// Mexicana a Assets › LogoCruzRoja. Mientras no exista, no se muestra nada.
private struct LogoCruzRoja: View {
    var body: some View {
        if UIImage(named: "LogoCruzRoja") != nil {
            Image("LogoCruzRoja")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .accessibilityLabel("Cruz Roja Mexicana")
        }
    }
}

private struct AccesoRapido: View {
    let seccion: Seccion

    var body: some View {
        HStack {
            Text(seccion.titulo)
                .font(.title3.bold())
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHint(seccion.detalle)
    }
}

#Preview {
    PantallaPrincipal()
        .environment(Ubicacion())
        .environment(CapacitacionModelo())
        .environment(Internet())
}
