//
//  ProductosCausaView.swift
//  Ventas
//
//  Created by Sebastián Martinez on 20/10/26.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Estado de la pantalla

final class ProductosViewModel: ObservableObject {
    enum Estado {
        case cargando
        case listo([Producto])
        case error(String)
    }

    @Published private(set) var estado: Estado = .cargando
    private let repositorio: ProductosRepositorio

    init(repositorio: ProductosRepositorio = ProductosAPI()) {
        self.repositorio = repositorio
    }

    @MainActor
    func cargar() async {
        if case .listo = estado {
            // ya hay productos en pantalla (jalar para actualizar): no los borres mientras carga
        } else {
            estado = .cargando
        }
        do {
            estado = .listo(try await repositorio.productos())
        } catch {
            if Task.isCancelled { return }
            let mensaje = (error as? ProductosError)?.mensaje ?? "No pudimos cargar los productos. Intenta más tarde."
            estado = .error(mensaje)
        }
    }
}

// MARK: - Pantalla

struct ProductosCausaView: View {
    @StateObject private var vm: ProductosViewModel
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    init(repositorio: ProductosRepositorio = ProductosAPI()) {
        _vm = StateObject(wrappedValue: ProductosViewModel(repositorio: repositorio))
    }

    var body: some View {
        contenido
            .pantalla("Productos con causa")
            .task { await vm.cargar() }
    }

    @ViewBuilder
    private var contenido: some View {
        switch vm.estado {
        case .cargando:
            ProgressView("Cargando productos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let texto):
            mensaje(texto, conReintento: true)
        case .listo(let productos) where productos.isEmpty:
            mensaje("Por ahora no hay productos disponibles.", conReintento: false)
        case .listo(let productos):
            ScrollView {
                Text("Cada compra apoya una causa de Cruz Roja.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Medida.margen)
                    .padding(.bottom, 8)

                LazyVGrid(columns: columnas, spacing: 12) {
                    ForEach(productos) { producto in
                        ProductoTarjeta(producto: producto)
                    }
                }
                .padding(.horizontal, Medida.margen)

                Text("Pagas con tarjeta dentro de la app y te lo enviamos a domicilio. El pago lo procesa Stripe: la app no guarda los datos de tu tarjeta.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .refreshable { await vm.cargar() }
        }
    }

    // Una columna cuando el texto del sistema está muy grande.
    private var columnas: [GridItem] {
        let cantidad = tamanoTexto.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: cantidad)
    }

    private func mensaje(_ texto: String, conReintento: Bool) -> some View {
        VStack(spacing: 12) {
            Text(texto)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if conReintento {
                Button("Reintentar") {
                    Task { await vm.cargar() }
                }
                .buttonStyle(BotonRojo())
                .frame(maxWidth: 220)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tarjeta de producto

struct ProductoTarjeta: View {
    let producto: Producto
    @State private var comprando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imagen
            Text(producto.nombre)
                .font(.subheadline.weight(.bold))
            Text(producto.precioTexto)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.rojoCruzRoja)
            Text(producto.causa)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)

            // Antes este botón abría el canal oficial en el navegador (Link a producto.enlaceCompra).
            // Ahora abre la hoja de compra con pago dentro de la app.
            Button {
                comprando = true
            } label: {
                HStack(spacing: 6) {
                    Text("Comprar")
                    Image(systemName: "creditcard")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.rojoCruzRoja, in: RoundedRectangle(cornerRadius: Medida.radio, style: .continuous))
            }
            .accessibilityLabel("Comprar \(producto.nombre)")
            .accessibilityHint("Abre la compra con pago con tarjeta y envío a domicilio")
        }
        .tarjetaConBorde()
        .sheet(isPresented: $comprando) {
            CompraView(producto: producto)
        }
    }

    private var imagen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.fondoTarjeta)
            AsyncImage(url: producto.imagenURL) { fase in
                switch fase {
                case .success(let foto):
                    foto
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                default:
                    Cruz()
                        .fill(Color.rojoCruzRoja)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Vista previa

struct ProductosCausaView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProductosCausaView(repositorio: ProductosDeEjemplo())
        }
    }
}
