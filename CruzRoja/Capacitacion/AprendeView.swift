// Los pasos salen siempre abiertos: en una emergencia, un toque menos.

import SwiftUI

struct AprendeView: View {
    @Environment(Internet.self) private var internet
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Esto no sustituye un curso. En una emergencia, llama al 911.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !internet.hayConexion {
                    AvisoSinInternet("los pasos se ven igual; los videos no")
                }

                ForEach(Tema.basicos) { tema in
                    TarjetaTema(tema: tema)
                }

                Button {
                    abrirURL(URL(string: "https://www.youtube.com/results?search_query=primeros+auxilios+Cruz+Roja")!)
                } label: {
                    Label("Ver más videos en YouTube", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(BotonRojo())
                .disabled(!internet.hayConexion)
            }
            .padding(.horizontal, Medida.margen)
            .padding(.bottom, 24)
        }
    }
}

private struct TarjetaTema: View {
    let tema: Tema

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tema.titulo, systemImage: tema.icono)
                .font(.headline)

            ForEach(Array(tema.pasos.enumerated()), id: \.offset) { i, paso in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.rojoCruzRoja, in: Circle())
                    Text(paso)
                }
            }

            BotonVideo(tema: tema)
        }
        .tarjeta()
    }
}

private struct BotonVideo: View {
    let tema: Tema
    @Environment(Internet.self) private var internet
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        if !internet.hayConexion {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Necesitas internet para ver el video")
                    .foregroundStyle(.secondary)
                BotonReintentar()
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                abrirURL(tema.urlVideo)
            } label: {
                if let miniatura = tema.urlMiniatura {
                    ZStack {
                        AsyncImage(url: miniatura) { imagen in
                            imagen.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.rojoCruzRoja)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Ver videos en YouTube", systemImage: "play.rectangle")
                        .font(.subheadline.bold())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rojoCruzRoja)
            .accessibilityLabel("Video sobre \(tema.titulo). Se abre en YouTube.")
        }
    }
}

#Preview {
    AprendeView()
        .environment(Internet())
}
