# SortAI UI Tests

Comprehensive UI testing suite for the SortAI macOS application using XCTest UI Testing framework.

## Overview

The UI test suite validates critical user workflows and UI interactions, ensuring the application behaves correctly from an end-user perspective.

## Test Coverage

### Settings Panel Tests (13 tests)
- ✅ Opening settings panel
- ✅ Max depth stepper functionality
- ✅ Stability/Correctness slider
- ✅ Watch mode toggle and conditional UI
- ✅ Deep analysis toggle and file types field
- ✅ Soft move (symlinks) toggle
- ✅ Destination picker (centralized/distributed/custom)
- ✅ Apply changes workflow
- ✅ Ollama host field editing
- ✅ Refresh models button
- ✅ Settings persistence (round-trip test)
- ✅ Multiple settings changes
- ✅ Keyboard navigation
- ✅ Accessibility identifiers validation

### Basic Launch Tests (2 tests)
- ✅ App launches successfully
- ✅ Main window elements present

## Running UI Tests

### From Xcode

1. Open the project in Xcode
2. Select the **SortAI** scheme
3. Choose **Product > Test** or press `Cmd+U`
4. To run only UI tests, select the **SortAIUITests** target

### From Command Line

```bash
# Run all tests (including UI tests)
swift test

# Run only UI tests (once SPM supports it)
swift test --filter SortAIUITests
```

### Using Xcode CLI

```bash
# Run all tests
xcodebuild test -scheme SortAI

# Run only UI tests
xcodebuild test -scheme SortAI -only-testing:SortAIUITests
```

## Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Test Configuration

The UI tests run with special launch arguments:
- `--uitesting`: Disables animations for faster, more reliable tests
- `--reset-defaults`: Starts with fresh user defaults
- `--skip-first-launch`: Skips the first launch wizard

## Accessibility Identifiers

All key UI elements have accessibility identifiers for stable test references:

### Settings Panel Identifiers

| Element | Identifier |
|---------|-----------|
| Ollama Host Field | `ollamaHostField` |
| Refresh Models Button | `refreshModelsButton` |
| Default Mode Picker | `defaultModePicker` |
| Destination Picker | `destinationPicker` |
| Custom Path Label | `customPathLabel` |
| Choose Path Button | `choosePathButton` |
| Soft Move Toggle | `softMoveToggle` |
| Max Depth Stepper | `maxDepthStepper` |
| Stability Slider | `stabilitySlider` |
| Enable Deep Analysis Toggle | `enableDeepAnalysisToggle` |
| File Types Field | `fileTypesField` |
| Enable Watch Mode Toggle | `enableWatchModeToggle` |
| Quiet Period Stepper | `quietPeriodStepper` |
| Battery Status Toggle | `batteryStatusToggle` |
| Notifications Toggle | `notificationsToggle` |
| Apply Changes Button | `applyChangesButton` |
| Changes Warning Label | `changesWarningLabel` |

## Writing New UI Tests

### Template for New Tests

```swift
func testMyNewFeature() {
    // 1. Open the relevant UI
    openSettingsPanel()
    
    // 2. Find the element using accessibility identifier
    let myElement = app.buttons["myElementIdentifier"]
    XCTAssertTrue(myElement.waitForExistence(timeout: 2))
    
    // 3. Interact with it
    myElement.click()
    
    // 4. Verify expected behavior
    let result = app.staticTexts["expectedResult"]
    XCTAssertTrue(result.exists)
}
```

### Best Practices

1. **Use Accessibility Identifiers**: Always prefer accessibility identifiers over text-based queries
2. **Wait for Existence**: Use `waitForExistence(timeout:)` instead of assuming elements exist
3. **Isolate Tests**: Each test should be independent and not rely on other tests
4. **Clean State**: Use setUp/tearDown to ensure clean state for each test
5. **Descriptive Names**: Test names should clearly describe what they test
6. **Verify, Don't Assume**: Always assert expected outcomes

### Adding Accessibility Identifiers to New UI

```swift
// In your SwiftUI view:
Button("My Button") {
    // action
}
.accessibilityIdentifier("myButtonIdentifier")

// In your UI test:
let button = app.buttons["myButtonIdentifier"]
XCTAssertTrue(button.exists)
button.click()
```

## Debugging UI Tests

### Common Issues

1. **Element Not Found**
   - Verify accessibility identifier is set correctly
   - Check element exists in current view hierarchy
   - Increase wait timeout if needed

2. **Flaky Tests**
   - Add `waitForExistence()` calls
   - Ensure animations are disabled (`--uitesting` flag)
   - Check for race conditions

3. **Tests Hang**
   - Verify app launches successfully
   - Check for modal dialogs blocking UI
   - Ensure file system access permissions

### Debugging Tips

```swift
// Print element hierarchy
print(app.debugDescription)

// Take screenshot for debugging
let screenshot = app.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.lifetime = .keepAlways
add(attachment)

// Check if element exists without waiting
if myElement.exists {
    print("Element found")
} else {
    print("Element not found")
    print(app.debugDescription)
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: UI Tests

on: [push, pull_request]

jobs:
  ui-tests:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Run UI Tests
      run: |
        xcodebuild test \
          -scheme SortAI \
          -only-testing:SortAIUITests \
          -destination 'platform=macOS'
```

## Performance

- **Average test duration**: 2-5 seconds per test
- **Full suite duration**: ~1-2 minutes (15 tests)
- **Parallel execution**: Supported for independent tests

## Maintenance

### Updating Tests After UI Changes

1. Update accessibility identifiers if changed
2. Update test assertions if behavior changed
3. Add new tests for new features
4. Remove tests for deprecated features
5. Run full suite to catch regressions

## Future Enhancements

- [ ] Main organization workflow tests
- [ ] Wizard flow tests
- [ ] Drag-and-drop tests
- [ ] File system interaction tests
- [ ] Undo/redo tests
- [ ] Conflict resolution UI tests
- [ ] Taxonomy editor tests
- [ ] Performance benchmarks

## Support

For issues or questions about UI tests:
1. Check test output and logs
2. Review accessibility identifiers in source
3. Verify app launches in UI testing mode
4. Check macOS permissions for accessibility

---

**Last Updated**: January 2026  
**Test Count**: 15 tests  
**Coverage**: Settings panel, basic launch, accessibility

