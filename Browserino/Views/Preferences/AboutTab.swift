//
//  AboutTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 96, height: 96)

            Text("Browserino")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .foregroundStyle(.secondary)

            Link("Browserino on GitHub", destination: URL(string: "https://github.com/AlexStrNik/Browserino/")!)
                .help("Open the original project page in your browser")

            Link("Fork created by @misku", destination: URL(string: "https://github.com/misku/Browserino")!)
                .help("Open this fork's project page in your browser")

            Text("Thanks to @AlexStrNik, who created Browserino, and to @matijazezelj, @xplorick, @byt3m4st3r, @mihado, @ventz, @sayre4ux, @mihai97ionita, @webcoyote, @simonswine and others for contributions!")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

#Preview {
    AboutTab()
}
