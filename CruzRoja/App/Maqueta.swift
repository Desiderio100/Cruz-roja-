// MAQUETA: solo diseño, no hace nada. Cuando Emergencia y Donar estén listos,
// conéctalos aquí o borra este archivo y `MaquetaInicio()` de PantallaPrincipal.

import SwiftUI

struct MaquetaInicio: View {
    var body: some View {
        VStack(spacing: 14) {
            Button {} label: {
                Text("Emergencia,\nun solo toque")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color.rojoCruzRoja, in: RoundedRectangle(cornerRadius: 18))
            }

            Button("Donar") {}
                .buttonStyle(BotonBorde())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MaquetaInicio().padding()
}
