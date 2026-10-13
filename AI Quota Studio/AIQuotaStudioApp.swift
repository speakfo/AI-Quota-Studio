//
//  AIQuotaStudioApp.swift
//  AI Quota Studio
//

import AppKit
import SwiftUI

@main
struct AIQuotaStudioApp: App {
    init() {
        QuotaBridge.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("AI Quota Studio", systemImage: "gauge.medium") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)

        Window("AI Quota Studio", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
