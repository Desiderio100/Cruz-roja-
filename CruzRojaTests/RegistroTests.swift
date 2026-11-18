//
//  RegistroTests.swift
//  Pruebas unitarias de la configuración inicial (HU01) y del teléfono del perfil.
//  Prueban las reglas que usa la pantalla "Crea tu cuenta" antes de pedir el código por SMS.
//  No usan internet ni el Llavero.
//

import Testing
@testable import CruzRoja

@Suite("HU01 · Configuración inicial")
@MainActor
struct RegistroTests {
    @Test("Acepta un nombre y un celular de 10 dígitos, con espacios, guiones o lada")
    func datosValidos() {
        #expect(ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "8112345678"))
        #expect(ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "81 1234 5678"))
        #expect(ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "(81) 1234-5678"))
        #expect(ReglasRegistro.datosValidos(nombre: "  Ana  ", telefono: "+52 81 1234 5678"))
    }

    @Test("No deja continuar con el nombre vacío o de una sola letra")
    func nombreInvalido() {
        #expect(!ReglasRegistro.datosValidos(nombre: "", telefono: "8112345678"))
        #expect(!ReglasRegistro.datosValidos(nombre: "   ", telefono: "8112345678"))
        #expect(!ReglasRegistro.datosValidos(nombre: "A", telefono: "8112345678"))
        #expect(!ReglasRegistro.datosValidos(nombre: String(repeating: "a", count: 81), telefono: "8112345678"))
    }

    @Test("No deja continuar con un teléfono corto, largo o con letras")
    func telefonoInvalido() {
        #expect(!ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "81123456"))
        #expect(!ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "8112345678901234"))
        #expect(!ReglasRegistro.datosValidos(nombre: "Ana López", telefono: "81123abc78"))
    }

    @Test("El teléfono se guarda solo con dígitos y el signo +, y así lo acepta el servidor")
    func telefonoLimpio() {
        let limpio = Perfil.limpiarTelefono("+52 (81) 1234-5678")
        #expect(limpio == "+528112345678")
        #expect(Perfil.telefonoValido(limpio))
        #expect(!Perfil.telefonoValido("81 1234 5678")) // con espacios no: primero se limpia
    }
}
