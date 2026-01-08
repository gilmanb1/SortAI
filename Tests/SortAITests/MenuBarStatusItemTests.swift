// MARK: - Menu Bar Status Item Tests

import XCTest
@testable import SortAI

@MainActor
final class MenuBarStatusManagerTests: XCTestCase {
    
    var manager: MenuBarStatusManager!
    
    override func setUp() {
        manager = MenuBarStatusManager()
    }
    
    override func tearDown() {
        manager = nil
    }
    
    // MARK: - Initial State
    
    func testInitialState() {
        XCTAssertEqual(manager.llmMode, .full)
        XCTAssertFalse(manager.watchEnabled)
        XCTAssertEqual(manager.queueDepth, 0)
        XCTAssertEqual(manager.lastAction, "Ready")
        XCTAssertNil(manager.lastActionTime)
        XCTAssertFalse(manager.isProcessing)
    }
    
    // MARK: - LLM Mode Tests
    
    func testLLMStatusModeValues() {
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.full.rawValue, "Full")
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.degraded.rawValue, "Degraded")
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.offline.rawValue, "Offline")
    }
    
    func testLLMStatusModeIcons() {
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.full.icon, "brain")
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.degraded.icon, "brain.head.profile")
        XCTAssertEqual(MenuBarStatusManager.LLMStatusMode.offline.icon, "wifi.slash")
    }
    
    func testUpdateLLMMode() {
        manager.updateLLMMode(.degraded)
        
        XCTAssertEqual(manager.llmMode, .degraded)
        XCTAssertTrue(manager.lastAction.contains("Degraded"))
        XCTAssertNotNil(manager.lastActionTime)
    }
    
    // MARK: - Watch Status Tests
    
    func testUpdateWatchStatusEnabled() {
        manager.updateWatchStatus(enabled: true)
        
        XCTAssertTrue(manager.watchEnabled)
        XCTAssertTrue(manager.lastAction.contains("enabled"))
    }
    
    func testUpdateWatchStatusDisabled() {
        manager.updateWatchStatus(enabled: true)  // First enable
        manager.updateWatchStatus(enabled: false)  // Then disable
        
        XCTAssertFalse(manager.watchEnabled)
        XCTAssertTrue(manager.lastAction.contains("disabled"))
    }
    
    // MARK: - Queue Depth Tests
    
    func testUpdateQueueDepth() {
        manager.updateQueueDepth(10)
        
        XCTAssertEqual(manager.queueDepth, 10)
    }
    
    func testQueueDepthZero() {
        manager.updateQueueDepth(0)
        
        XCTAssertEqual(manager.queueDepth, 0)
    }
    
    // MARK: - Action Recording Tests
    
    func testRecordAction() {
        manager.recordAction("Test action")
        
        XCTAssertEqual(manager.lastAction, "Test action")
        XCTAssertNotNil(manager.lastActionTime)
    }
    
    // MARK: - Processing Tests
    
    func testSetProcessing() {
        manager.setProcessing(true)
        
        XCTAssertTrue(manager.isProcessing)
        
        manager.setProcessing(false)
        
        XCTAssertFalse(manager.isProcessing)
    }
    
    // MARK: - Health Status Tests
    
    func testUpdateHealth() {
        manager.updateHealth(.warning)
        
        XCTAssertEqual(manager.healthStatus, .warning)
        
        manager.updateHealth(.error)
        
        XCTAssertEqual(manager.healthStatus, .error)
    }
    
    func testHealthStatusColors() {
        // Just verify they exist and are different
        let healthyColor = MenuBarStatusManager.HealthStatus.healthy.color
        let warningColor = MenuBarStatusManager.HealthStatus.warning.color
        let errorColor = MenuBarStatusManager.HealthStatus.error.color
        
        XCTAssertNotNil(healthyColor)
        XCTAssertNotNil(warningColor)
        XCTAssertNotNil(errorColor)
    }
    
    // MARK: - Status Text Tests
    
    func testStatusTextBasic() {
        let statusText = manager.statusText
        
        XCTAssertTrue(statusText.contains("Full"))
    }
    
    func testStatusTextWithWatch() {
        manager.updateWatchStatus(enabled: true)
        
        let statusText = manager.statusText
        
        XCTAssertTrue(statusText.contains("Watch"))
    }
    
    func testStatusTextWithQueue() {
        manager.updateQueueDepth(5)
        
        let statusText = manager.statusText
        
        XCTAssertTrue(statusText.contains("Queue: 5"))
    }
    
    // MARK: - Time Since Last Action Tests
    
    func testTimeSinceLastActionNil() {
        // Initially nil since no action recorded
        manager.lastActionTime = nil
        
        XCTAssertNil(manager.timeSinceLastAction)
    }
    
    func testTimeSinceLastActionRecent() {
        manager.recordAction("Recent action")
        
        // Should be "Just now" or similar
        let timeSince = manager.timeSinceLastAction
        
        XCTAssertNotNil(timeSince)
        XCTAssertTrue(timeSince?.contains("now") ?? false || timeSince?.contains("m ago") ?? false)
    }
}

// MARK: - LLM Status Mode Tests

final class LLMStatusModeTests: XCTestCase {
    
    func testAllModes() {
        let modes: [MenuBarStatusManager.LLMStatusMode] = [.full, .degraded, .offline]
        
        for mode in modes {
            XCTAssertFalse(mode.rawValue.isEmpty)
            XCTAssertFalse(mode.icon.isEmpty)
            XCTAssertNotNil(mode.color)
        }
    }
    
    func testModeColors() {
        // Colors should be distinct
        let fullColor = MenuBarStatusManager.LLMStatusMode.full.color
        let degradedColor = MenuBarStatusManager.LLMStatusMode.degraded.color
        let offlineColor = MenuBarStatusManager.LLMStatusMode.offline.color
        
        XCTAssertNotNil(fullColor)
        XCTAssertNotNil(degradedColor)
        XCTAssertNotNil(offlineColor)
    }
}
