// Estilo ÚNICO de la app. Todas las pantallas usan lo de aquí para verse igual.
// Si cambia el diseño (el rojo, las esquinas, los botones), se cambia en este archivo.
//
// Regla: fondo blanco, rojo solo para lo importante.
//
//   Botones:   .buttonStyle(BotonRojo())    principal (Continuar, Confirmar…)
//              .buttonStyle(BotonBorde())   secundario (Donar, Cancelar cita…)
//              .buttonStyle(BotonTexto())   enlace rojo (Omitir por ahora, Reenviar…)
//   Tarjetas:  .tarjeta()                   gris, para bloques de información
//              .tarjetaConBorde()           blanca con borde, para elementos de una lista
//   Campos:    Campo("Nombre") { TextField(...) }
//   Fichas:    .ficha(seleccionada:)        opciones para elegir (día, horario, servicio)
//   Pantalla:  .pantalla("Título")          título grande, fondo y logo arriba en medio
//   Logo:      LogoCruzRoja()               (.logoArriba() si la pantalla no tiene título)

import SwiftUI

// MARK: - Colores

extension Color {
    /// El rojo de la app, tomado de las maquetas (#B0241A). Es el ÚNICO rojo: no crees otro.
    static let rojoCruzRoja = Color(red: 176 / 255, green: 36 / 255, blue: 26 / 255)
    /// Gris claro de tarjetas, campos de texto y accesos rápidos.
    static let fondoTarjeta = Color(uiColor: .secondarySystemBackground)
    /// Línea suave para tarjetas con contorno.
    static let borde = Color(uiColor: .separator)
}

// MARK: - Medidas

enum Medida {
    /// Esquinas de botones, tarjetas y campos.
    static let radio: CGFloat = 14
    /// Alto mínimo de los botones (más que 44 para tocarlos fácil en una emergencia).
    static let altoBoton: CGFloat = 52
    /// Margen a los lados de cada pantalla.
    static let margen: CGFloat = 20
    /// Tamaño del logo arriba en medio: el MISMO en todas las pantallas.
    static let logo: CGFloat = 28
}

private var forma: RoundedRectangle {
    RoundedRectangle(cornerRadius: Medida.radio, style: .continuous)
}

// MARK: - Botones

/// Botón principal: fondo rojo y texto blanco. Se pone gris cuando está desactivado.
struct BotonRojo: ButtonStyle {
    @Environment(\.isEnabled) private var habilitado

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Medida.altoBoton)
            .foregroundStyle(.white)
            .background(habilitado ? Color.rojoCruzRoja : Color.gray.opacity(0.45), in: forma)
            .contentShape(forma)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Botón secundario: contorno rojo y fondo blanco.
struct BotonBorde: ButtonStyle {
    @Environment(\.isEnabled) private var habilitado

    func makeBody(configuration: Configuration) -> some View {
        let color = habilitado ? Color.rojoCruzRoja : Color.gray
        return configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Medida.altoBoton)
            .foregroundStyle(color)
            .background(Color(uiColor: .systemBackground), in: forma)
            .overlay(forma.stroke(color, lineWidth: 1.5))
            .contentShape(forma)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Enlace rojo sin fondo: "Omitir por ahora", "Reenviar código"…
struct BotonTexto: ButtonStyle {
    @Environment(\.isEnabled) private var habilitado

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(habilitado ? Color.rojoCruzRoja : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Tarjetas, fichas y pantallas

extension View {
    /// Bloque gris con esquinas redondeadas.
    func tarjeta() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fondoTarjeta, in: forma)
    }

    /// Tarjeta blanca con contorno (citas, productos). Para resaltarla: .tarjetaConBorde(.rojoCruzRoja, grosor: 1.5)
    func tarjetaConBorde(_ color: Color = .borde, grosor: CGFloat = 1) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: forma)
            .overlay(forma.stroke(color, lineWidth: grosor))
    }

    /// Opción que se puede elegir: roja si está elegida, gris si no.
    func ficha(seleccionada: Bool) -> some View {
        foregroundStyle(seleccionada ? Color.white : Color.primary)
            .background(seleccionada ? Color.rojoCruzRoja : Color.fondoTarjeta, in: forma)
            .contentShape(forma)
            .accessibilityAddTraits(seleccionada ? .isSelected : [])
    }

    /// Título de una pantalla. Úsalo en todas para que se vean igual (el botón "‹ Atrás"
    /// lo pone iOS solo). `grande: false` deja el título chico (pantallas con mapa arriba).
    /// Pone el logo arriba en medio; `logo: false` lo quita (el mapa de delegaciones).
    func pantalla(_ titulo: String, grande: Bool = true, logo: Bool = true) -> some View {
        navigationTitle(titulo)
            .navigationBarTitleDisplayMode(grande ? .large : .inline)
            .toolbar {
                if logo {
                    ToolbarItem(placement: .principal) {
                        // En el centro de la barra iOS ya no pinta el título chico,
                        // así que con título chico lo ponemos debajo del logo.
                        VStack(spacing: 0) {
                            LogoCruzRoja(tamano: Medida.logo)
                            if !grande {
                                Text(titulo)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
    }

    /// Solo el logo arriba en medio, para pantallas sin título (la principal).
    func logoArriba() -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                LogoCruzRoja(tamano: Medida.logo)
            }
        }
    }
}

// MARK: - Campo de texto con etiqueta

/// Campo("Nombre") { TextField("Ingresa tu nombre", text: $nombre) }
struct Campo<Contenido: View>: View {
    let etiqueta: String
    let contenido: Contenido

    init(_ etiqueta: String, @ViewBuilder contenido: () -> Contenido) {
        self.etiqueta = etiqueta
        self.contenido = contenido()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(etiqueta)
                .font(.subheadline.weight(.semibold))
            contenido
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Logo

/// Logo de la app. Si alguien pone el logo oficial en Assets › LogoCruzRoja, se usa ese;
/// si no, se dibuja la cruz.
struct LogoCruzRoja: View {
    var tamano: CGFloat = 40

    var body: some View {
        Group {
            if UIImage(named: "LogoCruzRoja") != nil {
                Image("LogoCruzRoja")
                    .resizable()
                    .scaledToFit()
            } else {
                Cruz().fill(Color.rojoCruzRoja)
            }
        }
        .frame(width: tamano, height: tamano)
        .accessibilityLabel("Cruz Roja Mexicana")
    }
}

/// Cruz de brazos iguales, dibujada con código.
struct Cruz: Shape {
    func path(in rect: CGRect) -> Path {
        let lado = min(rect.width, rect.height)
        let brazo = lado / 3
        let x = rect.midX - lado / 2
        let y = rect.midY - lado / 2
        var camino = Path()
        camino.addRect(CGRect(x: x + brazo, y: y, width: brazo, height: lado))
        camino.addRect(CGRect(x: x, y: y + brazo, width: lado, height: brazo))
        return camino
    }
}
