# Teacher Minute — Code Rules

## Architecture

### Views must be minimal and clean (MVVM principle)

Views are for rendering UI only. All business logic, state management, permissions, networking, analytics, and side effects belong in ViewModels.

**What stays in the View:**
- UI state (text fields, toggles, focus, loading spinners tied to `isLoading` from ViewModel)
- Layout and styling
- User interaction handlers that immediately call ViewModel methods
- Environment values and derived UI computed properties

**What moves to ViewModel:**
- Permissions (requesting, checking, handling denial)
- Analytics logging (all service calls)
- Networking and data fetching
- Business logic and validation
- State that affects behavior (not just rendering)
- Localized strings

**Pattern:**
```swift
// ✗ Bad: View handling permission
func findTeacherTapped() async {
  let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
  if !micState.isGranted {
    permissionAlertMessage = "Mic required"
  }
  AnalyticsService.shared.logEvent(...) // Also bad
  submitQuestion(...)
}

// ✓ Good: ViewModel handling permission and analytics
func findTeacherTapped() async {
  let error = await viewModel.submitQuestionWithPermissions(...)
  if let error = error {
    permissionAlertMessage = error
  }
}

// In ViewModel:
func submitQuestionWithPermissions(...) async -> String? {
  let micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
  if !micState.isGranted {
    AnalyticsService.shared.logEvent(AnalyticsEvent.permissionDenied, ...)
    return "Microphone access is required"
  }
  AnalyticsService.shared.logEvent(AnalyticsEvent.askTeacherSubmitted, ...)
  submitQuestion(...)
  return nil
}
```

**Why:** Keeps Views testable without mocking services, makes analytics and permission logic auditable in one place, and makes Views easy to read at a glance.

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

This rule applies to **every** view, not only the ones behind a
`*ViewModeling` protocol. Which mechanism a screen uses depends on what it has:

| The view has… | Where its copy lives |
|---|---|
| A `*ViewModeling` protocol | A protocol extension (`StudentHomeViewModeling`, `TeacherDashboardViewModeling`, `ChatSessionViewModeling`, `SettingsViewModeling`) |
| A concrete view model | `<Name>ViewModel+LocalizedStrings.swift`, an extension on that class |
| No view model, but one owner screen | A `viewModel` property passed down from that screen |
| No view model, and several owner screens | A shared protocol with default implementations — `LessonHistoryViewModeling`, `PhotoSourceViewModeling`, `OnboardingBackViewModeling` |
| A small presentational component | Plain `String` parameters supplied by the caller |

### Presentational components never translate what they are handed

A component that takes a `title` renders it verbatim. Translating a parameter
inside the component means the caller cannot pass anything but a raw English
key, and every caller that already translated its own copy pays for a second,
pointless lookup. `HistoryMetricCard`, `AboutWebView`, `SubjectChip`,
`BadgeView` and the grade chips all used to do this.

### Keys must not collide

`LocalizationKey.generatedKey` reduces a source string to three words, so
distinct strings can land on the same key and one published value ends up
serving both. When that happens, add an explicit entry to
`LocalizationKey.exactKeys` under "Collision fixes" — the string that matches
the value already in the template keeps the original key.

Both invariants — every string reachable from a view model, and no two strings
sharing a key — are checked by:

```bash
python3 backend/Firebase/check-localization.py
```
