// Cada integrante agrega UNA entrada a la lista y aparece sola en la pantalla
// principal. Tu código va en tu propia carpeta: CruzRoja/<TuFuncion>/

import SwiftUI

enum Secciones {
    static let todas: [Seccion] = [
        Seccion("Centro más cercano",
                detalle: "Mapa y lista de centros de Cruz Roja, del más cercano al más lejano",
                icono: "mappin.and.ellipse",
                responsable: "Desiderio") {
            CentroCercanoView()
        },

        Seccion("Capacitación",
                detalle: "Cursos, videos y lo básico de primeros auxilios",
                icono: "cross.case.fill",
                responsable: "Desiderio") {
            CapacitacionView()
        },

        Seccion("Agenda de citas",
                detalle: "Nutrición y psicología: agenda, mis citas y cancelar",
                icono: "calendar",
                responsable: "Luis") {
            AgendaView()
        },

        Seccion("Productos con causa",
                detalle: "Compra productos y apoya a Cruz Roja",
                icono: "bag.fill",
                responsable: "Sebastián") {
            ProductosCausaView()
        },

        // ⬇︎ Copia este bloque, quita las // y cambia los datos:
        //
        // Seccion("Mi función",
        //         detalle: "Qué hace, en una línea",
        //         icono: "star.fill",          // nombre de SF Symbols
        //         responsable: "Tu nombre") {
        //     MiFuncionView()
        // },
    ]
}

struct Seccion: Identifiable {
    let titulo: String
    let detalle: String
    let icono: String
    let responsable: String
    let pantalla: @MainActor () -> AnyView

    var id: String { titulo }

    init<Pantalla: View>(_ titulo: String, detalle: String, icono: String, responsable: String,
                         @ViewBuilder pantalla: @escaping @MainActor () -> Pantalla) {
        self.titulo = titulo
        self.detalle = detalle
        self.icono = icono
        self.responsable = responsable
        self.pantalla = { AnyView(pantalla()) }
    }
}
