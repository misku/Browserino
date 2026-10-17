//
//  ChromiumProfile.swift
//  Browserino
//

import AppKit
import Foundation
import SwiftUI

struct ChromiumProfile: Hashable {
    /// Directory name on disk, e.g. "Default" or "Profile 2". This is what
    /// --profile-directory takes, not the display name.
    let directory: String
    let name: String
    let avatar: URL?
}

@MainActor
enum ChromiumProfileService {
    /// Chromium locates its user data directory from CrProductDirName in its own
    /// Info.plist. Stable Chrome omits the key and relies on a compiled-in default,
    /// so a fallback is still needed — but reading the key first means forks and
    /// beta channels work without being listed here, and non-Chromium browsers
    /// fall out on their own.
    private static let fallbackDirectoryNames: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "company.thebrowser.Browser": "Arc/User Data",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "org.chromium.Chromium": "Chromium",
        "net.imput.helium": "net.imput.helium",
    ]

    private static var cache: [URL: (modified: Date, profiles: [ChromiumProfile])] = [:]
    private static var avatarImages: [URL: NSImage] = [:]

    /// One redraw asks for the same browser's profiles many times (name, icon
    /// badge, missing-profile check), and every answer resolves a
    /// security-scoped bookmark and touches the disk. Answers younger than this
    /// are reused, which is still fresh enough to notice a profile added in the
    /// browser a moment ago.
    private static let memoLifetime: TimeInterval = 2
    private static var recentProfiles: [URL: (time: Date, profiles: [ChromiumProfile]?)] = [:]
    private static var recentDirectories: [URL: (time: Date, root: URL?)] = [:]

    /// macOS treats a browser's user data as private to that browser, so reading it
    /// is refused until the user points at the folder themselves. The bookmark from
    /// that choice is what carries the permission across launches.
    @StoredDefault("browserDataAccess") private static var bookmarks: [String: Data] = [:]

    @discardableResult
    static func requestAccess(forAppAt app: URL) -> Bool {
        guard let root = userDataDirectory(forAppAt: app) else {
            return false
        }

        let browser = Bundle(url: app)?.appDisplayName ?? app.appDisplayName

        guard requestAccess(toFolder: root, message: "Choose this folder so Browserino can list \(browser)'s profiles.") else {
            return false
        }

        cache[app] = nil
        recentProfiles[app] = nil

        return true
    }

    /// Asks the user to point at a browser's data folder once, and keeps the
    /// grant. Firefox containers use the same grant as Chromium profiles.
    static func requestAccess(toFolder root: URL, message: String) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.message = message
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let picked = panel.url else {
            return false
        }

        guard let data = try? picked.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return false
        }

        bookmarks[root.path] = data

        return true
    }

    static func withAccess<T>(to root: URL, _ body: () -> T?) -> T? {
        guard let data = bookmarks[root.path] else {
            // No grant yet. Still worth attempting: a browser whose data is not
            // protected, or an app already holding wider access, reads fine.
            return body()
        }

        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // The grant is no longer usable. Re-signing or moving the app
            // invalidates its bookmarks. Drop it so the UI offers the grant again
            // instead of failing silently for good.
            bookmarks[root.path] = nil
            return body()
        }

        let opened = url.startAccessingSecurityScopedResource()

        defer {
            if opened {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let result = body()

        if result == nil, isStale || !opened {
            bookmarks[root.path] = nil
        }

        return result
    }

    /// Avatars are read while laying out rows, so keep them off the disk path.
    static func avatarImage(_ url: URL) -> NSImage? {
        if let cached = avatarImages[url] {
            return cached
        }

        guard let image = NSImage(contentsOf: url) else {
            return nil
        }

        avatarImages[url] = image

        return image
    }

    private struct LocalState: Decodable {
        struct Profile: Decodable {
            struct Info: Decodable {
                let name: String?
                let isEphemeral: Bool?
                let gaiaPictureFileName: String?

                enum CodingKeys: String, CodingKey {
                    case name
                    case isEphemeral = "is_ephemeral"
                    case gaiaPictureFileName = "gaia_picture_file_name"
                }
            }

            let infoCache: [String: Info]?
            let profilesOrder: [String]?

            enum CodingKeys: String, CodingKey {
                case infoCache = "info_cache"
                case profilesOrder = "profiles_order"
            }
        }

        let profile: Profile?
    }

    /// nil when the app is not a Chromium browser.
    static func userDataDirectory(forAppAt app: URL) -> URL? {
        if let recent = recentDirectories[app], -recent.time.timeIntervalSinceNow < memoLifetime {
            return recent.root
        }

        let root = findUserDataDirectory(forAppAt: app)
        recentDirectories[app] = (Date(), root)

        return root
    }

    private static func findUserDataDirectory(forAppAt app: URL) -> URL? {
        guard let bundle = Bundle(url: app) else {
            return nil
        }

        let relativePath = bundle.infoDictionary?["CrProductDirName"] as? String
            ?? bundle.bundleIdentifier.flatMap { fallbackDirectoryNames[$0] }

        guard let relativePath,
              let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first
        else {
            return nil
        }

        let root = support.appending(path: relativePath)

        // CrProductDirName is not proof of a Chromium browser: Electron-based apps
        // ship it too (ChatGPT.app declares com.openai.codex). Only a directory
        // holding a Local State file is a profile store. fileExists answers that
        // without permission, where opening the file would be refused.
        guard FileManager.default.fileExists(
            atPath: root.appending(path: "Local State").path
        ) else {
            return nil
        }

        return root
    }

    /// nil means "could not determine" — either not a Chromium browser, or Local
    /// State was unreadable because the browser was mid-write. Callers must not
    /// collapse that into "no profiles", or a transient failure deletes rows the
    /// user has ordered, hidden and assigned shortcuts to.
    static func profiles(forAppAt app: URL) -> [ChromiumProfile]? {
        if let recent = recentProfiles[app], -recent.time.timeIntervalSinceNow < memoLifetime {
            return recent.profiles
        }

        let profiles = userDataDirectory(forAppAt: app).flatMap { root in
            withAccess(to: root) {
                readProfiles(forAppAt: app, root: root)
            }
        }
        recentProfiles[app] = (Date(), profiles)

        return profiles
    }

    private static func readProfiles(forAppAt app: URL, root: URL) -> [ChromiumProfile]? {
        let localState = root.appending(path: "Local State")

        guard let modified = try? FileManager.default.attributesOfItem(
            atPath: localState.path
        )[.modificationDate] as? Date else {
            return nil
        }

        if let cached = cache[app], cached.modified == modified {
            return cached.profiles
        }

        guard let data = try? Data(contentsOf: localState),
              let state = try? JSONDecoder().decode(LocalState.self, from: data),
              let infoCache = state.profile?.infoCache
        else {
            return nil
        }

        let ordered = order(
            directories: Array(infoCache.keys),
            preferring: state.profile?.profilesOrder
        )

        let profiles: [ChromiumProfile] = ordered.compactMap { directory in
            guard let info = infoCache[directory], info.isEphemeral != true else {
                return nil
            }

            let avatar = avatarURL(root: root, directory: directory, info: info)

            // Read now, while the security scope is still open: the picture lives
            // inside the browser's protected data directory too.
            if let avatar {
                _ = avatarImage(avatar)
            }

            return ChromiumProfile(
                directory: directory,
                name: info.name ?? directory,
                avatar: avatar
            )
        }

        cache[app] = (modified, profiles)

        return profiles
    }

    /// The picture is only cached on disk for signed-in profiles, and its filename
    /// is recorded in Local State rather than being fixed.
    private static func avatarURL(
        root: URL,
        directory: String,
        info: LocalState.Profile.Info
    ) -> URL? {
        guard let fileName = info.gaiaPictureFileName else {
            return nil
        }

        let url = root.appending(path: directory).appending(path: fileName)

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// profiles_order is Chromium's own display order. Anything missing from it is
    /// appended deterministically — JSON object order is not stable.
    private static func order(directories: [String], preferring order: [String]?) -> [String] {
        let known = order ?? []
        let remaining = Set(directories).subtracting(known)

        return known.filter(directories.contains) + remaining.sorted { lhs, rhs in
            if lhs == "Default" || rhs == "Default" {
                return lhs == "Default"
            }

            switch (profileNumber(lhs), profileNumber(rhs)) {
            case let (lhsNumber?, rhsNumber?):
                return lhsNumber < rhsNumber
            case (nil, nil):
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            }
        }
    }

    private static func profileNumber(_ directory: String) -> Int? {
        guard directory.hasPrefix("Profile ") else {
            return nil
        }

        return Int(directory.dropFirst("Profile ".count))
    }
}

/// A Firefox container (contextual identity): tabs in it keep their own
/// cookies and logins inside one profile. Not a profile.
struct FirefoxContainer: Hashable {
    let name: String
    let color: String
    let icon: String
}

/// Reads the containers of the profile Firefox opens by default. Firefox
/// can't be told from outside to open a link in a container; the free
/// extension "Open external links in a container" adds that, by handling
/// ext+container: links. Browserino sends those, so container rows need it.
@MainActor
enum FirefoxContainerService {
    /// Where each Firefox family browser keeps profiles.ini, under
    /// ~/Library/Application Support.
    private static let dataDirectoryNames: [(prefix: String, name: String)] = [
        ("org.mozilla.", "Firefox"),
        ("app.zen-browser.", "zen"),
        ("io.gitlab.librewolf", "librewolf"),
        ("net.waterfox.", "Waterfox"),
    ]

    static let extensionPage = URL(string: "https://addons.mozilla.org/firefox/addon/open-url-in-container/")!

    private static let memoLifetime: TimeInterval = 2
    private static var recentContainers: [URL: (time: Date, containers: [FirefoxContainer]?)] = [:]

    /// nil when the app is not a Firefox family browser with profiles on disk.
    static func dataDirectory(forAppAt app: URL) -> URL? {
        guard let identifier = Bundle(url: app)?.bundleIdentifier?.lowercased(),
              let entry = dataDirectoryNames.first(where: { identifier.hasPrefix($0.prefix) }),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        let root = support.appending(path: entry.name)

        // fileExists answers without permission, where reading may be refused.
        guard FileManager.default.fileExists(atPath: root.appending(path: "profiles.ini").path) else {
            return nil
        }

        return root
    }

    /// The profile a plain launch opens: the install's default when
    /// profiles.ini names one, else the profile marked Default=1, else the
    /// first. Each install of Firefox records its own default.
    private static func defaultProfile(in root: URL) -> URL? {
        guard let text = try? String(contentsOf: root.appending(path: "profiles.ini"), encoding: .utf8) else {
            return nil
        }

        var sections: [(name: String, values: [String: String])] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("[") && line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty {
                let key = String(line[..<equals])
                let value = String(line[line.index(after: equals)...])
                sections[sections.count - 1].values[key] = value
            }
        }

        func url(for values: [String: String]) -> URL? {
            guard let path = values["Path"] ?? values["Default"] else {
                return nil
            }

            return values["IsRelative"] == "0" ? URL(fileURLWithPath: path) : root.appending(path: path)
        }

        if let install = sections.first(where: { $0.name.hasPrefix("Install") }),
           let path = install.values["Default"] {
            return root.appending(path: path)
        }

        let profiles = sections.filter { $0.name.hasPrefix("Profile") }
        let chosen = profiles.first { $0.values["Default"] == "1" } ?? profiles.first

        return chosen.flatMap { url(for: $0.values) }
    }

    private struct ContainersFile: Decodable {
        struct Identity: Decodable {
            let `public`: Bool?
            let icon: String?
            let color: String?
            let name: String?
            let l10nID: String?
            let l10nId: String?
        }

        let identities: [Identity]
    }

    /// The four containers Firefox ships carry a translation key instead of a
    /// name. These are their English names, which is what the extension
    /// matches against in an English Firefox.
    private static func builtInName(_ key: String) -> String? {
        let key = key.lowercased()

        if key.contains("personal") { return "Personal" }
        if key.contains("work") { return "Work" }
        if key.contains("banking") { return "Banking" }
        if key.contains("shopping") { return "Shopping" }

        return nil
    }

    /// nil means "could not read", not "no containers": a read the system
    /// refused must not delete rows the user has ordered and named.
    static func containers(forAppAt app: URL) -> [FirefoxContainer]? {
        if let recent = recentContainers[app], -recent.time.timeIntervalSinceNow < memoLifetime {
            return recent.containers
        }

        let containers = dataDirectory(forAppAt: app).flatMap { root in
            ChromiumProfileService.withAccess(to: root) { () -> [FirefoxContainer]? in
                guard let profile = defaultProfile(in: root) else {
                    return nil
                }

                let file = profile.appending(path: "containers.json")

                // A profile that never used containers has no file yet.
                guard FileManager.default.fileExists(atPath: file.path) else {
                    return []
                }

                guard let data = try? Data(contentsOf: file),
                      let decoded = try? JSONDecoder().decode(ContainersFile.self, from: data)
                else {
                    return nil
                }

                return decoded.identities.compactMap { identity -> FirefoxContainer? in
                    // Firefox keeps a few hidden identities for itself.
                    guard identity.`public` != false,
                          let name = identity.name
                            ?? (identity.l10nID ?? identity.l10nId).flatMap(builtInName)
                    else {
                        return nil
                    }

                    return FirefoxContainer(
                        name: name,
                        color: identity.color ?? "toolbar",
                        icon: identity.icon ?? "circle"
                    )
                }
            }
        }
        recentContainers[app] = (Date(), containers)

        return containers
    }

    /// Whether the default profile has an extension that opens ext+container:
    /// links. nil when that can't be read.
    static func hasContainerExtension(forAppAt app: URL) -> Bool? {
        guard let root = dataDirectory(forAppAt: app) else {
            return nil
        }

        return ChromiumProfileService.withAccess(to: root) { () -> Bool? in
            guard let profile = defaultProfile(in: root),
                  let text = try? String(contentsOf: profile.appending(path: "extensions.json"), encoding: .utf8)
            else {
                return nil
            }

            return text.contains("Open external links in a container")
                || text.contains("Default Container Handler")
        }
    }

    @discardableResult
    static func requestAccess(forAppAt app: URL) -> Bool {
        guard let root = dataDirectory(forAppAt: app) else {
            return false
        }

        let browser = Bundle(url: app)?.appDisplayName ?? app.appDisplayName

        guard ChromiumProfileService.requestAccess(
            toFolder: root,
            message: "Choose this folder so Browserino can list \(browser)'s containers."
        ) else {
            return false
        }

        recentContainers[app] = nil

        return true
    }

    /// An ext+container: link the extension opens in the named container.
    /// Both parts are fully escaped, so a link's own & and = stay inside it.
    nonisolated static func containerLink(for url: URL, container: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        guard let name = container.addingPercentEncoding(withAllowedCharacters: allowed),
              let link = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
            return nil
        }

        return URL(string: "ext+container:name=\(name)&url=\(link)")
    }
}
