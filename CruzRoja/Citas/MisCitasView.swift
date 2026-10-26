import SwiftUI

// Pantalla Mis citas (Luis).
struct MisCitasView: View {
    @StateObject private var vm = MisCitasViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                contenido
                    .padding(.horizontal, Medida.margen)
                    .padding(.vertical, 8)
            }
            .refreshable { await vm.cargar() }

            NavigationLink {
                AgendaView()
            } label: {
                Text("Agendar nueva cita")
            }
            .buttonStyle(BotonRojo())
            .padding(.horizontal, Medida.margen)
            .padding(.vertical, 12)
        }
        .pantalla("Mis citas")
        .task { await vm.cargar() }
        .alert("¿Cancelar tu cita?", isPresented: preguntandoCancelar, presenting: vm.citaPorCancelar) { cita in
            Button("Sí, cancelar cita", role: .destructive) {
                Task { await vm.cancelar(cita) }
            }
            Button("Conservar cita", role: .cancel) { }
        } message: { cita in
            Text("\(cita.nombreServicio), \(Formato.fechaYRango(cita.inicio)). El horario quedará libre para otra persona.")
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

    private var preguntandoCancelar: Binding<Bool> {
        Binding(
            get: { vm.citaPorCancelar != nil },
            set: { if !$0 { vm.citaPorCancelar = nil } }
        )
    }

    @ViewBuilder
    private var contenido: some View {
        if !vm.cargadoUnaVez {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if vm.citas.isEmpty {
            Text(vm.fallo ? "No se pudieron cargar tus citas." : "Todavía no tienes citas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(spacing: 12) {
                ForEach(vm.citas) { cita in
                    if cita.estaPospuesta {
                        tarjetaPospuesta(cita)
                    } else {
                        tarjeta(cita)
                    }
                }
            }
        }
    }

    private func encabezado(_ cita: Cita) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cita.nombreServicio)
                .font(.headline)
            Text("Folio \(cita.folio)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tarjeta(_ cita: Cita) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado(cita)

            Label(Formato.fechaYRango(cita.inicio), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))

            Button("Cancelar cita") {
                vm.citaPorCancelar = cita
            }
            .buttonStyle(BotonBorde())
            .disabled(vm.cancelando)
        }
        .tarjetaConBorde()
    }

    // Las citas pospuestas llevan borde rojo y el botón para elegir nuevo horario.
    private func tarjetaPospuesta(_ cita: Cita) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                encabezado(cita)
                Spacer()
                Text("Pospuesta")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.rojoCruzRoja)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(Color.rojoCruzRoja, lineWidth: 1.5))
            }

            Text(Formato.fechaYRango(cita.inicio))
                .font(.subheadline)
                .strikethrough()
                .foregroundStyle(.secondary)

            NavigationLink {
                AgendaView(reprogramando: cita)
            } label: {
                Text("Elegir nuevo horario")
            }
            .buttonStyle(BotonRojo())
        }
        .tarjetaConBorde(.rojoCruzRoja, grosor: 1.5)
    }
}

#Preview {
    NavigationStack {
        MisCitasView()
    }
}
