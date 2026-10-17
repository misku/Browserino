//
//  BrowserinoApp.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI
import Foundation

/// Toolbar-style Settings, the macOS convention for a multi-pane settings
/// window. It reopens on the pane last used.
final class SettingsTabViewController: NSTabViewController {
    @AppStorage("settingsTab") private var lastPane: Int = 0

    init() {
        super.init(nibName: nil, bundle: nil)

        tabStyle = .toolbar
        // The window keeps the size the user gave it instead of jumping to
        // each pane's own size.
        transitionOptions = []

        for pane in SettingsPane.allCases {
            let controller = NSHostingController(
                rootView: pane.content.frame(minWidth: 700, minHeight: 500)
            )
            controller.sizingOptions = []
            controller.title = pane.title

            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }

        if tabViewItems.indices.contains(lastPane) {
            selectedTabViewItemIndex = lastPane
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        lastPane = selectedTabViewItemIndex
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var selectorWindow: BrowserinoWindow?
    private var preferencesWindow: NSWindow?
    
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [BrowserTarget] = []
    @AppStorage("apps") private var apps: [App] = []
    @AppStorage("apps_autoOpen") private var autoOpenApps: Bool = false
    @AppStorage("catchallTargets") private var catchallTargets: [BrowserTarget] = []
    @AppStorage("catchallIncognito") private var catchallIncognito: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    
    var statusMenu: NSMenu!
    var statusBarItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBar()
        
        UserDefaults.standard.addObserver(self, forKeyPath: "showInMenuBar", options: [.new], context: nil)

        // Earlier builds recorded Escape, Return and other keys the picker needs
        // for itself. Such a row showed a blank shortcut and could steal the key.
        let validShortcuts = shortcuts.filter { PickerShortcut.isValid($0.value) }
        if validShortcuts.count != shortcuts.count {
            shortcuts = validShortcuts
        }
        
        if UserDefaults.standard.object(forKey: "browsers") == nil {
            openPreferences()
        } else {
            // Splits browsers into their profile rows, and carries their shortcuts
            // over, before the first pop-up rather than on the first Preferences visit.
            browsers = BrowserUtil.loadBrowsers(oldBrowsers: browsers)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        self.openPreferences()
        return true
    }
    
    func setupStatusBar() {
        if showInMenuBar {
            if statusBarItem == nil {
                statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let statusButton = statusBarItem!.button
                statusButton!.image = NSImage.menuIcon
                
                let preferences = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
                let quit = NSMenuItem(title: "Quit Browserino", action: #selector(quitApp), keyEquivalent: "q")
                
                statusMenu = NSMenu()
                
                statusMenu!.addItem(preferences)
                statusMenu!.addItem(.separator())
                statusMenu!.addItem(quit)
                
                statusBarItem!.menu = statusMenu!
            }
        } else {
            if statusBarItem != nil {
                NSStatusBar.system.removeStatusItem(statusBarItem!)
                statusBarItem = nil
            }
        }
    }
    
    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "showInMenuBar" {
            // Another process writing our defaults delivers this off the main
            // thread, so hop rather than assuming isolation.
            Task { @MainActor in
                setupStatusBar()
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "showInMenuBar")
    }
    
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        if userActivityType == NSUserActivityTypeBrowsingWeb {
            return true
        }
        
        return false
    }
    
    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            self.application(application, open: [url])
            return true
        }
        
        return false
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func openPreferences() {
        // Already open: bring it forward without throwing away what the user
        // is in the middle of.
        if let preferencesWindow, preferencesWindow.isVisible {
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }

        if preferencesWindow == nil {
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.closable, .resizable, .titled],
                backing: .buffered,
                defer: false
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(preferencesWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: preferencesWindow
            )
        }

        // Fresh panes on every open, so folded rows, sheets and half-typed
        // fields from last time are gone.
        preferencesWindow!.contentViewController = SettingsTabViewController()
        preferencesWindow!.toolbarStyle = .preference
        preferencesWindow!.setContentSize(NSSize(width: 760, height: 560))
        preferencesWindow!.center()

        preferencesWindow!.isReleasedWhenClosed = false

        preferencesWindow!.contentMinSize = NSSize(width: 700, height: 500)

        preferencesWindow!.collectionBehavior = [.moveToActiveSpace, .fullScreenNone, .managed, .participatesInCycle]

        // A regular app shows in Cmd-Tab; switch back once Preferences closes.
        NSApp.setActivationPolicy(.regular)

        NSApplication.shared.activate(ignoringOtherApps: true)

        preferencesWindow!.makeKeyAndOrderFront(nil)
        preferencesWindow!.orderFrontRegardless()
    }

    @objc func preferencesWindowWillClose(_ notification: Notification) {
        preferencesWindow?.collectionBehavior.remove(.managed)
        preferencesWindow?.collectionBehavior.remove(.participatesInCycle)

        NSApp.setActivationPolicy(.accessory)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        var processedUrls = urls
        
        if urls.count == 1 {
            let url = urls.first!
            
            if url.scheme == "browserino" && url.host == "open" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let encodedUrl = queryItems.first(where: { $0.name == "url" })?.value,
                   let decodedData = Data(base64Encoded: encodedUrl),
                   let decodedUrlString = String(data: decodedData, encoding: .utf8),
                   let decodedUrl = URL(string: decodedUrlString) {
                    processedUrls = [decodedUrl]
                } else {
                    return
                }
            }
            
            if let rule = rules.first(where: { $0.matches(processedUrls.first!) }) {
                route(processedUrls, to: rule.targets, isIncognito: rule.isIncognito)
                return
            }

            // Rules win. Then an App the picker would list for this link opens
            // directly, but only one bound to a host: an App with an empty host
            // matches every link and stays a picker entry.
            if autoOpenApps, let app = apps.first(where: { app in
                !app.host.isEmpty
                    && processedUrls.first!.matchesHost(app.host)
                    && !browsers.contains(app.target)
                    && Bundle(url: app.app) != nil
            }) {
                BrowserUtil.openURL(
                    app.urlsToOpen(processedUrls),
                    target: app.target,
                    isIncognito: false
                )
                return
            }

            // Whatever no rule or App took goes to Default catchall, which is
            // the full picker until the user picks browsers for it.
            route(processedUrls, to: catchallTargets, isIncognito: catchallIncognito)
            return
        }

        showPicker(urls: processedUrls)
    }

    /// One installed browser opens the link directly and several show the
    /// picker with only those. With none installed the link would otherwise
    /// go nowhere, so the full picker shows instead.
    private func route(_ urls: [URL], to targets: [BrowserTarget], isIncognito: Bool) {
        let installed = targets.withoutDuplicates.filter { Bundle(url: $0.app) != nil }

        switch installed.count {
        case 0:
            showPicker(urls: urls)
        case 1:
            BrowserUtil.openURL(urls, target: installed[0], isIncognito: isIncognito)
        default:
            showPicker(urls: urls, targets: installed, isIncognito: isIncognito)
        }
    }

    /// `targets` limits the picker to those browsers, in that order.
    private func showPicker(
        urls: [URL],
        targets: [BrowserTarget]? = nil,
        isIncognito: Bool = false
    ) {
        // A picker with no rows can only be dismissed. General's Reset empties
        // the browser list until the next scan, so scan first, and send the
        // user to Settings if there is still nothing to offer.
        if targets == nil {
            if browsers.isEmpty {
                browsers = BrowserUtil.loadBrowsers(oldBrowsers: [])
            }

            let hasBrowser = browsers.contains {
                !hiddenBrowsers.contains($0) && Bundle(url: $0.app) != nil
            }
            let hasApp = apps.contains { app in
                urls.contains { $0.matchesHost(app.host) } && Bundle(url: app.app) != nil
            }

            guard hasBrowser || hasApp else {
                openPreferences()
                return
            }
        }

        if selectorWindow == nil {
            selectorWindow = BrowserinoWindow()
        }
        
        let screen = getScreenWithMouse()!.visibleFrame
        
        selectorWindow?.setFrameOrigin(
            NSPoint(
                x: clamp(
                    min: screen.minX + 20,
                    max: screen.maxX - selectorWindow!.frame.width - 20,
                    value: NSEvent.mouseLocation.x - selectorWindow!.frame.width / 2
                ),
                y: clamp(
                    min: screen.minY + 20,
                    max: screen.maxY - selectorWindow!.frame.height - 20,
                    value: NSEvent.mouseLocation.y - (selectorWindow!.frame.height - 30)
                )
            )
        )
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        selectorWindow!.deactivateDelay()
        
        selectorWindow!.contentView = NSHostingView(
            rootView: PromptView(
                urls: urls,
                targets: targets,
                isIncognito: isIncognito
            )
        )
        
        selectorWindow!.makeKeyAndOrderFront(nil)
        selectorWindow!.isReleasedWhenClosed = false
        selectorWindow!.delegate = self
    }
    
    func clamp(min: CGFloat, max: CGFloat, value: CGFloat) -> CGFloat {
        CGFloat.minimum(CGFloat.maximum(min, value), max)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if selectorWindow!.hidesOnDeactivate {
            selectorWindow!.contentView = nil
            selectorWindow!.close()
        }
    }
    
    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        
        return screenWithMouse
    }
}
