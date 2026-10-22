// Uso:
//     @Environment(Internet.self) private var internet
//     if !internet.hayConexion { AvisoSinInternet("la lista de centros sigue funcionando") }

import SwiftUI

struct AvisoSinInternet: View {
    let queSiFunciona: String
    init(_ queSiFunciona: String) { self.queSiFunciona = queSiFunciona }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Sin internet · \(queSiFunciona)")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            BotonReintentar()
        }
        .font(.footnote.bold())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BotonReintentar: View {
    @Environment(Internet.self) private var internet

    var body: some View {
        Button(internet.revisando ? "Revisando…" : "Reintentar") {
            Task { await internet.revisar() }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.rojoCruzRoja)
        .disabled(internet.revisando)
    }
}
