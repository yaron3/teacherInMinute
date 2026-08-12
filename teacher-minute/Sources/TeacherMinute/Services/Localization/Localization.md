# Localization with Firebase Remote Config

A drop-in localization module that lets you ship translations through Firebase
Remote Config instead of `Localizable.xcstrings`, so copy edits don't require
an app update. The module also handles the live language switch (locale,
layout direction, and translated text all update in the same render pass) and
shows a spinner while Remote Config refreshes.

Assumes Firebase is already wired up in the host app.

---

## Files that make up the module

Copy these files together — they have no dependencies on app-specific types:

| File | Role |
|---|---|
| `LocalizationSupport.swift` | Static API: `localized(_:)`, `currentLanguageCode`, `locale(languagePreference:)`, `layoutDirection(languagePreference:)`, `applyPlatformLayoutDirection`, `languagePreferenceKey` |
| `LocalizationManager.swift` | `@Observable` singleton holding `isLoading` / `dataFetched` and the async `updateLanguageCode(to:)` orchestration |
| `LocalizationServiceProtocol.swift` | Protocol + `StaticLocalizationService` fallback for previews/tests |
| `RemoteConfigLocalizationService.swift` | Maps English source → snake_case key → Remote Config value, with local fallbacks. **Edit `LocalizationKey.exactKeys` per app.** |
| `RemoteConfigService.swift` | Thin wrapper around Firebase Remote Config (`start`, `refresh`, `readString`) |
| `SettingsLanguageChoice.swift` | The user-facing language enum (`system`/`english`/`hebrew`/…) — add cases as you add languages |
| `AndroidLocaleBridge.swift` + `Android/.../AndroidLocaleManager.kt` | Skip-bridged helper that pushes the new language into the JVM locale and the Firebase RC custom signals on Android |

That's the whole reusable surface. Everything else (settings UI, root view
wiring) is **app integration**, covered below.

---

## How a language change flows

```
User taps "Hebrew"
        │
        ▼
SettingsViewModel.updateLanguage(.hebrew)
  • selectedLanguage = .hebrew              ← checkmark moves immediately
  • Analytics.setUserProperty("he", "app_language")   ← analytics only
  • Task { await LocalizationManager.shared.updateLanguageCode(to: "he") }
        │
        ▼
LocalizationManager.updateLanguageCode("he")
  • updates languageCode / locale / layoutDirection (Observable)
  • writes UserDefaults "appLanguage" + "AppleLanguages"
  • applySystemLocaleOverride (Android JVM)
  • applyRemoteConfigLanguageSignal → user_language user property
  • isLoading = true                         ← spinner shows
  • await RemoteConfigService.refresh(language: "he")  ← Firebase round-trip
  • dataFetched = true; isLoading = false    ← spinner hides
        │
        ▼
SettingsViewModel.updateLanguage continuation
  • UserDefaults.set("hebrew", forKey: languagePreferenceKey)
        │
        ▼
Root view @AppStorage(languagePreferenceKey) re-fires
  • .environment(\.locale, …)        ← flips
  • .environment(\.layoutDirection, …) ← flips
  • .id("\(languagePreference)-…")    ← rebuilds whole subtree
  • Every LocalizationSupport.localized(...) re-reads now-cached RC values
```

Two ordering rules make or break this flow:

1. **Write `languagePreferenceKey` last**, only after `updateLanguageCode`
   returns. That guarantees the locale flip and the translation refresh land
   in the same render pass instead of staggered.

2. **Always pass `language:` to `refresh()` during a switch.** Because of
   rule 1, `LocalizationSupport.currentLanguageCode` still returns the
   *outgoing* language for the whole duration of `updateLanguageCode`.
   `refresh()` re-publishes the language signal right before fetching, so
   letting it fall back to that default overwrites the incoming language with
   the outgoing one and the server hands back the language the user just
   moved away from. This was a live bug: the UI stayed Hebrew after
   selecting English, and no amount of fixing the *client* side helped,
   because the fetch itself was asking for the wrong language.

---

## App integration checklist

### 1. App launch

In your app delegate's `onInit`/`didFinishLaunching`, after `FirebaseApp.configure()`:

```swift
RemoteConfigService.shared.start()
```

This applies the saved-language signal, configures fetch settings, and kicks
off the initial fetch-and-activate.

### 2. Root view

```swift
struct RootView: View {
    @AppStorage(LocalizationSupport.languagePreferenceKey)
    var languagePreference = SettingsLanguageChoice.system.rawValue

    var body: some View {
        AppContent()
            .environment(\.locale,
                LocalizationSupport.locale(languagePreference: languagePreference))
            .environment(\.layoutDirection,
                LocalizationSupport.layoutDirection(languagePreference: languagePreference))
            .id(languagePreference)  // forces full subtree rebuild
            .onAppear {
                LocalizationSupport.applyPlatformLayoutDirection(
                    languagePreference: languagePreference)
            }
            .onChange(of: languagePreference) { _, new in
                LocalizationSupport.applyPlatformLayoutDirection(
                    languagePreference: new)
            }
    }
}
```

`applyPlatformLayoutDirection` calls `UIView.appearance().semanticContentAttribute = …`
so UIKit-backed controls (nav bar, tab bar) flip too.

### 3. Translated strings

Replace every `NSLocalizedString(...)` / `Text("key")` with:

```swift
LocalizationSupport.localized("English source text")
```

The English source string IS the key — the lookup maps it to a stable
snake_case key via `LocalizationKey.key(for:)`. No `.xcstrings` file required.

### 4. Language settings screen

```swift
struct LanguageSettingsView: View {
    let viewModel: SettingsViewModel
    @State var localizationManager = LocalizationManager.shared

    var body: some View {
        // Reading these triggers a re-render once Remote Config is ready.
        let _ = localizationManager.languageCode
        let _ = localizationManager.dataFetched

        ZStack {
            Form { /* language picker */ }
                .disabled(localizationManager.isLoading)

            if localizationManager.isLoading {
                Color.black.opacity(0.18).ignoresSafeArea()
                ProgressView().scaleEffect(1.4)
            }
        }
    }
}
```

And in the view-model:

```swift
func updateLanguage(_ language: SettingsLanguageChoice) {
    selectedLanguage = language                 // checkmark updates now
    // Reporting only. The property the Remote Config condition reads is
    // `user_language`, set inside updateLanguageCode → the fetch that
    // follows it is what actually picks the translation set.
    Analytics.setUserProperty(language.remoteConfigLanguageCode,
                              forName: "app_language")
    let managerCode = localizationManagerCode(for: language)
    Task {
        await LocalizationManager.shared.updateLanguageCode(to: managerCode)
        // Write LAST — see "How a language change flows" above.
        UserDefaults.standard.set(language.rawValue,
            forKey: LocalizationSupport.languagePreferenceKey)
    }
}

private func localizationManagerCode(for language: SettingsLanguageChoice) -> String {
    switch language {
    case .system: return ""        // empty == follow system
    case .english: return "en"
    case .hebrew: return "he"
    }
}
```

The `selectedLanguage` property must **not** write `languagePreferenceKey`
in a `didSet` — that's the bug we fixed: it caused layout to flip
instantly while text lagged until the user navigated.

---

## Firebase Remote Config template

For every snake_case key in `LocalizationKey.exactKeys` (and every
auto-generated key from `LocalizationKey.generatedKey`), add a parameter to
the Remote Config template:

- **Default value**: the English source string.
- **Conditional values**: one per supported language, gated by a condition
  on the user property `user_language == "he"` (etc).

The module sets the `user_language` Analytics user property both at startup
and on every language change (`LocalizationManager.applyRemoteConfigLanguageSignal`),
and the Firebase SDK ships it in the fetch request's `analyticsUserProperties`
field — that's how Firebase decides which conditional value to serve.

> ⚠️ **The condition must key off the user property, not `device.language`.**
> A `device.language in ['he']` condition looks equivalent but is not: the
> Android SDK builds that field from
> `context.getResources().getConfiguration().locale` at fetch time, so it
> reports the *device* locale and an in-app language switch never reaches it
> reliably. `backend/Firebase/remote_config_tim.json` still ships the old
> `device.language` condition — migrating it to `user_language` is the
> outstanding piece of work.

> ⚠️ `RemoteConfigService.configureRemoteConfig` sets
> `minimumFetchInterval = 3600`, which is why `refresh()` calls
> `fetch(withExpirationDuration: 0)` explicitly — `fetchAndActivate()` alone
> honors the throttle and would serve stale values on a language switch.

---

## Adding a new language

1. Add a case to `SettingsLanguageChoice` (e.g. `case arabic`).
2. Map it in `remoteConfigLanguageCode` (`"ar"`).
3. Add the user-facing title/subtitle strings in the enum.
4. If the language is RTL, add its ISO code to the array in
   `LocalizationManager.layoutDirection(for:)` (already includes `ar`/`he`/
   `iw`/`fa`/`ur`).
5. Add it to `LocalizationSupport.supportedLanguageCodes` so the system-
   language resolution can pick it up.
6. Add the corresponding conditional values to your Firebase RC template.
7. Map the language code in `localizationManagerCode(for:)` inside the
   settings view-model.

---

## Adding a new translatable string

1. In code, call `LocalizationSupport.localized("My new English text.")`.
2. Open `RemoteConfigLocalizationService.swift` →
   `LocalizationKey.exactKeys`. If the auto-generated key would collide or
   read poorly, add an explicit `"My new English text.": "my_new_text"`
   mapping. Otherwise the auto-generator handles it.
3. Add the same key to the Remote Config template with the English default
   plus one conditional value per supported language.
4. Publish the template — no app update required.

---

## Language names must never be translated

When displaying the name of a language in the settings screen, **always show it in the language's own script — never translate it into the currently active language.**

```swift
// CORRECT — hardcoded native form, NOT wrapped in localized()
case .english: "English"
case .hebrew:  "עברית"
case .arabic:  "العربية"
case .russian: "Русский"

// WRONG — translating the name defeats the purpose
case .hebrew: LocalizationSupport.localized("Hebrew")   // ❌
```

**Why:** A user who has accidentally switched to a language they don't understand must still be able to find and select their own language. If language names are translated, a Hebrew speaker looking at an app stuck in English will see "Hebrew" — a word they may not recognise. Seeing "עברית" makes the option self-evident regardless of what language the rest of the app is showing.

This rule applies to every place a language name appears: pickers, confirmation dialogs, analytics labels, etc. The only exception is the `system` case, whose label ("System Language", "Use the device language") follows the active language because it is a functional description rather than a proper name.

---

## Gotchas

- **Two UserDefaults keys** — `LocalizationManager` writes `appLanguage` +
  `AppleLanguages`; `LocalizationSupport` reads its own
  `settings.language.preference`. They're kept in sync by the orchestration
  in `SettingsViewModel.updateLanguage`. Don't write either one directly
  from elsewhere.
- **Android JVM locale** — `AndroidLocaleBridge.applyLanguageCode` updates
  `Locale.setDefault` and the app resources' configuration. Note this does
  *not* reliably drive Firebase RC's `device.language`:
  `ConfigFetchHttpClient` reads
  `context.getResources().getConfiguration().locale`, not
  `Locale.getDefault()`, and `AppCompatDelegate.setApplicationLocales` applies
  asynchronously via an activity recreation. Treat the JVM locale as being
  for date/number formatting and system-provided strings; use the
  `user_language` user property to steer Remote Config.
- **A language switch needs a successful network fetch.** Every translated
  string comes from Remote Config, so offline — or after the server's fetch
  throttle kicks in (429 → SDK backoff) — the UI silently keeps the previous
  language. `refresh()` swallows the failure into a single
  `logger.error("[RemoteConfig] refresh failed: …")`. Toggling languages
  repeatedly while testing hits the throttle fast; check that log line before
  assuming a client-side bug.
- **`setUserProperty` is not synchronous.** It goes through the Analytics
  measurement service, and Remote Config reads user properties via the
  Analytics connector at fetch time. A fetch issued immediately after the
  write can still carry the previous value. `setCustomSignals` has the same
  shape but is deterministic if awaited — it is
  `Tasks.call(executor) { … .commit() }` into RC's own SharedPreferences.
  `AndroidLocaleManager.applyRemoteConfigLanguageSignal` already sends
  `app_language` / `language` / `locale` as custom signals, so a
  `customSignal` condition is available as a fallback if the user property
  proves laggy.
- **Don't `await` from `didSet`** — keep all async work in `updateLanguage`,
  not in property observers, so the call site controls the ordering.
- **Force-LTR contexts** — math editor, whiteboard, login form, chat bubble
  scaffolding etc. use `.environment(\.layoutDirection, .leftToRight)` to
  pin LTR inside an RTL app. Use that escape hatch sparingly.
