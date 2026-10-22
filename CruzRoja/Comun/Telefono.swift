// Para marcar a un número desde cualquier pantalla:
//
//     Link("Llamar", destination: Telefono.url("8112345600"))

import Foundation

enum Telefono {
    static let emergencias = "911"

    static func url(_ numero: String) -> URL {
        let digitos = numero.filter { $0.isASCII && $0.isNumber }
        return URL(string: "tel://\(digitos.isEmpty ? emergencias : digitos)")!
    }
}
