# Teacher Minute — Code Rules

## Architecture

### No `LocalizationSupport.localized` in views

Views must never call `LocalizationSupport.localized(...)` directly. All localized strings must be requested from the view model.

- Add string properties/methods to the `*ViewModeling` protocol via a **protocol extension** with default implementations that call `LocalizationSupport.localized(...)`.
- The concrete `ViewModel` and `MockViewModel` classes inherit the defaults automatically — no extra code needed.
- The view calls `viewModel.xxx` instead of `LocalizationSupport.localized("xxx")`.

**Why:** Keeps views free of localization logic, makes all UI text testable through the mock, and centralises string management in a single layer.

**Example pattern — protocol extension in the ViewModel file:**
```swift
extension MyViewModeling {
  var continueButtonLabel: String { LocalizationSupport.localized("Continue") }
  var errorTitle: String { LocalizationSupport.localized("Error") }
  var greetingText: String {
    String(format: LocalizationSupport.localized("Hello, %@"), name)
  }
  func subjectCountText(for subject: Subject) -> String {
    String(format: LocalizationSupport.localized("%d teachers"), subject.count)
  }
}
```

**Example pattern — view:**
```swift
Text(viewModel.continueButtonLabel)
Text(viewModel.greetingText)
Text(viewModel.subjectCountText(for: subject))
```

This rule applies to every view that has a `*ViewModeling` protocol:
- `StudentHomeViewModeling` (done)
- `TeacherDashboardViewModeling` (done)
- `ChatSessionViewModeling` (done)
- `SettingsViewModeling` (done)
