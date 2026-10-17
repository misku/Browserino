//
//  Rule.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import Foundation

struct Rule: Hashable, Codable, Identifiable {
    /// Rows follow their rule through a drag, so an open browser list stays
    /// with its rule instead of with its position.
    var id = UUID()
    var regex: String
    /// One installed browser opens the link directly; several show the picker
    /// with only these. Empty shows the full picker, as if no rule matched,
    /// but still stops All Other Links from taking the link.
    var targets: [BrowserTarget]
    /// When set, the link's port must match as well as the regex.
    var port: Int? = nil
    /// Opens the link with the browser's private argument.
    var isIncognito: Bool = false

    var showsPicker: Bool {
        targets.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case regex
        case targets
        case port
        case isIncognito
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

    /// Compiling a pattern costs far more than matching it, and the Rules tab
    /// asks for every rule on each redraw.
    @MainActor private static var compiled: [String: Regex<AnyRegexOutput>] = [:]
    @MainActor private static var invalid: Set<String> = []

    /// Compiled the way links are matched, so the Rules tab and the router agree.
    @MainActor static func compile(_ pattern: String) -> Regex<AnyRegexOutput>? {
        if let cached = compiled[pattern] {
            return cached
        }

        if invalid.contains(pattern) {
            return nil
        }

        // The rule sheet compiles every pattern typed on the way to the real
        // one; a bound keeps those from piling up.
        if compiled.count + invalid.count > 256 {
            compiled.removeAll()
            invalid.removeAll()
        }

        guard let regex = try? Regex(pattern).ignoresCase() else {
            invalid.insert(pattern)
            return nil
        }

        compiled[pattern] = regex

        return regex
    }

    @MainActor var compiledRegex: Regex<AnyRegexOutput>? {
        Rule.compile(regex)
    }

    @MainActor func matches(_ url: URL) -> Bool {
        guard let compiledRegex else {
            return false
        }

        return url.absoluteString.firstMatch(of: compiledRegex) != nil && matchesPort(of: url)
    }

    /// Unrelated links: different schemes, hosts, ports, paths and queries. A
    /// pattern for any port that takes all of them, such as ".*", catches every
    /// web link, so nothing below it is ever reached.
    private static let unrelatedLinks = [
        "https://browserino.invalid/",
        "http://example.org/x?y=1",
        "https://203.0.113.7:8443/a/b#c",
        "http://localhost/",
    ]

    @MainActor var matchesEveryLink: Bool {
        guard port == nil, let compiledRegex else {
            return false
        }

        return Rule.unrelatedLinks.allSatisfy {
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

    // Rules saved before port and isIncognito existed lack both keys, and
    // rules saved before targets existed hold a single app and profile instead.
    // A rule that fails here is dropped by Array+RawRepresentable.
    // Declared in an extension so the memberwise init stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
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

    /// Also writes the single app and profile older builds require. Without
    /// them, one launch of an older Browserino fails to read any rule, starts
    /// with none, and saves that over the user's list.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(regex, forKey: .regex)
        try container.encode(targets, forKey: .targets)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(isIncognito, forKey: .isIncognito)

        // Safari as the last resort, because a rule without an app is one an
        // older build can't read at all.
        let legacyTarget = targets.first
            ?? Rule.firstVisibleBrowser()
            ?? BrowserTarget(app: URL(fileURLWithPath: "/Applications/Safari.app"))
        var legacy = encoder.container(keyedBy: LegacyCodingKeys.self)
        try legacy.encode(legacyTarget.app, forKey: .app)
        try legacy.encodeIfPresent(legacyTarget.profile, forKey: .profile)
    }

    /// An older build has no picker state; the closest it can do is the first
    /// browser the picker would list.
    private static func firstVisibleBrowser() -> BrowserTarget? {
        let defaults = UserDefaults.standard
        let browsers = [BrowserTarget](rawValue: defaults.string(forKey: "browsers") ?? "") ?? []
        let hidden = [BrowserTarget](rawValue: defaults.string(forKey: "hiddenBrowsers") ?? "") ?? []

        return browsers.first { !hidden.contains($0) }
    }
}
