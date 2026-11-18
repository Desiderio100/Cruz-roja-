import SwiftUI

/// Pantalla de Capacitación: pestaña Cursos (HU14) y pestaña Aprende (primeros auxilios).
struct CapacitacionView: View {
    enum Parte: String, CaseIterable { case cursos = "Cursos", aprende = "Aprende" }
    @State private var parte: Parte = .cursos

    var body: some View {
        VStack(spacing: 0) {
            Picker("Parte", selection: $parte) {
                ForEach(Parte.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Medida.margen)
            .padding(.vertical, 8)

            switch parte {
            case .cursos: ListaCursosView()
            case .aprende: AprendeView()
            }
        }
        .pantalla("Capacitación")
    }
}

// MARK: - Mis inscripciones + lista de cursos

/// Mis inscripciones (con folio) y los próximos cursos con fecha y lugares disponibles.
/// Los cursos se descargan del backend al entrar y al jalar la lista hacia abajo.
struct ListaCursosView: View {
    @Environment(CapacitacionModelo.self) private var capacitacion
    @Environment(Internet.self) private var internet

    var body: some View {
        List {
            if !internet.hayConexion {
                AvisoSinInternet("tus inscripciones se ven igual; los lugares pueden haber cambiado")
                    .listRowSeparator(.hidden)
            } else if capacitacion.errorDeCarga != nil, !capacitacion.cursos.isEmpty {
                // Hay internet pero el servidor no respondió: se ve la última lista guardada.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("No pudimos actualizar los cursos. Ves la última lista guardada.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    botonReintentarCarga
                }
                .font(.footnote.bold())
                .listRowSeparator(.hidden)
            }

            if !capacitacion.inscripciones.isEmpty {
                Section("Mis inscripciones") {
                    ForEach(capacitacion.inscripciones) { inscripcion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(inscripcion.titulo).font(.headline)
                            Label(inscripcion.fecha.textoCurso, systemImage: "calendar")
                            Label(inscripcion.sede, systemImage: "mappin")
                            Label("Folio \(inscripcion.folio)", systemImage: "checkmark.seal.fill")
                                .bold()
                                .foregroundStyle(.green)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                        // VoiceOver lee la inscripción completa de una vez, no etiqueta por etiqueta.
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Próximos cursos") {
                if capacitacion.cursos.isEmpty {
                    sinCursos
                }
                ForEach(capacitacion.cursos) { curso in
                    NavigationLink {
                        DetalleCursoView(cursoId: curso.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(curso.titulo).font(.headline)
                            Label(curso.textoFecha, systemImage: "calendar")
                            Label(curso.sede, systemImage: "mappin")
                            if capacitacion.folio(de: curso.id) != nil {
                                Text("Ya estás inscrito").bold().foregroundStyle(.green)
                            } else {
                                Text(curso.textoLugares).bold()
                                    .foregroundStyle(curso.estaLleno ? Color.secondary : Color.rojoCruzRoja)
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await capacitacion.cargar() }
        .task { await capacitacion.cargar() }
    }

    /// Lo que se ve cuando todavía no hay cursos: cargando, error o lista vacía.
    @ViewBuilder
    private var sinCursos: some View {
        if capacitacion.cargando {
            HStack(spacing: 10) {
                ProgressView()
                Text("Cargando cursos…").foregroundStyle(.secondary)
            }
        } else if let error = capacitacion.errorDeCarga {
            VStack(alignment: .leading, spacing: 8) {
                Label("No pudimos cargar los cursos", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                botonReintentarCarga.bold()
            }
            .padding(.vertical, 4)
        } else {
            Text("Por ahora no hay cursos programados.")
                .foregroundStyle(.secondary)
        }
    }

    private var botonReintentarCarga: some View {
        Button("Reintentar") {
            Task { await capacitacion.cargar() }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.rojoCruzRoja)
        .disabled(capacitacion.cargando)
    }
}

// MARK: - Detalle e inscripción

/// Detalle de un curso y formulario de inscripción. Sin internet o sin cupo, no deja inscribirse.
struct DetalleCursoView: View {
    @Environment(CapacitacionModelo.self) private var capacitacion
    @Environment(Internet.self) private var internet
    let cursoId: String

    // Si la persona se registró, ya vienen llenos (Perfil, Comun/Dispositivo.swift).
    @State private var nombre = Perfil.nombre
    @State private var celular = Perfil.telefono
    @State private var folioNuevo: String?
    @State private var error: String?
    /// `true` mientras el servidor contesta la inscripción (evita mandar dos veces).
    @State private var enviando = false

    var body: some View {
        if let curso = capacitacion.cursos.first(where: { $0.id == cursoId }) {
            Form {
                Section {
                    if !curso.descripcion.isEmpty {
                        Text(curso.descripcion)
                    }
                    LabeledContent("Fecha", value: curso.textoFecha)
                    if let duracion = curso.duracion {
                        LabeledContent("Duración", value: duracion)
                    }
                    LabeledContent("Lugar", value: curso.sede)
                    if let costo = curso.textoCosto {
                        LabeledContent("Costo", value: costo)
                    }
                    LabeledContent("Lugares", value: curso.textoLugares)
                }

                if let folio = capacitacion.folio(de: curso.id) {
                    Section {
                        Label("Ya estás inscrito. Folio: \(folio)", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                } else if curso.estaLleno {
                    Section {
                        Label("Curso lleno. Revisa otras fechas.", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Tus datos") {
                        TextField("Nombre completo", text: $nombre)
                            .textContentType(.name)
                        TextField("Celular (10 dígitos)", text: $celular)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }
                    Section {
                        Button(enviando ? "Inscribiendo…" : "Inscribirme") { inscribir(curso) }
                            .buttonStyle(BotonRojo())
                            .disabled(enviando
                                      || !internet.hayConexion
                                      || !CapacitacionModelo.datosValidos(nombre: nombre, celular: celular))
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        if !internet.hayConexion {
                            HStack(alignment: .firstTextBaseline) {
                                Label("Necesitas internet para inscribirte: así apartamos tu lugar de verdad.",
                                      systemImage: "exclamationmark.triangle.fill")
                                BotonReintentar().bold()
                            }
                        }
                    }
                }
            }
            .pantalla(curso.titulo, grande: false)
            .alert("¡Inscripción confirmada!", isPresented: Binding(get: { folioNuevo != nil }, set: { if !$0 { folioNuevo = nil } })) {
                Button("Listo") {}
            } message: {
                Text("Tu folio es \(folioNuevo ?? ""). Lo encuentras en Mis inscripciones, aun sin internet.")
            }
            .alert("No se pudo inscribir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
        } else {
            // El curso dejó de estar en la lista (ya pasó o lo quitaron) mientras se veía su detalle.
            ContentUnavailableView("Este curso ya no está disponible", systemImage: "calendar.badge.exclamationmark")
        }
    }

    /// Manda la inscripción al servidor y muestra el folio o el motivo del error.
    private func inscribir(_ curso: Curso) {
        enviando = true
        Task { @MainActor in
            defer { enviando = false }
            do {
                folioNuevo = try await capacitacion.inscribir(en: curso, nombre: nombre, celular: celular)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { CapacitacionView() }
        .environment(CapacitacionModelo(repositorio: CursosDeEjemplo()))
        .environment(Internet())
}
