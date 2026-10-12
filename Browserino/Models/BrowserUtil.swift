//  BrowserUtil.swift
//  Browserino
//
//  Created by byt3m4st3r.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
class BrowserUtil {
    @AppStorage("directories") private static var directories: [Directory] = []
    @AppStorage("privateArgs") private static var privateArgs: [String: String] = [:]
    @AppStorage("shortcuts") private static var shortcuts: [String: String] = [:]
    @AppStorage("browserNames") private static var names: [String: String] = [:]
    @AppStorage("hiddenBrowsers") private static var hiddenBrowsers: [BrowserTarget] = []

    static func loadBrowsers(
        oldBrowsers: [BrowserTarget]
    ) -> [BrowserTarget] {
        if directories.isEmpty {
            let defaultDirectory = Directory(directoryPath: "/Applications")
            directories.append(defaultDirectory)
        }
        
        let validDirectories = directories.map { $0.directoryPath }

        guard let url = URL(string: "https:") else {
            return []
        }

        let urlsForApplications = NSWorkspace.shared.urlsForApplications(toOpen: url)

        var filteredUrlsForApplications = urlsForApplications.filter { urlsForApplication in
            validDirectories.contains { urlsForApplication.path.hasPrefix($0) }
        }
        
        if let browserino = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "xyz.alexstrnik.Browserino") {
            filteredUrlsForApplications.removeAll { $0 == browserino }
        }

        if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            if !filteredUrlsForApplications.contains(safari) {
                filteredUrlsForApplications.append(safari)
            }
        }
        
        let discovered = filteredUrlsForApplications.flatMap { app in
            targets(forAppAt: app, oldBrowsers: oldBrowsers)
        }

        let merged = merge(discovered: discovered, into: oldBrowsers)

        carryOverSettings(from: oldBrowsers, to: merged)

        return merged
    }

    /// When a browser's plain row is replaced by its profile rows, the plain row's
    /// shortcut moves to the first profile and a hidden browser stays hidden.
    /// Otherwise the upgrade silently drops the user's keys and unhides browsers.
    private static func carryOverSettings(
        from oldBrowsers: [BrowserTarget],
        to merged: [BrowserTarget]
    ) {
        for old in oldBrowsers where old.profile == nil && !merged.contains(old) {
            let replacements = merged.filter { $0.app == old.app && $0.profile != nil }

            guard let first = replacements.first,
                  let bundleIdentifier = Bundle(url: old.app)?.bundleIdentifier
            else {
                continue
            }

            let profileKey = first.shortcutKey(bundleIdentifier: bundleIdentifier)

            if let key = shortcuts[bundleIdentifier], shortcuts[profileKey] == nil {
                shortcuts[profileKey] = key
                shortcuts[bundleIdentifier] = nil
            }

            if let name = names[bundleIdentifier], names[profileKey] == nil {
                names[profileKey] = name
                names[bundleIdentifier] = nil
            }

            if let index = hiddenBrowsers.firstIndex(of: old) {
                hiddenBrowsers.remove(at: index)
                hiddenBrowsers.append(
                    contentsOf: replacements.filter { !hiddenBrowsers.contains($0) }
                )
            }
        }
    }

    /// A browser with several profiles is represented by its profiles rather than
    /// by itself — opening "Chrome" when every link could go to a specific profile
    /// is just an extra row that does nothing distinct.
    private static func targets(
        forAppAt app: URL,
        oldBrowsers: [BrowserTarget]
    ) -> [BrowserTarget] {
        guard let profiles = ChromiumProfileService.profiles(forAppAt: app) else {
            // Local State unreadable. If this is a Chromium browser we already knew
            // profiles for, keep them: dropping to a bare entry here would discard
            // the user's ordering, hidden flags and shortcuts on one bad rescan.
            guard ChromiumProfileService.userDataDirectory(forAppAt: app) != nil else {
                return [BrowserTarget(app: app)]
            }

            let known = oldBrowsers.filter { $0.app == app }

            return known.isEmpty ? [BrowserTarget(app: app)] : known
        }

        guard profiles.count > 1 else {
            return [BrowserTarget(app: app)]
        }

        return profiles.map { BrowserTarget(app: app, profile: $0.directory) }
    }

    /// Keeps the order the user arranged, and drops anything newly discovered next
    /// to its own browser rather than at the end.
    private static func merge(
        discovered: [BrowserTarget],
        into oldBrowsers: [BrowserTarget]
    ) -> [BrowserTarget] {
        let discoveredTargets = Set(discovered)

        var merged: [BrowserTarget] = []
        var placed: Set<BrowserTarget> = []

        for old in oldBrowsers {
            if discoveredTargets.contains(old) {
                if placed.insert(old).inserted {
                    merged.append(old)
                }
            } else {
                // This exact entry is gone, but the same browser may now be
                // represented differently — profiles replacing the plain row on
                // first run. Those belong where the user had put the browser, not
                // at the bottom of the list.
                for target in discovered
                where target.app == old.app && placed.insert(target).inserted {
                    merged.append(target)
                }
            }
        }

        for target in discovered where !placed.contains(target) {
            if let last = merged.lastIndex(where: { $0.app == target.app }) {
                merged.insert(target, at: last + 1)
            } else {
                merged.append(target)
            }

            placed.insert(target)
        }

        return merged
    }
    
    static func openURL(_ urls: [URL], target: BrowserTarget, isIncognito: Bool) {
        guard let bundle = Bundle(url: target.app) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        var arguments: [String] = []

        if let profile = target.profile, isKnownProfile(profile, forAppAt: target.app) {
            arguments.append("--profile-directory=\(profile)")
        }

        if isIncognito, let bundleIdentifier = bundle.bundleIdentifier,
           let privateArg = privateArgs[bundleIdentifier], !privateArg.isEmpty {
            arguments.append(privateArg)
        }

        // Arguments only reach an already-running browser as a forwarded command
        // line, which needs a second instance. Without any, the plain Apple Event
        // open is both faster and the long-standing behaviour.
        guard !arguments.isEmpty else {
            NSWorkspace.shared.open(
                urls,
                withApplicationAt: target.app,
                configuration: configuration
            )
            return
        }

        configuration.createsNewApplicationInstance = true
        // Only absolute URLs reach the command line. One with a scheme starts with a
        // letter, so a crafted link can never be read as a browser switch.
        configuration.arguments = arguments + urls.filter { $0.scheme != nil }.map(\.absoluteString)

        NSWorkspace.shared.open(
            [],
            withApplicationAt: target.app,
            configuration: configuration
        )
    }

    /// Chromium silently creates a fresh empty profile when handed a directory it
    /// doesn't recognise, so a stale rule must fall back to a normal launch rather
    /// than litter the browser. An unreadable profile list is not evidence of
    /// absence, so it is treated as known.
    private static func isKnownProfile(_ profile: String, forAppAt app: URL) -> Bool {
        guard let profiles = ChromiumProfileService.profiles(forAppAt: app) else {
            return true
        }

        return profiles.contains { $0.directory == profile }
    }
}
