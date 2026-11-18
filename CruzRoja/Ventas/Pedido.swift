//
//  Pedido.swift
//  Ventas
//
//  Modelos de la compra con pago dentro de la app (Stripe + envío a domicilio).
//  Lo que mandan y devuelven estas rutas está en backend/src/rutas/pedidos.js.
//

import Foundation

// MARK: - Dinero

/// El dinero se calcula en CENTAVOS ENTEROS para no arrastrar errores de decimales
/// (el servidor hace lo mismo). El total que cobra Stripe lo calcula SIEMPRE el servidor;
/// los números de la app son solo para mostrarlos antes de pagar.
enum Dinero {
    static func centavos(_ pesos: Decimal) -> Int {
        let centavos = NSDecimalNumber(decimal: pesos * 100).doubleValue
        return Int(centavos.rounded())
    }

    static func centavos(_ pesos: Double) -> Int {
        Int((pesos * 100).rounded())
    }

    /// "$399 MXN", o "$399.50 MXN" si trae centavos (mismo formato que `Producto.precioTexto`).
    static func texto(centavos: Int) -> String {
        let conCentavos = centavos % 100 != 0
        let formato = NumberFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.numberStyle = .decimal
        formato.minimumFractionDigits = conCentavos ? 2 : 0
        formato.maximumFractionDigits = 2
        let pesos = NSDecimalNumber(decimal: Decimal(centavos) / 100)
        return "$\(formato.string(from: pesos) ?? pesos.stringValue) MXN"
    }
}

// MARK: - Datos de envío

/// Lo que la persona escribe para recibir su pedido en casa.
/// Las reglas son las MISMAS del servidor (esquemaPedido en pedidos.js); el servidor las vuelve
/// a revisar, así que aquí sirven para avisar rápido y no mandar datos que van a rebotar.
struct DatosEnvio: Equatable {
    var nombre = ""
    var telefono = ""
    var calleNumero = ""
    var colonia = ""
    var ciudad = ""
    var entidad = ""
    var codigoPostal = ""
    var referencias = ""

    /// Los datos ya limpios: sin espacios de más, sin saltos de línea y con el teléfono y el
    /// código postal solo con dígitos. Esto es lo que se manda al servidor.
    var normalizado: DatosEnvio {
        DatosEnvio(
            nombre: Self.limpio(nombre),
            telefono: telefono.filter { $0.isASCII && ($0.isNumber || $0 == "+") },
            calleNumero: Self.limpio(calleNumero),
            colonia: Self.limpio(colonia),
            ciudad: Self.limpio(ciudad),
            entidad: Self.limpio(entidad),
            codigoPostal: codigoPostal.filter { $0.isASCII && $0.isNumber },
            referencias: Self.limpio(referencias)
        )
    }

    /// El primer problema que ve el usuario, o nil si todo está bien.
    var problema: String? {
        let d = normalizado
        if let falla = Self.revisar(d.nombre, "el nombre", minimo: 3, maximo: 120) { return falla }
        if d.telefono.isEmpty { return "Falta el teléfono." }
        if !Self.telefonoValido(d.telefono) { return "El teléfono debe tener entre 10 y 15 dígitos." }
        if let falla = Self.revisar(d.calleNumero, "la calle y el número", minimo: 3, maximo: 150) { return falla }
        if let falla = Self.revisar(d.colonia, "la colonia", minimo: 2, maximo: 100) { return falla }
        if let falla = Self.revisar(d.ciudad, "la ciudad", minimo: 2, maximo: 100) { return falla }
        if let falla = Self.revisar(d.entidad, "el estado", minimo: 2, maximo: 60) { return falla }
        if d.codigoPostal.isEmpty { return "Falta el código postal." }
        if d.codigoPostal.range(of: "^[0-9]{5}$", options: .regularExpression) == nil {
            return "El código postal debe tener 5 dígitos."
        }
        if d.referencias.count > 200 { return "Las referencias son muy largas (máximo 200 letras)." }
        return nil
    }

    var esValido: Bool { problema == nil }

    // MARK: Ayudas

    // Se reescribe aquí (y no se usa Perfil.telefonoValido) porque Perfil vive en el hilo principal.
    private static func telefonoValido(_ texto: String) -> Bool {
        texto.range(of: "^[+]?[0-9]{10,15}$", options: .regularExpression) != nil
    }

    private static func limpio(_ texto: String) -> String {
        texto.components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func revisar(_ valor: String, _ etiqueta: String, minimo: Int, maximo: Int) -> String? {
        if valor.isEmpty { return "Falta \(etiqueta)." }
        if valor.count < minimo { return "Revisa \(etiqueta): es muy corto." }
        if valor.count > maximo { return "Revisa \(etiqueta): es muy largo." }
        return nil
    }
}

// MARK: - Respuestas del servidor

/// GET /api/pedidos/condiciones: lo que la app necesita saber ANTES de pagar.
/// (ClienteAPI convierte envio_mxn → envioMxn, etc.)
struct CondicionesDeCompra: Decodable, Equatable {
    /// false si el servidor no tiene Stripe configurado: la app avisa que la compra no está disponible.
    let disponible: Bool
    let envioMxn: Double
    let cantidadMaxima: Int
    let totalMinimoMxn: Double
}

/// POST /api/pedidos: el pedido recién creado y lo necesario para abrir la hoja de pago.
struct Pedido: Identifiable, Decodable, Equatable {
    let id: String
    /// Número que se le da a la persona para dar seguimiento, por ejemplo "PC-000012".
    let folio: String
    let productoNombre: String
    let cantidad: Int
    let envioMxn: Double
    let totalMxn: Double
    /// Con esto (y la llave publicable) la hoja de Stripe cobra ESTE pedido. No es la llave secreta.
    let clientSecret: String
    let publishableKey: String

    var totalCentavos: Int { Dinero.centavos(totalMxn) }
    var totalTexto: String { Dinero.texto(centavos: totalCentavos) }
}

enum EstadoPedido: String, Decodable, Equatable {
    case pendiente
    case pagado
    case cancelado
}

/// GET /api/pedidos/:id (el servidor también manda fechas y totales; aquí solo se usa el estado).
struct EstadoDelPedido: Decodable, Equatable {
    let id: String
    let folio: String
    let estado: EstadoPedido
}
