//
//  ProductosAPI.swift
//  Ventas
//
//  Created by Sebastián Martinez on 20/10/26.
//

import Foundation

enum ProductosError: Error {
    case noSePudoConectar
    case servidor(Int)
    case respuestaInvalida

    /// Texto que ve el usuario. El detalle técnico no se muestra.
    var mensaje: String {
        switch self {
        case .noSePudoConectar:
            return "No hay conexión con el servidor. Revisa tu internet e intenta de nuevo."
        case .servidor, .respuestaInvalida:
            return "No pudimos cargar los productos. Intenta más tarde."
        }
    }
}

/// Pide el catálogo al backend: GET {apiBaseURL}/api/productos
///
/// Respuesta esperada (la arma el backend desde la tabla `producto`, solo activo = 1):
/// {
///   "productos": [
///     { "id": 1, "nombre": "Bolsa solidaria", "precio_mxn": 150,
///       "causa": "Apoya atención prehospitalaria", "imagen_url": null,
///       "enlace_compra": "https://..." }
///   ]
/// }
/// `precio_mxn` debe ser un número en el JSON, no un texto.
struct ProductosAPI: ProductosRepositorio {
    private struct Respuesta: Decodable {
        let productos: [Producto]
    }

    private let base: URL
    private let sesion: URLSession

    init(base: URL = Configuracion.apiBaseURL, sesion: URLSession = .shared) {
        self.base = base
        self.sesion = sesion
    }

    func productos() async throws -> [Producto] {
        var peticion = URLRequest(url: base.appendingPathComponent("api/productos"))
        peticion.httpMethod = "GET"
        peticion.timeoutInterval = 15
        peticion.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (datos, respuesta) = try await sesion.data(for: peticion)
            guard let http = respuesta as? HTTPURLResponse else {
                throw ProductosError.respuestaInvalida
            }
            guard http.statusCode == 200 else {
                throw ProductosError.servidor(http.statusCode)
            }
            let contenido = try JSONDecoder().decode(Respuesta.self, from: datos)
            // La compra ocurre fuera de la app: solo se abren enlaces https.
            return contenido.productos
                .filter { $0.enlaceCompra.scheme?.lowercased() == "https" }
                .map { producto in
                    Producto(id: producto.id, nombre: producto.nombre, precioMXN: producto.precioMXN,
                             causa: producto.causa, imagenURL: fotoDelServidor(producto.imagenURL),
                             enlaceCompra: producto.enlaceCompra)
                }
        } catch let error as URLError where error.code != .cancelled {
            throw ProductosError.noSePudoConectar
        } catch is DecodingError {
            throw ProductosError.respuestaInvalida
        }
    }

    /// En desarrollo la base guarda las fotos como http://localhost:3000/img/… En un iPhone real
    /// "localhost" es el propio teléfono, así que esas fotos (o las que vengan sin servidor,
    /// como "/img/…") se piden al mismo servidor del catálogo. Las demás se dejan igual.
    private func fotoDelServidor(_ url: URL?) -> URL? {
        guard let url, url.host == nil || ["localhost", "127.0.0.1"].contains(url.host) else { return url }
        let servidor = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var foto = URLComponents(url: url, resolvingAgainstBaseURL: false)
        foto?.scheme = servidor?.scheme
        foto?.host = servidor?.host
        foto?.port = servidor?.port
        return foto?.url ?? url
    }
}
