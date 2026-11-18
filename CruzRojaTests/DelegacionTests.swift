//
//  DelegacionTests.swift
//  Pruebas unitarias de HU11 · Delegación según mi ubicación (directorio de delegaciones).
//
//  Cada prueba guarda el directorio en un archivo temporal propio y usa un servidor
//  falso en memoria, así no necesita el backend ni toca la copia del simulador.
//

import CoreLocation
import Foundation
import Testing
@testable import CruzRoja

/// Servidor falso del directorio: responde como GET /api/delegaciones.
@MainActor
final class ServidorDeDelegacionesFalso: FuenteDirectorio {
    var version: Int
    var lista: [Delegacion]
    var sinConexion = false
    private(set) var versionesPedidas: [Int?] = []

    init(version: Int, lista: [Delegacion]) {
        self.version = version
        self.lista = lista
    }

    func descargar(version pedida: Int?) async throws -> RespuestaDirectorio {
        versionesPedidas.append(pedida)
        if sinConexion { throw ErrorAPI(mensaje: "No hay conexión con el servidor") }
        if pedida == version { return RespuestaDirectorio(version: version, sinCambios: true, delegaciones: nil) }
        return RespuestaDirectorio(version: version, sinCambios: nil, delegaciones: lista)
    }
}

@MainActor
@Suite("HU11 · Delegación según mi ubicación")
struct DelegacionTests {
    static let monterrey = Delegacion(id: 2, nombre: "Monterrey", telefono: "+528100000002",
                                      latitud: 25.6866, longitud: -100.3161, estado: "Nuevo León")
    static let guadalajara = Delegacion(id: 3, nombre: "Guadalajara", telefono: "+523300000003",
                                        latitud: 20.6597, longitud: -103.3496, estado: "Jalisco")
    static let saltillo = Delegacion(id: 7, nombre: "Saltillo", telefono: "+528440000007",
                                     latitud: 25.4232, longitud: -101.0053, estado: "Coahuila")

    let enMonterrey = CLLocationCoordinate2D(latitude: 25.6500, longitude: -100.2900)
    let enGuadalajara = CLLocationCoordinate2D(latitude: 20.6700, longitude: -103.3600)

    /// Directorio con un archivo y un almacén propios, ya descargado del servidor falso.
    static func directorioNuevo(_ servidor: ServidorDeDelegacionesFalso) async
        -> (directorio: DirectorioDelegaciones, archivo: URL, almacen: UserDefaults) {
        let archivo = FileManager.default.temporaryDirectory.appending(path: "directorio-\(UUID().uuidString).json")
        let suite = "pruebas.delegacion.\(UUID().uuidString)"
        let almacen = UserDefaults(suiteName: suite)!
        almacen.removePersistentDomain(forName: suite)
        let directorio = DirectorioDelegaciones(archivo: archivo, almacen: almacen, fuente: servidor)
        await directorio.actualizar()
        return (directorio, archivo, almacen)
    }

    static func servidor() -> ServidorDeDelegacionesFalso {
        ServidorDeDelegacionesFalso(version: 7, lista: [monterrey, guadalajara])
    }

    // MARK: - CA11.1 · Al moverme a otra zona, la app actualiza la delegación que me corresponde

    @Test("Con mi ubicación, me toca la delegación más cercana")
    func delegacionPorUbicacion() async {
        let directorio = await Self.directorioNuevo(Self.servidor()).directorio
        directorio.ubicar(enMonterrey)
        #expect(directorio.actual?.id == Self.monterrey.id)
        #expect(directorio.anterior == nil)
    }

    @Test("Al moverme a otra zona cambia mi delegación y se avisa cuál tenía antes")
    func cambiaAlMoverme() async {
        let directorio = await Self.directorioNuevo(Self.servidor()).directorio
        directorio.ubicar(enMonterrey)
        directorio.ubicar(enGuadalajara)
        #expect(directorio.actual?.id == Self.guadalajara.id)
        #expect(directorio.anterior?.id == Self.monterrey.id)
    }

    @Test("En la frontera entre dos zonas no brinca de una delegación a otra")
    func noBrincaEnLaFrontera() async {
        let servidor = ServidorDeDelegacionesFalso(version: 1, lista: [Self.monterrey, Self.saltillo])
        let directorio = await Self.directorioNuevo(servidor).directorio
        directorio.ubicar(enMonterrey)

        // Punto a medio camino, apenas más cerca de Saltillo: menos que el margen de cambio.
        let mitad = CLLocationCoordinate2D(latitude: (Self.monterrey.latitud + Self.saltillo.latitud) / 2,
                                           longitude: (Self.monterrey.longitud + Self.saltillo.longitud) / 2 - 0.005)
        directorio.ubicar(mitad)
        #expect(directorio.actual?.id == Self.monterrey.id)
    }

    @Test("Sin ubicación se queda la última delegación conocida, aun al reabrir la app")
    func ultimaConocida() async {
        let servidor = Self.servidor()
        let (directorio, archivo, almacen) = await Self.directorioNuevo(servidor)
        directorio.ubicar(enGuadalajara)
        directorio.ubicar(nil)
        #expect(directorio.actual?.id == Self.guadalajara.id)

        let reabierto = DirectorioDelegaciones(archivo: archivo, almacen: almacen, fuente: servidor)
        #expect(reabierto.actual?.id == Self.guadalajara.id)
    }

    // MARK: - CA11.2 · Sin internet, la app usa el directorio guardado en el teléfono

    @Test("Sin internet usa el directorio guardado en el teléfono")
    func sinInternetUsaElGuardado() async {
        let servidor = Self.servidor()
        let (_, archivo, almacen) = await Self.directorioNuevo(servidor)
        servidor.sinConexion = true

        let reabierto = DirectorioDelegaciones(archivo: archivo, almacen: almacen, fuente: servidor)
        await reabierto.actualizar()

        #expect(reabierto.delegaciones.map(\.id).sorted() == [2, 3])
        #expect(reabierto.confirmadoEn != nil)
        reabierto.ubicar(enGuadalajara)
        #expect(reabierto.actual?.telefono == Self.guadalajara.telefono)
    }

    @Test("Si nunca hubo internet usa el directorio que trae la app")
    func directorioIncluido() {
        let archivo = FileManager.default.temporaryDirectory.appending(path: "no-existe-\(UUID().uuidString).json")
        let servidor = Self.servidor()
        servidor.sinConexion = true
        let directorio = DirectorioDelegaciones(archivo: archivo, almacen: UserDefaults(suiteName: UUID().uuidString)!,
                                                fuente: servidor)
        #expect(!directorio.delegaciones.isEmpty)
        #expect(directorio.confirmadoEn == nil)
        #expect(directorio.delegaciones.allSatisfy { $0.telefonoLocal.count == 10 })
    }

    @Test("Solo baja el directorio completo cuando cambia la versión")
    func soloBajaSiCambiaLaVersion() async {
        let servidor = Self.servidor()
        let directorio = await Self.directorioNuevo(servidor).directorio

        await directorio.actualizar()                 // misma versión: sin cambios
        servidor.version = 8
        servidor.lista = [Self.monterrey, Self.guadalajara, Self.saltillo]
        await directorio.actualizar()                 // versión nueva: baja la lista

        #expect(servidor.versionesPedidas == [nil, 7, 7])
        #expect(directorio.version == 8)
        #expect(directorio.delegaciones.count == 3)
    }

    @Test("Si mi delegación se da de baja, me toca la siguiente más cercana")
    func delegacionDadaDeBaja() async {
        let servidor = ServidorDeDelegacionesFalso(version: 1, lista: [Self.monterrey, Self.saltillo])
        let directorio = await Self.directorioNuevo(servidor).directorio
        directorio.ubicar(enMonterrey)

        servidor.version = 2
        servidor.lista = [Self.saltillo]
        await directorio.actualizar()

        #expect(directorio.actual?.id == Self.saltillo.id)
    }

    // MARK: - Número para llamar

    @Test("El número se marca con 10 dígitos y se muestra con espacios")
    func telefono() {
        #expect(Self.monterrey.telefonoLocal == "8100000002")
        #expect(Self.monterrey.telefonoParaMostrar == "81 0000 0002")
        #expect(Self.monterrey.comoCentro.telefono == "8100000002")
    }
}
