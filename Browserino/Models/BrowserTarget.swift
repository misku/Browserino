//
//  BrowserTarget.swift
//  Browserino
//

import AppKit
import Foundation

/// A browser to open links in. `profile` names a Chromium profile directory;
/// nil means the browser picks, which is what every entry meant before profiles
/// existed.
struct BrowserTarget: Codable, Hashable {
    var app: URL
    var profile: String?

    init(app: URL, profile: String? = nil) {
        self.app = app
        self.profile = profile
    }

    /// The open panel hands back "Foo.app/" where Launch Services says
    /// "Foo.app", so the same browser could count as two. The path settles it.
    private var appPath: String {
        app.standardizedFileURL.path
    }

    static func == (lhs: BrowserTarget, rhs: BrowserTarget) -> Bool {
        lhs.appPath == rhs.appPath && lhs.profile == rhs.profile
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(appPath)
        hasher.combine(profile)
    }

    /// Earlier builds stored these as bare URL strings. Both shapes have to
    /// decode, or Array+RawRepresentable skips every such entry and the user's
    /// browser order and hidden set are lost with nothing shown to explain it.
    init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let app = try? container.decode(URL.self) {
            self.init(app: app)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            app: try container.decode(URL.self, forKey: .app),
            profile: try container.decodeIfPresent(String.self, forKey: .profile)
        )
    }

    /// Shortcuts are stored per target. Profile-less targets keep using the bare
    /// bundle identifier so shortcuts recorded before this feature still resolve.
    func shortcutKey(bundleIdentifier: String) -> String {
        guard let profile else {
            return bundleIdentifier
        }

        return "\(bundleIdentifier)#\(profile)"
    }
}

extension Array where Element == BrowserTarget {
    /// The same browser twice in a rule would only show twice in the picker.
    var withoutDuplicates: [BrowserTarget] {
        var seen = Set<BrowserTarget>()
        return filter { seen.insert($0).inserted }
    }

    /// The Browsers tab order, which is also the picker's. Targets missing from
    /// that list keep their own order after the rest.
    func ordered(like browsers: [BrowserTarget]) -> [BrowserTarget] {
        let positions = Dictionary(
            browsers.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        return enumerated()
            .sorted { lhs, rhs in
                let left = positions[lhs.element] ?? Int.max
                let right = positions[rhs.element] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

@MainActor
extension BrowserTarget {
    var chromiumProfile: ChromiumProfile? {
        guard let profile else {
            return nil
        }

        return ChromiumProfileService.profiles(forAppAt: app)?
            .first { $0.directory == profile }
    }

    /// A profile the browser no longer knows about — the user switched machines,
    /// restored a backup, or deleted it in the browser. An unreadable profile list
    /// is not evidence of absence, matching how links are opened.
    var hasMissingProfile: Bool {
        guard let profile,
              let profiles = ChromiumProfileService.profiles(forAppAt: app)
        else {
            return false
        }

        return !profiles.contains { $0.directory == profile }
    }

    /// "Chrome" for a browser, "Work" for one of its profiles: the icon already
    /// says which browser a profile belongs to.
    var defaultName: String {
        let browser = Bundle(url: app)?.appDisplayName ?? app.appDisplayName

        guard let profile else {
            return browser
        }

        if hasMissingProfile {
            return "\(browser): \(profile) (missing)"
        }

        return chromiumProfile?.name ?? profile
    }

    /// The name the user typed in Preferences, or the default when they left it empty.
    var displayName: String {
        displayName(
            using: [String: String](
                rawValue: UserDefaults.standard.string(forKey: "browserNames") ?? ""
            ) ?? [:]
        )
    }

    /// For views that hold the names in @AppStorage, so a rename redraws them.
    func displayName(using names: [String: String]) -> String {
        if let bundleIdentifier = Bundle(url: app)?.bundleIdentifier,
           let name = names[shortcutKey(bundleIdentifier: bundleIdentifier)]?
            .trimmingCharacters(in: .whitespaces),
           !name.isEmpty {
            return hasMissingProfile ? "\(name) (missing)" : name
        }

        return defaultName
    }

    /// NSWorkspace builds a new image on every call, and rows ask on every
    /// redraw, which also makes SwiftUI treat the icon as changed each time.
    private static var icons: [URL: NSImage] = [:]
    private static var smallIcons: [URL: NSImage] = [:]

    var icon: NSImage {
        if let cached = Self.icons[app] {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: app.path)
        Self.icons[app] = image

        return image
    }

    /// Menus draw an image at its own size, so it has to be sized before use.
    var smallIcon: NSImage {
        if let cached = Self.smallIcons[app] {
            return cached
        }

        let image = icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        Self.smallIcons[app] = image

        return image
    }
}
