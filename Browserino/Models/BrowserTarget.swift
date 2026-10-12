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

    /// Earlier builds stored these as bare URL strings. Both shapes have to decode,
    /// because Array+RawRepresentable turns any decode failure into nil and
    /// @AppStorage then silently substitutes an empty array — losing the user's
    /// browser order and hidden set with nothing shown to explain it.
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
        let names = [String: String](
            rawValue: UserDefaults.standard.string(forKey: "browserNames") ?? ""
        ) ?? [:]

        if let bundleIdentifier = Bundle(url: app)?.bundleIdentifier,
           let name = names[shortcutKey(bundleIdentifier: bundleIdentifier)]?
            .trimmingCharacters(in: .whitespaces),
           !name.isEmpty {
            return hasMissingProfile ? "\(name) (missing)" : name
        }

        return defaultName
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: app.path)
    }

    /// Menus draw an image at its own size, so it has to be sized before use.
    var smallIcon: NSImage {
        let image = icon
        image.size = NSSize(width: 16, height: 16)

        return image
    }
}
