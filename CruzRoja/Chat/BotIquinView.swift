import SwiftUI

struct BotIquinView: View {
    enum Estado {
        case reposo
        case cargando
    }

    let estado: Estado
    var alto: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var arriba = false

    var body: some View {
        Image(estado == .reposo ? "BotIquinReposo" : "BotIquinCargando")
            .resizable()
            .scaledToFit()
            .frame(height: alto)
            .offset(y: arriba ? -alto * 0.03 : 0)
            .overlay(alignment: .topTrailing) {
                if estado == .cargando {
                    PuntosCargando()
                        .scaleEffect(alto / 120, anchor: .topTrailing)
                }
            }
            .onAppear {
                guard !sinMovimiento else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    arriba = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(estado == .reposo ? "Bot-iquin" : "Bot-iquin está pensando")
    }
}

private struct PuntosCargando: View {
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: sinMovimiento)) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.rojoCruzRoja)
                        .frame(width: 7, height: 7)
                        .offset(y: sinMovimiento ? 0 : -3 * max(0, sin(t * 5 - Double(i) * 0.7)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(Color.borde, lineWidth: 1))
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        BotIquinView(estado: .reposo, alto: 140)
        BotIquinView(estado: .cargando, alto: 140)
    }
    .padding()
}
