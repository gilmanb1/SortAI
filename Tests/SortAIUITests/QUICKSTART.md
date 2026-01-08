# UI Testing Quick Start Guide

Get started with UI testing in SortAI in 5 minutes!

## Run Tests Immediately

### Option 1: Xcode
```bash
# Open project and run tests
open Package.swift
# Then: Cmd+U to run all tests
```

### Option 2: Command Line
```bash
# Run all tests (unit + UI)
swift test

# Or use xcodebuild
xcodebuild test -scheme SortAI
```

## Test What's Already Working

### ✅ Settings Panel Tests (13 tests)

All settings UI interactions are fully tested:

```swift
// Test max depth stepper
func testMaxDepthStepper()

// Test watch mode toggle
func testWatchModeToggle()  

// Test deep analysis toggle
func testDeepAnalysisToggle()

// Test settings persistence
func testSettingsRoundTrip()

// ... and 9 more!
```

## Add Your First Test

### 1. Add Accessibility Identifier to UI

```swift
// In your SwiftUI view
Button("My Feature") {
    myAction()
}
.accessibilityIdentifier("myFeatureButton")  // ← Add this!
```

### 2. Write the Test

```swift
// In Tests/SortAIUITests/SortAIUITests.swift

func testMyNewFeature() {
    // 1. Open the UI
    openSettingsPanel()
    
    // 2. Find your element
    let button = app.buttons["myFeatureButton"]
    XCTAssertTrue(button.waitForExistence(timeout: 2))
    
    // 3. Interact with it
    button.click()
    
    // 4. Verify result
    let result = app.staticTexts["expectedResult"]
    XCTAssertTrue(result.exists, "Feature should show result")
}
```

### 3. Run Your Test

```bash
# Run just your test
xcodebuild test -scheme SortAI -only-testing:SortAIUITests/SortAIUITests/testMyNewFeature
```

## Common Test Patterns

### Toggle a Checkbox
```swift
let toggle = app.checkBoxes["myToggleIdentifier"]
XCTAssertTrue(toggle.waitForExistence(timeout: 2))
toggle.click()
```

### Use a Stepper
```swift
let stepper = app.steppers["myStepperIdentifier"]
stepper.increment()  // or .decrement()
```

### Adjust a Slider
```swift
let slider = app.sliders["mySliderIdentifier"]
XCTAssertTrue(slider.isEnabled)
// Sliders are trickier - best to just verify they exist/enabled
```

### Select from Picker
```swift
let picker = app.popUpButtons["myPickerIdentifier"]
picker.click()
app.menuItems["Option Name"].click()
```

### Type in Field
```swift
let field = app.textFields["myFieldIdentifier"]
field.click()
field.typeText("new value")
```

## Debugging Tests

### Print Element Hierarchy
```swift
print(app.debugDescription)
```

### Take Screenshot
```swift
let screenshot = app.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.lifetime = .keepAlways
add(attachment)
```

### Check If Element Exists
```swift
if !myElement.exists {
    print("Element not found!")
    print("Available elements:")
    print(app.descendants(matching: .any).allElementsBoundByIndex)
}
```

## All Available Identifiers

Quick reference for existing accessibility identifiers:

### Settings Panel
- `ollamaHostField` - Ollama server URL field
- `refreshModelsButton` - Refresh models button
- `maxDepthStepper` - Taxonomy max depth
- `stabilitySlider` - Stability vs Correctness
- `enableWatchModeToggle` - Watch mode on/off
- `quietPeriodStepper` - Watch quiet period (when enabled)
- `enableDeepAnalysisToggle` - Deep analysis on/off
- `fileTypesField` - File types for deep analysis (when enabled)
- `softMoveToggle` - Soft move (symlinks) toggle
- `destinationPicker` - Destination mode picker
- `choosePathButton` - Custom path chooser (when custom selected)
- `batteryStatusToggle` - Respect battery status
- `notificationsToggle` - Show notifications
- `applyChangesButton` - Apply changes button (appears when settings change)

## Tips for Success

1. **Always use `waitForExistence()`** - Don't assume elements exist immediately
2. **Use descriptive test names** - `testWatchModeToggle` is better than `testToggle1`
3. **One thing per test** - Test one feature/behavior per test method
4. **Clean state** - Tests should not depend on each other
5. **Verify outcomes** - Always assert expected results, don't just click

## Next Steps

- Read full documentation: `Tests/SortAIUITests/README.md`
- Add tests for new features as you build them
- Run tests before committing code
- Set up CI/CD to run tests automatically

## Need Help?

1. Check the README for detailed examples
2. Look at existing tests in `SortAIUITests.swift`
3. Print `app.debugDescription` to see available elements
4. Verify accessibility identifiers are set correctly

---

**Happy Testing! 🧪**

