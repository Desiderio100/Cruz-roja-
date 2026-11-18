// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
//
//  EmergenciaBoton.swift
//  Botón rojo de EMERGENCIA (diseño de Ayhan). Lo usa EmergenciaInicio.
//
//  Al tocarlo cuenta 3 segundos antes de llamar, para evitar llamadas sin querer.
//  Si se toca otra vez durante la cuenta, se cancela.
//
//  La imagen de la ambulancia sale de Assets › Ambulancia.
//

import SwiftUI

struct EmergenciaBoton: View {
    let estaConectando: Bool
    let action: () -> Void

    /// Segundos que espera antes de llamar.
    private static let segundosEspera = 3

    /// Segundos que faltan para llamar; nil si no está contando.
    @State private var cuenta: Int?
    @State private var tareaCuenta: Task<Void, Never>?
    /// Dónde está el botón en la pantalla, para dejarlo nítido mientras cuenta.
    @State private var marco: CGRect = .zero
    @Environment(EnfoqueEmergencia.self) private var enfoque: EnfoqueEmergencia?

    var body: some View {
        Button(action: tocar) {
            VStack(spacing: 8) {
                if estaConectando {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .frame(height: 96)
                } else if let cuenta {
                    Text("\(cuenta)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(countsDown: true))
                        .frame(height: 96)
                } else {
                    Image("Ambulancia")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 96)
                        .accessibilityHidden(true)
                }

                Text(cuenta == nil ? "Botón de emergencia" : "Llamando a emergencias…")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if estaConectando {
                    Text("Conectando con la delegación…")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                } else if cuenta != nil {
                    Text("Toca otra vez para cancelar")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color.rojoCruzRoja, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.rojoCruzRoja.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(BotonEmergenciaEstilo())
        .disabled(estaConectando)
        .sensoryFeedback(.impact(weight: .heavy), trigger: cuenta)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { marco = $0 }
        .onChange(of: cuenta == nil) { _, sinCuenta in
            withAnimation(.easeInOut(duration: 0.25)) {
                enfoque?.zona = sinCuenta ? nil : marco
            }
        }
        .onDisappear(perform: cancelar)
        .accessibilityLabel(cuenta.map { "Llamando a emergencias en \($0) segundos" } ?? "Emergencia")
        .accessibilityHint(cuenta == nil
                           ? "Inicia una llamada de emergencia después de 3 segundos"
                           : "Toca para cancelar la llamada")
    }

    /// Primer toque: empieza la cuenta. Toque durante la cuenta: la cancela.
    private func tocar() {
        guard cuenta == nil else {
            cancelar()
            return
        }
        withAnimation { cuenta = Self.segundosEspera }
        tareaCuenta = Task { @MainActor in
            while let restante = cuenta, restante > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation { cuenta = restante - 1 }
            }
            cuenta = nil
            action()
        }
    }

    private func cancelar() {
        tareaCuenta?.cancel()
        tareaCuenta = nil
        withAnimation { cuenta = nil }
    }
}

// MARK: - Pantalla borrosa durante la cuenta

/// Lo comparte la pantalla principal con el botón: mientras cuenta, `zona` es el lugar
/// del botón (en coordenadas de toda la pantalla); si no, nil.
@Observable
final class EnfoqueEmergencia {
    var zona: CGRect?
}

extension View {
    /// Pone borrosa toda la pantalla, menos el botón de emergencia, mientras cuenta.
    /// Va en la pantalla que contiene el botón (por fuera del NavigationStack para tapar la barra).
    func borrosaSalvoEmergencia(_ enfoque: EnfoqueEmergencia) -> some View {
        overlay {
            if let zona = enfoque.zona {
                FondoBorroso(zona: zona)
                    .transition(.opacity)
            }
        }
        .environment(enfoque)
    }
}

private struct FondoBorroso: View {
    let zona: CGRect

    var body: some View {
        GeometryReader { geo in
            let origen = geo.frame(in: .global).origin
            let forma = FormaConHueco(hueco: zona.offsetBy(dx: -origen.x, dy: -origen.y))
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(forma.fill(style: FillStyle(eoFill: true)))
                // Bloquea los toques fuera del botón; el botón se sigue pudiendo tocar (cancelar).
                .contentShape(forma, eoFill: true)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Toda la pantalla con un hueco redondeado del tamaño del botón.
private struct FormaConHueco: Shape {
    let hueco: CGRect

    func path(in rect: CGRect) -> Path {
        var camino = Path(rect)
        camino.addRoundedRect(in: hueco, cornerSize: CGSize(width: 24, height: 24), style: .continuous)
        return camino
    }
}

private struct BotonEmergenciaEstilo: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        EmergenciaBoton(estaConectando: false) { }
        EmergenciaBoton(estaConectando: true) { }
    }
    .padding()
}
