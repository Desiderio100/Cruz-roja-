import SwiftUI

// Pantalla Agenda de citas (Luis). También sirve para elegir nuevo horario de una cita pospuesta.
struct AgendaView: View {
    @StateObject private var vm: AgendaViewModel
    @Environment(\.dismiss) private var cerrar

    init(reprogramando cita: Cita? = nil) {
        _vm = StateObject(wrappedValue: AgendaViewModel(reprogramando: cita))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !vm.esReprogramacion {
                        selectorServicio.padding(.top, 8)
                    }
                    titulo("Elige el día").padding(.top, 20)
                    selectorDia.padding(.top, 8)
                    titulo("Horarios disponibles").padding(.top, 20)
                    cuadriculaHorarios.padding(.top, 8)
                    tarjetaPrecio.padding(.top, 16)
                    if vm.mostrarAviso {
                        aviso.padding(.top, 12)
                    }
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 16)
            }

            Button {
                Task { await vm.confirmar() }
            } label: {
                Text(vm.enviando ? "Confirmando…" : "Confirmar cita")
            }
            .buttonStyle(BotonRojo())
            .disabled(!vm.puedeConfirmar)
            .padding(.horizontal, Medida.margen)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .pantalla(vm.esReprogramacion ? "Nuevo horario" : "Agenda de citas")
        .toolbar {
            if !vm.esReprogramacion {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MisCitasView()
                    } label: {
                        Label("Mis citas", systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .task(id: vm.clave) { await vm.cargarHorarios() }
        .sheet(isPresented: $vm.pidiendoPerfil) {
            PerfilFormView {
                Task { await vm.confirmar() }
            }
        }
        .alert(
            vm.esReprogramacion ? "Cita reprogramada" : "Cita agendada",
            isPresented: Binding(
                get: { vm.citaConfirmada != nil },
                set: { if !$0 { vm.citaConfirmada = nil } }
            )
        ) {
            Button("Listo") { cerrar() }
        } message: {
            if let cita = vm.citaConfirmada {
                Text("\(cita.nombreServicio)\n\(Formato.fechaYRango(cita.inicio))\nFolio \(cita.folio)")
            }
        }
        .alert(
            "No se pudo completar",
            isPresented: Binding(
                get: { vm.mensajeError != nil },
                set: { if !$0 { vm.mensajeError = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(vm.mensajeError ?? "")
        }
    }

    private func titulo(_ texto: String) -> some View {
        Text(texto)
            .font(.headline)
    }

    private var selectorServicio: some View {
        HStack(spacing: 8) {
            ForEach(Servicio.allCases) { opcion in
                Button {
                    vm.servicio = opcion
                } label: {
                    Text(opcion.nombre)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .ficha(seleccionada: vm.servicio == opcion)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectorDia: some View {
        HStack(spacing: 8) {
            ForEach(Array(vm.dias.enumerated()), id: \.offset) { indice, dia in
                Button {
                    vm.diaElegido = indice
                } label: {
                    VStack(spacing: 2) {
                        Text(Formato.etiquetaDia(dia))
                            .font(.caption.weight(.medium))
                        Text(Formato.numeroDia(dia))
                            .font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .ficha(seleccionada: vm.diaElegido == indice)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var cuadriculaHorarios: some View {
        if vm.cargando && vm.horarios.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 96)
        } else if vm.horarios.isEmpty {
            Text("No hay horarios disponibles ese día.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(vm.horarios) { horario in
                    Button {
                        vm.horarioElegido = horario.inicio
                    } label: {
                        Text(Formato.rango(horario.inicio))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .ficha(seleccionada: vm.horarioElegido == horario.inicio)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Tarjeta con la duración y el costo.
    private var tarjetaPrecio: some View {
        HStack(spacing: 0) {
            dato("Duración", "50 minutos")
            Divider()
            dato("Costo", "$150 MXN")
        }
        .padding(.vertical, 2)
        .tarjetaConBorde()
    }

    private func dato(_ titulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(valor)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // Aviso de que una emergencia mayor puede posponer la cita.
    private var aviso: some View {
        Label("Si llega una emergencia mayor, tu cita puede posponerse. Te avisaremos para que elijas otro horario.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .tarjetaConBorde()
    }
}

#Preview {
    NavigationStack {
        AgendaView()
    }
}
