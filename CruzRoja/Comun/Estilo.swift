// Regla: fondo blanco, rojo solo para lo importante. Si cambia el diseño, se cambia aquí.

import SwiftUI

extension Color {
    static let rojoCruzRoja = Color(red: 170 / 255, green: 63 / 255, blue: 52 / 255) // #AA3F34
    static let fondoTarjeta = Color(uiColor: .secondarySystemBackground)
}

struct BotonRojo: ButtonStyle {
    @Environment(\.isEnabled) private var habilitado

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(habilitado ? Color.rojoCruzRoja : Color.gray.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct BotonBorde: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.rojoCruzRoja)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rojoCruzRoja, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func tarjeta() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 14))
    }
}
