// Parte de arriba de la pantalla principal:
//   • EMERGENCIA: botón + llamada (Emergencia/). No pide cuenta.
//   • Donar: abre el canal oficial de Cruz Roja en el navegador (Configuracion.urlDonar).

import SwiftUI

struct BotonesInicio: View {
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        VStack(spacing: 12) {
            EmergenciaInicio()

            Button {
                abrirURL(Configuracion.urlDonar)
            } label: {
                Label("Donar", systemImage: "heart.fill")
            }
            .buttonStyle(BotonBorde())
            .accessibilityHint("Abre el sitio oficial de Cruz Roja Mexicana")
        }
    }
}

#Preview {
    BotonesInicio()
        .padding()
        .environment(Ubicacion())
        .environment(Internet())
}
