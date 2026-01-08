// MARK: - Degraded Mode UI Tests

import XCTest
@testable import SortAI

final class LLMUnavailableActionTests: XCTestCase {
    
    func testActionValues() {
        // Test that all actions exist
        let retry = LLMUnavailableAlert.LLMUnavailableAction.retry
        let degraded = LLMUnavailableAlert.LLMUnavailableAction.useDegraded
        let wait = LLMUnavailableAlert.LLMUnavailableAction.waitForRecovery
        
        XCTAssertNotNil(retry)
        XCTAssertNotNil(degraded)
        XCTAssertNotNil(wait)
    }
}

// MARK: - LLM Status Banner Mode Tests

final class LLMStatusBannerModeTests: XCTestCase {
    
    func testModeBackgroundColors() {
        let modes: [LLMStatusBanner.LLMMode] = [.full, .degraded, .offline, .recovering]
        
        for mode in modes {
            let color = mode.backgroundColor
            XCTAssertNotNil(color)
        }
    }
    
    func testModeBorderColors() {
        let modes: [LLMStatusBanner.LLMMode] = [.full, .degraded, .offline, .recovering]
        
        for mode in modes {
            let color = mode.borderColor
            XCTAssertNotNil(color)
        }
    }
    
    func testModeIconColors() {
        let modes: [LLMStatusBanner.LLMMode] = [.full, .degraded, .offline, .recovering]
        
        for mode in modes {
            let color = mode.iconColor
            XCTAssertNotNil(color)
        }
    }
    
    func testModeIcons() {
        XCTAssertEqual(LLMStatusBanner.LLMMode.full.icon, "checkmark.circle.fill")
        XCTAssertEqual(LLMStatusBanner.LLMMode.degraded.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(LLMStatusBanner.LLMMode.offline.icon, "wifi.slash")
        XCTAssertEqual(LLMStatusBanner.LLMMode.recovering.icon, "arrow.clockwise")
    }
    
    func testModeTitles() {
        XCTAssertEqual(LLMStatusBanner.LLMMode.full.title, "Full Mode")
        XCTAssertEqual(LLMStatusBanner.LLMMode.degraded.title, "Degraded Mode")
        XCTAssertEqual(LLMStatusBanner.LLMMode.offline.title, "Offline")
        XCTAssertEqual(LLMStatusBanner.LLMMode.recovering.title, "Reconnecting...")
    }
    
    func testModeDescriptions() {
        let modes: [LLMStatusBanner.LLMMode] = [.full, .degraded, .offline, .recovering]
        
        for mode in modes {
            XCTAssertFalse(mode.description.isEmpty)
        }
    }
}

// MARK: - LLM Mode UI Representation Tests

final class LLMModeUITests: XCTestCase {
    
    func testFullModeIsHealthy() {
        let mode = LLMStatusBanner.LLMMode.full
        
        XCTAssertEqual(mode.title, "Full Mode")
        XCTAssertEqual(mode.icon, "checkmark.circle.fill")
    }
    
    func testDegradedModeAppearance() {
        let mode = LLMStatusBanner.LLMMode.degraded
        
        XCTAssertEqual(mode.title, "Degraded Mode")
        XCTAssertTrue(mode.icon.contains("exclamationmark"))
    }
    
    func testOfflineModeAppearance() {
        let mode = LLMStatusBanner.LLMMode.offline
        
        XCTAssertEqual(mode.title, "Offline")
        XCTAssertTrue(mode.icon.contains("wifi.slash"))
    }
    
    func testRecoveringModeAppearance() {
        let mode = LLMStatusBanner.LLMMode.recovering
        
        XCTAssertTrue(mode.title.contains("Reconnect"))
        XCTAssertTrue(mode.icon.contains("clockwise"))
    }
}

// MARK: - Degraded Mode Constants Tests

final class DegradedModeConstantsTests: XCTestCase {
    
    func testModeDescriptionsAreInformative() {
        let fullDesc = LLMStatusBanner.LLMMode.full.description
        let degradedDesc = LLMStatusBanner.LLMMode.degraded.description
        
        // Descriptions should explain what the mode means
        XCTAssertTrue(fullDesc.contains("LLM") || fullDesc.contains("connected") || fullDesc.contains("ready"))
        XCTAssertGreaterThan(degradedDesc.count, 10, "Description should be meaningful")
    }
}
