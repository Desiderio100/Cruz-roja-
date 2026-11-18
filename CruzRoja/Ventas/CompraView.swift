//
//  CompraView.swift
//  Ventas
//
//  Hoja "Comprar" de un producto con causa: cantidad, datos de envío a domicilio, total y pago
//  con tarjeta en la hoja de Stripe. La lógica está en PagoViewModel.swift.
//

import SwiftUI

struct CompraView: View {
    @StateObject private var vm: PagoViewModel
    @Environment(\.dismiss) private var cerrar

    init(producto: Producto, repositorio: PedidosRepositorio = PedidosAPI()) {
        _vm = StateObject(wrappedValue: PagoViewModel(producto: producto, repositorio: repositorio))
    }

    var body: some View {
        NavigationStack {
            contenido
                .pantalla("Comprar", grande: false)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !vm.ocupado {
                            Button(esFinal ? "Listo" : "Cerrar") { cerrar() }
                        }
                    }
                }
        }
        // Mientras se cobra no se puede cerrar la hoja deslizándola.
        .interactiveDismissDisabled(vm.ocupado)
        .task { await vm.cargarCondiciones() }
        .onChange(of: vm.pedidoParaPagar) { _, pedido in
            guard let pedido else { return }
            // El pedido ya existe en el servidor: ahora sí se abre la hoja de Stripe.
            let modelo = vm
            Task { @MainActor in
                PagoStripe.presentar(pedido) { resultado in
                    Task { await modelo.resultadoDePago(resultado) }
                }
            }
        }
    }

    /// true cuando la compra ya terminó (pagado o en revisión).
    private var esFinal: Bool {
        switch vm.fase {
        case .pagado, .enRevision: return true
        default: return false
        }
    }

    @ViewBuilder
    private var contenido: some View {
        switch vm.fase {
        case .pagado(let pedido):
            pantallaGracias(pedido)
        case .enRevision(let pedido):
            pantallaEnRevision(pedido)
        case .confirmando:
            pantallaEspera
        case .editando, .preparando, .listoParaPagar:
            formulario
        }
    }

    // MARK: - Formulario

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                resumenProducto

                switch vm.disponibilidad {
                case .consultando:
                    ProgressView("Revisando el costo de envío…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                case .sinConexion(let texto):
                    avisoConReintento(texto)
                case .noDisponible:
                    avisoNoDisponible
                case .disponible:
                    selectorCantidad
                    datosDeEnvio
                    totales
                    avisoPrivacidad
                }
            }
            .padding(.horizontal, Medida.margen)
            .padding(.bottom, 16)
            .disabled(vm.ocupado)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { zonaDelBoton }
    }

    private var resumenProducto: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.producto.nombre)
                .font(.headline)
            Text(vm.producto.precioTexto)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.rojoCruzRoja)
            Text(vm.producto.causa)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .tarjeta()
        .accessibilityElement(children: .combine)
    }

    private var selectorCantidad: some View {
        Stepper(value: $vm.cantidad, in: 1...vm.cantidadMaxima) {
            Text("Cantidad: \(vm.cantidad)")
                .font(.subheadline.weight(.semibold))
        }
        .tarjeta()
    }

    private var datosDeEnvio: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Envío a domicilio")
                .font(.title3.bold())

            Campo("Nombre de quien recibe") {
                TextField("Nombre completo", text: $vm.datos.nombre)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }
            Campo("Teléfono") {
                TextField("10 dígitos", text: $vm.datos.telefono)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            Campo("Calle y número") {
                TextField("Av. Juárez 100", text: $vm.datos.calleNumero)
                    .textContentType(.streetAddressLine1)
                    .textInputAutocapitalization(.words)
            }
            Campo("Colonia") {
                TextField("Colonia", text: $vm.datos.colonia)
                    .textInputAutocapitalization(.words)
            }
            Campo("Ciudad") {
                TextField("Ciudad", text: $vm.datos.ciudad)
                    .textContentType(.addressCity)
                    .textInputAutocapitalization(.words)
            }
            Campo("Estado") {
                TextField("Estado", text: $vm.datos.entidad)
                    .textContentType(.addressState)
                    .textInputAutocapitalization(.words)
            }
            Campo("Código postal") {
                TextField("5 dígitos", text: $vm.datos.codigoPostal)
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
            }
            Campo("Referencias (opcional)") {
                TextField("Entre qué calles, color de la casa…", text: $vm.datos.referencias)
            }
        }
    }

    private var totales: some View {
        VStack(spacing: 8) {
            filaDeTotal("Productos (\(vm.cantidad))", centavos: vm.subtotalCentavos)
            filaDeTotal("Envío a domicilio", centavos: vm.envioCentavos)
            Divider()
            filaDeTotal("Total", centavos: vm.totalCentavos, destacada: true)
        }
        .tarjeta()
    }

    private func filaDeTotal(_ etiqueta: String, centavos: Int?, destacada: Bool = false) -> some View {
        HStack {
            Text(etiqueta)
            Spacer()
            Text(centavos.map { Dinero.texto(centavos: $0) } ?? "—")
        }
        .font(destacada ? .headline : .subheadline)
        .foregroundStyle(destacada ? Color.rojoCruzRoja : Color.primary)
        .accessibilityElement(children: .combine)
    }

    private var avisoPrivacidad: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("El pago lo procesa Stripe. La app no guarda los datos de tu tarjeta.", systemImage: "lock.fill")
            Text("Usamos tu nombre, teléfono y dirección solo para entregar tu pedido.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: - Avisos

    private func avisoConReintento(_ texto: String) -> some View {
        VStack(spacing: 12) {
            Text(texto)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Reintentar") {
                Task { await vm.cargarCondiciones() }
            }
            .buttonStyle(BotonRojo())
        }
        .padding(.vertical, 16)
    }

    /// Pagos apagados en el servidor (o Stripe sin agregar a la app). La compra solo ocurre aquí en
    /// la app: no hay otro canal al que mandar a la persona, así que se avisa y se deja reintentar.
    private var avisoNoDisponible: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("La compra dentro de la app no está disponible por ahora.")
                .font(.subheadline.weight(.semibold))
            Text("Intenta de nuevo más tarde. Si el problema sigue, avisa a Cruz Roja.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Reintentar") {
                Task { await vm.cargarCondiciones() }
            }
            .buttonStyle(BotonBorde())
        }
        .tarjeta()
    }

    // MARK: - Botón de pago

    private var zonaDelBoton: some View {
        VStack(spacing: 8) {
            if let error = vm.mensajeError {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.rojoCruzRoja)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error. \(error)")
            } else if let ayuda = vm.ayuda, vm.disponibilidad == .disponible, !vm.ocupado {
                Text(ayuda)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if vm.disponibilidad == .disponible {
                Button {
                    Task { await vm.pagar() }
                } label: {
                    Text(textoDelBoton)
                }
                .buttonStyle(BotonRojo())
                .disabled(!vm.puedePagar)
            }
        }
        .padding(.horizontal, Medida.margen)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var textoDelBoton: String {
        switch vm.fase {
        case .preparando: return "Preparando el pago…"
        case .listoParaPagar: return "Abriendo el pago…"
        default:
            if let total = vm.totalCentavos { return "Pagar \(Dinero.texto(centavos: total))" }
            return "Pagar"
        }
    }

    // MARK: - Pantallas finales

    private var pantallaEspera: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Confirmando tu pago…")
                .font(.title3.bold())
            Text("No cierres la app. Esto tarda unos segundos.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(Medida.margen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func pantallaGracias(_ pedido: Pedido) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.rojoCruzRoja)
                .accessibilityHidden(true)
            Text("¡Gracias por tu compra!")
                .font(.title2.bold())
            Text("Recibimos tu pago. Guarda este folio para dar seguimiento a tu pedido:")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(pedido.folio)
                .font(.title3.monospaced().bold())
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(pedido.cantidad) × \(pedido.productoNombre)")
                    .font(.subheadline.weight(.semibold))
                Text("Total pagado: \(pedido.totalTexto)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .tarjeta()
            Spacer(minLength: 0)
            Button("Listo") { cerrar() }
                .buttonStyle(BotonRojo())
        }
        .padding(Medida.margen)
        .accessibilityElement(children: .contain)
    }

    private func pantallaEnRevision(_ pedido: Pedido) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.rojoCruzRoja)
                .accessibilityHidden(true)
            Text("Estamos confirmando tu pago")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Tu pago llegó a Stripe, pero todavía no lo vemos reflejado. No vuelvas a pagar. Si pasan unos minutos, comunícate con Cruz Roja y menciona tu folio:")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(pedido.folio)
                .font(.title3.monospaced().bold())
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Revisar de nuevo") {
                Task { await vm.revisarDeNuevo() }
            }
            .buttonStyle(BotonRojo())
            Button("Cerrar") { cerrar() }
                .buttonStyle(BotonTexto())
        }
        .padding(Medida.margen)
    }
}

// MARK: - Vista previa

struct CompraView_Previews: PreviewProvider {
    static var previews: some View {
        CompraView(producto: Producto.ejemplos[0], repositorio: PedidosDeEjemplo())
    }
}
