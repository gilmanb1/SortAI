// MARK: - SortAI Application Entry Point
// macOS 26 / Swift 6 / SwiftUI

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.sortai.app", category: "lifecycle")

@main
struct SortAIApp: App {
    @State private var appState = AppState()
    @StateObject private var menuBarStatusManager = MenuBarStatusManager()
    
    init() {
        // Register defaults FIRST before any @AppStorage or ConfigurationManager access
        SortAIDefaults.registerDefaults()
        
        logger.info("🚀 SortAI App initializing... PID: \(ProcessInfo.processInfo.processIdentifier)")
        NSLog("🚀 [DEBUG] SortAI App initializing... PID: %d", ProcessInfo.processInfo.processIdentifier)
        NSLog("🚀 [DEBUG] Default model: %@", SortAIDefaults.defaultModel)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 400, minHeight: 500)
                .onAppear {
                    logger.info("🚀 ContentView appeared")
                    NSLog("🚀 [DEBUG] ContentView appeared")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 450, height: 600)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        // Menu Bar Status Item
        MenuBarExtra {
            MenuBarStatusView(statusManager: menuBarStatusManager)
                .environment(appState)
        } label: {
            MenuBarIcon(statusManager: menuBarStatusManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Helper Extensions

extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

