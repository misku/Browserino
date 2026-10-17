//
//  PreferencesView.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI

/// The panes of the Settings window, in toolbar order. AppDelegate builds the
/// toolbar from this list; the preview below shows the same panes as tabs.
enum SettingsPane: Int, CaseIterable {
    case general
    case browsers
    case apps
    case rules
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .apps: "Apps"
        case .rules: "Rules"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .browsers: "globe"
        case .apps: "square.grid.2x2"
        case .rules: "arrow.triangle.branch"
        case .about: "info.circle"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralTab()
        case .browsers: BrowsersTab()
        case .apps: AppsTab()
        case .rules: RulesTab()
        case .about: AboutTab()
        }
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                pane.content
                    .tabItem {
                        Label(pane.title, systemImage: pane.symbol)
                    }
                    .tag(pane.rawValue)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    PreferencesView()
}
