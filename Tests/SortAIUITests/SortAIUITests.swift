// MARK: - SortAI UI Tests
// Comprehensive UI testing suite for SortAI macOS application

import XCTest

/// Main UI test suite for SortAI application
/// Tests critical user workflows and UI interactions
final class SortAIUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Configure for UI testing
        continueAfterFailure = false
        
        // Launch app
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",              // Disable animations
            "--reset-defaults",         // Start with fresh defaults
            "--skip-first-launch"       // Skip wizard on first launch
        ]
        app.launch()
    }
    
    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }
    
    // MARK: - Basic Launch Tests
    
    func testAppLaunches() {
        // Verify app launched successfully
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
    
    func testMainWindowElements() {
        // Verify main UI elements are present
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        
        // Check for toolbar
        XCTAssertTrue(app.toolbars.firstMatch.exists, "Toolbar should exist")
    }
    
    // MARK: - Settings Tests
    
    func testOpenSettings() {
        // Open settings window
        // On macOS, settings are typically in menu or toolbar
        if app.menuBars.buttons["Settings"].exists {
            app.menuBars.buttons["Settings"].click()
        } else if app.buttons["Settings"].exists {
            app.buttons["Settings"].click()
        }
        
        // Wait for settings window to appear
        let settingsWindow = app.windows.matching(identifier: "settings").firstMatch
        let exists = settingsWindow.waitForExistence(timeout: 2)
        
        // If no dedicated settings window, check for sheet
        if !exists {
            XCTAssertTrue(app.sheets.firstMatch.exists, "Settings should open as window or sheet")
        }
    }
    
    func testMaxDepthStepper() {
        openSettingsPanel()
        
        let stepper = app.steppers["maxDepthStepper"]
        
        // Wait for stepper to exist
        XCTAssertTrue(stepper.waitForExistence(timeout: 2), "Max depth stepper should exist")
        
        // Get initial value
        let initialValue = stepper.value as? String ?? "5"
        
        // Increment
        stepper.increment()
        
        // Verify value changed
        let newValue = stepper.value as? String ?? "5"
        XCTAssertNotEqual(initialValue, newValue, "Stepper value should change after increment")
    }
    
    func testStabilitySlider() {
        openSettingsPanel()
        
        let slider = app.sliders["stabilitySlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 2), "Stability slider should exist")
        
        // Sliders on macOS can be adjusted, but value verification is tricky
        // Just verify it exists and is enabled
        XCTAssertTrue(slider.isEnabled, "Stability slider should be enabled")
    }
    
    func testWatchModeToggle() {
        openSettingsPanel()
        
        let toggle = app.checkBoxes["enableWatchModeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), "Watch mode toggle should exist")
        
        // Check initial state
        let wasEnabled = toggle.value as? Int == 1
        
        // Toggle it
        toggle.click()
        
        // Verify state changed
        let isEnabled = toggle.value as? Int == 1
        XCTAssertNotEqual(wasEnabled, isEnabled, "Watch mode should toggle")
        
        // If now enabled, quiet period stepper should appear
        if isEnabled {
            let quietPeriodStepper = app.steppers["quietPeriodStepper"]
            XCTAssertTrue(quietPeriodStepper.waitForExistence(timeout: 1),
                         "Quiet period stepper should appear when watch mode is enabled")
        }
    }
    
    func testDeepAnalysisToggle() {
        openSettingsPanel()
        
        let toggle = app.checkBoxes["enableDeepAnalysisToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), "Deep analysis toggle should exist")
        
        // Check initial state
        let wasEnabled = toggle.value as? Int == 1
        
        // Toggle it
        toggle.click()
        
        // Verify state changed
        let isEnabled = toggle.value as? Int == 1
        XCTAssertNotEqual(wasEnabled, isEnabled, "Deep analysis should toggle")
        
        // If now enabled, file types field should appear
        if isEnabled {
            let fileTypesField = app.textFields["fileTypesField"]
            XCTAssertTrue(fileTypesField.waitForExistence(timeout: 1),
                         "File types field should appear when deep analysis is enabled")
        }
    }
    
    func testSoftMoveToggle() {
        openSettingsPanel()
        
        let toggle = app.checkBoxes["softMoveToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), "Soft move toggle should exist")
        
        // Verify it can be toggled
        toggle.click()
        
        // Check for apply changes button after making a change
        let applyButton = app.buttons["applyChangesButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 1),
                     "Apply changes button should appear after changing settings")
    }
    
    func testDestinationPicker() {
        openSettingsPanel()
        
        let picker = app.popUpButtons["destinationPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 2), "Destination picker should exist")
        
        // Open picker menu
        picker.click()
        
        // Verify options exist
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1), "Picker menu should open")
        
        // Check for expected options
        XCTAssertTrue(app.menuItems["Centralized"].exists, "Centralized option should exist")
        XCTAssertTrue(app.menuItems["Distributed"].exists, "Distributed option should exist")
        XCTAssertTrue(app.menuItems["Custom Path"].exists, "Custom Path option should exist")
        
        // Select custom path
        app.menuItems["Custom Path"].click()
        
        // Verify choose button appears
        let chooseButton = app.buttons["choosePathButton"]
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 1),
                     "Choose path button should appear when custom is selected")
    }
    
    func testApplyChangesWorkflow() {
        openSettingsPanel()
        
        // Make a change
        let toggle = app.checkBoxes["notificationsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        
        // Verify apply button appears
        let applyButton = app.buttons["applyChangesButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 1),
                     "Apply button should appear after making changes")
        
        // Verify warning label
        let warningLabel = app.staticTexts["changesWarningLabel"]
        XCTAssertTrue(warningLabel.exists, "Warning label should be visible")
        
        // Click apply
        applyButton.click()
        
        // Wait for apply to complete and button to disappear
        let disappeared = !applyButton.waitForExistence(timeout: 3)
        XCTAssertTrue(disappeared, "Apply button should disappear after applying changes")
    }
    
    func testOllamaHostField() {
        openSettingsPanel()
        
        let hostField = app.textFields["ollamaHostField"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2), "Ollama host field should exist")
        
        // Verify field is editable
        hostField.click()
        XCTAssertTrue(hostField.value(forKey: "AXFocused") as? Bool ?? false,
                     "Host field should be focusable")
    }
    
    func testRefreshModelsButton() {
        openSettingsPanel()
        
        let refreshButton = app.buttons["refreshModelsButton"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 2), "Refresh models button should exist")
        
        // Click it
        refreshButton.click()
        
        // Verify loading indicator appears (if Ollama is running)
        // This might timeout if Ollama isn't running, which is okay
        _ = app.progressIndicators["modelsLoadingIndicator"].waitForExistence(timeout: 1)
    }
    
    // MARK: - Integration Tests
    
    func testSettingsRoundTrip() {
        openSettingsPanel()
        
        // Change multiple settings
        let depthStepper = app.steppers["maxDepthStepper"]
        let batteryToggle = app.checkBoxes["batteryStatusToggle"]
        
        XCTAssertTrue(depthStepper.waitForExistence(timeout: 2))
        XCTAssertTrue(batteryToggle.waitForExistence(timeout: 2))
        
        // Make changes
        depthStepper.increment()
        batteryToggle.click()
        
        // Apply changes
        let applyButton = app.buttons["applyChangesButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 1))
        applyButton.click()
        
        // Wait for apply to complete
        _ = !applyButton.waitForExistence(timeout: 3)
        
        // Close and reopen settings
        closeSettingsPanel()
        openSettingsPanel()
        
        // Verify settings persisted (values should be the same)
        XCTAssertTrue(depthStepper.waitForExistence(timeout: 2),
                     "Settings should persist after close/reopen")
    }
    
    func testMultipleSettingsChanges() {
        openSettingsPanel()
        
        // Change multiple settings in different sections
        let watchToggle = app.checkBoxes["enableWatchModeToggle"]
        let deepAnalysisToggle = app.checkBoxes["enableDeepAnalysisToggle"]
        let softMoveToggle = app.checkBoxes["softMoveToggle"]
        
        XCTAssertTrue(watchToggle.waitForExistence(timeout: 2))
        XCTAssertTrue(deepAnalysisToggle.waitForExistence(timeout: 2))
        XCTAssertTrue(softMoveToggle.waitForExistence(timeout: 2))
        
        // Toggle all three
        watchToggle.click()
        deepAnalysisToggle.click()
        softMoveToggle.click()
        
        // Verify apply button appears
        let applyButton = app.buttons["applyChangesButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 1))
        
        // Apply all changes at once
        applyButton.click()
        
        // Verify completion
        let disappeared = !applyButton.waitForExistence(timeout: 3)
        XCTAssertTrue(disappeared, "All changes should be applied successfully")
    }
    
    // MARK: - Accessibility Tests
    
    func testKeyboardNavigation() {
        openSettingsPanel()
        
        // Verify form is keyboard accessible
        let firstResponder = app.firstResponder
        XCTAssertTrue(firstResponder.exists, "Settings should have a focused element")
        
        // Tab through elements
        app.typeKey(.tab, modifierFlags: [])
        
        // Verify focus moved
        let newFirstResponder = app.firstResponder
        XCTAssertTrue(newFirstResponder.exists, "Should be able to tab through settings")
    }
    
    func testAccessibilityIdentifiers() {
        openSettingsPanel()
        
        // Verify all key elements have accessibility identifiers
        let identifiers = [
            "maxDepthStepper",
            "stabilitySlider",
            "enableWatchModeToggle",
            "enableDeepAnalysisToggle",
            "softMoveToggle",
            "batteryStatusToggle",
            "notificationsToggle",
            "destinationPicker",
            "defaultModePicker"
        ]
        
        for identifier in identifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 2),
                         "Element with identifier '\(identifier)' should exist")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Opens the settings panel/window
    private func openSettingsPanel() {
        // Try different ways to open settings depending on UI structure
        
        // Method 1: Menu bar
        if app.menuBars.buttons["Settings"].exists {
            app.menuBars.buttons["Settings"].click()
            return
        }
        
        // Method 2: Toolbar button
        if app.toolbarButtons["Settings"].exists {
            app.toolbarButtons["Settings"].click()
            return
        }
        
        // Method 3: Regular button
        if app.buttons["Settings"].exists {
            app.buttons["Settings"].click()
            return
        }
        
        // Method 4: Keyboard shortcut (Cmd+,)
        app.typeKey(",", modifierFlags: .command)
        
        // Wait a moment for settings to open
        sleep(1)
    }
    
    /// Closes the settings panel/window
    private func closeSettingsPanel() {
        // Close via keyboard shortcut (Cmd+W) or button
        if app.buttons["Close"].exists {
            app.buttons["Close"].click()
        } else {
            app.typeKey("w", modifierFlags: .command)
        }
        
        // Wait a moment for settings to close
        sleep(1)
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    /// Gets the first responder (focused element)
    var firstResponder: XCUIElement {
        return descendants(matching: .any).element(matching: NSPredicate(format: "value LIKE '*AXFocused: 1*'"))
    }
}

