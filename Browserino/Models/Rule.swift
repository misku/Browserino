//
//  Rule.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import Foundation

struct Rule: Hashable, Codable {
    var regex: String
    /// One browser opens the link directly; several show the picker with only
    /// these, in this order.
    var targets: [BrowserTarget]
    /// When set, the link's port must match as well as the regex.
    var port: Int? = nil
    /// Opens the link with the browser's private argument.
    var isIncognito: Bool = false

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

    /// Compiled the way links are matched, so the Rules tab and the router agree.
    var compiledRegex: Regex<AnyRegexOutput>? {
        try? Regex(regex).ignoresCase()
    }

    func matches(_ url: URL) -> Bool {
        guard let compiledRegex else {
            return false
        }

        return url.absoluteString.firstMatch(of: compiledRegex) != nil && matchesPort(of: url)
    }

    /// A rule for any port whose regex takes both of these unrelated links,
    /// such as ".*", catches every link, so no rule below it is ever reached.
    var matchesEveryLink: Bool {
        guard port == nil, let compiledRegex else {
            return false
        }

        return ["https://browserino.invalid/", "http://browserino.invalid/x"].allSatisfy {
            $0.firstMatch(of: compiledRegex) != nil
        }
    }
}

extension Rule {
    /// The keys rules were stored under before they held several browsers.
    private enum LegacyCodingKeys: String, CodingKey {
        case app
        case profile
    }

    // Rules saved before port and isIncognito existed lack both keys, rules
    // saved before targets existed hold a single app and profile instead, and
    // Array+RawRepresentable turns one failed element into an empty list.
    // Declared in an extension so the memberwise init and the synthesized
    // CodingKeys and encoder stay, and the encoder writes targets only.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regex = try container.decode(String.self, forKey: .regex)

        if let targets = try container.decodeIfPresent([BrowserTarget].self, forKey: .targets) {
            self.targets = targets
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            targets = [
                BrowserTarget(
                    app: try legacy.decode(URL.self, forKey: .app),
                    profile: try legacy.decodeIfPresent(String.self, forKey: .profile)
                )
            ]
        }

        port = try container.decodeIfPresent(Int.self, forKey: .port)
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
    }
}
