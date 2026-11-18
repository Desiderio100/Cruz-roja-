#if canImport(FoundationModels)
import SwiftUI

@available(iOS 26.0, *)
struct ChatView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(CapacitacionModelo.self) private var capacitacion
    @Environment(Internet.self) private var internet
    @State private var modelo: ChatModelo?
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            Group {
                if let modelo {
                    contenido(modelo)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Asistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { cerrar() }
                }
            }
        }
        .tint(Color.rojoCruzRoja)
        .task {
            if modelo == nil {
                let acciones = AccionesChat(ubicacion: ubicacion, capacitacion: capacitacion, internet: internet)
                modelo = ChatModelo(acciones: acciones)
            }
        }
    }

    private func contenido(_ modelo: ChatModelo) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { lector in
                ScrollView {
                    VStack(spacing: 12) {
                        if modelo.mensajes.isEmpty {
                            bienvenida(modelo)
                        }
                        ForEach(modelo.mensajes) { mensaje in
                            BurbujaChat(mensaje: mensaje)
                        }
                        if modelo.respondiendo {
                            HStack(spacing: 10) {
                                BotIquinView(estado: .cargando, alto: 64)
                                Text("Pensando…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        if let pendiente = modelo.acciones.pendiente {
                            TarjetaConfirmacion(pendiente: pendiente, modelo: modelo)
                        }
                        Color.clear.frame(height: 1).id("fondo")
                    }
                    .padding(.horizontal, Medida.margen)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: modelo.mensajes.count) { _, _ in
                    withAnimation { lector.scrollTo("fondo") }
                }
                .onChange(of: modelo.respondiendo) { _, _ in
                    withAnimation { lector.scrollTo("fondo") }
                }
                .onChange(of: modelo.acciones.pendiente?.id) { _, _ in
                    withAnimation { lector.scrollTo("fondo") }
                }
            }
            barraEscribir(modelo)
        }
    }

    private func bienvenida(_ modelo: ChatModelo) -> some View {
        VStack(spacing: 16) {
            BotIquinView(estado: .reposo, alto: 150)
            Text(TextosChat.bienvenida)
                .font(.headline)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(TextosChat.sugerencias, id: \.self) { sugerencia in
                    Button {
                        Task { await modelo.enviar(sugerencia) }
                    } label: {
                        Text(sugerencia)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.rojoCruzRoja)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: Medida.radio, style: .continuous)
                                    .stroke(Color.rojoCruzRoja, lineWidth: 1.5)
                            )
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func barraEscribir(_ modelo: ChatModelo) -> some View {
        let puedeEnviar = !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !modelo.respondiendo
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Escribe tu mensaje", text: $texto, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.fondoTarjeta, in: RoundedRectangle(cornerRadius: Medida.radio, style: .continuous))

            Button {
                let mensaje = texto
                texto = ""
                Task { await modelo.enviar(mensaje) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(puedeEnviar ? Color.rojoCruzRoja : Color.gray.opacity(0.4))
            }
            .disabled(!puedeEnviar)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, Medida.margen)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

@available(iOS 26.0, *)
private struct BurbujaChat: View {
    let mensaje: MensajeChat

    private var esPersona: Bool { mensaje.autor == .persona }

    var body: some View {
        HStack {
            if esPersona { Spacer(minLength: 48) }
            contenido
                .font(.body)
                .foregroundStyle(esPersona ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    esPersona ? Color.rojoCruzRoja : Color.fondoTarjeta,
                    in: RoundedRectangle(cornerRadius: Medida.radio, style: .continuous)
                )
            if !esPersona { Spacer(minLength: 48) }
        }
    }

    /// El modelo a veces responde con Markdown (**negritas**, viñetas con "-", títulos con "#").
    /// Se muestran las negritas como negritas y las viñetas como "•"; lo que escribe la persona va tal cual.
    private var contenido: Text {
        guard !esPersona else { return Text(mensaje.texto) }
        let lineas = mensaje.texto.components(separatedBy: "\n").map { linea -> String in
            let sinSangria = linea.drop(while: { $0 == " " })
            let sangria = String(repeating: " ", count: linea.count - sinSangria.count)
            if sinSangria.hasPrefix("- ") || sinSangria.hasPrefix("* ") {
                return sangria + "• " + String(sinSangria.dropFirst(2))
            }
            if sinSangria.hasPrefix("#") {
                return "**" + String(sinSangria.drop(while: { $0 == "#" || $0 == " " })) + "**"
            }
            return linea
        }
        let texto = lineas.joined(separator: "\n")
        let opciones = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let formateado = try? AttributedString(markdown: texto, options: opciones) else { return Text(texto) }
        return Text(formateado)
    }
}

@available(iOS 26.0, *)
private struct TarjetaConfirmacion: View {
    let pendiente: AccionPendiente
    let modelo: ChatModelo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pendiente.titulo)
                .font(.headline)
            Text(pendiente.detalle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if case .elegirRuta = pendiente.tipo {
                ForEach([AppMapa.apple, .google, .waze], id: \.self) { app in
                    Button(app.nombre) {
                        Task { await modelo.elegirApp(app) }
                    }
                    .buttonStyle(BotonRojo())
                    .disabled(modelo.acciones.ejecutando)
                }
            } else {
                Button(pendiente.textoConfirmar) {
                    Task { await modelo.confirmar() }
                }
                .buttonStyle(BotonRojo())
                .disabled(modelo.acciones.ejecutando)
            }
            Button("No, dejarlo así") {
                modelo.descartarPendiente()
            }
            .buttonStyle(BotonBorde())
        }
        .tarjetaConBorde(.rojoCruzRoja, grosor: 1.5)
    }
}
#endif
