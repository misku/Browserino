//
//  Rule.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import Foundation

struct Rule: Hashable, Codable {
    var regex: String
    var app: URL
    var profile: String?
    /// When set, the link's port must match as well as the regex.
    var port: Int? = nil
    /// Opens the link with the browser's private argument.
    var isIncognito: Bool = false

    var target: BrowserTarget {
        BrowserTarget(app: app, profile: profile)
    }

    /// The link's port, with the scheme's default when it has none.
    static func effectivePort(of url: URL) -> Int? {
        if let port = url.port {
            return port
        }

        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    func matchesPort(of url: URL) -> Bool {
        guard let port else {
            return true
        }

        return Rule.effectivePort(of: url) == port
    }
}

extension Rule {
    // Rules saved before port and isIncognito existed lack both keys, and
    // Array+RawRepresentable turns one failed element into an empty list.
    // Declared in an extension so the memberwise init and the synthesized
    // CodingKeys and encoder stay.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regex = try container.decode(String.self, forKey: .regex)
        app = try container.decode(URL.self, forKey: .app)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
    }
}
