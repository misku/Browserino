//
//  main.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import AppKit
import Foundation

// Help tags wait about a second by default, long enough that people stop
// hovering before learning what an icon button does. Read once at launch.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])

let app = BrowserinoApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
