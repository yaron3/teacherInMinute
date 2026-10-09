# Teacher in a Minute — Project Rules

Swift/SwiftUI code rules live in [teacher-minute/CLAUDE.md](teacher-minute/CLAUDE.md).

## App Store screenshots

Every screenshot deliverable is a **20-image matrix** — 2 languages × 2
appearances × 5 screens:

|         | Light | Dark |
|---------|-------|------|
| English | 5     | 5    |
| Hebrew  | 5     | 5    |

A set is not finished until all four quadrants have their 5 images. Never ship
one language, or one appearance, on its own.

### Both roles, at least 4 images each

Within each **language** — the 10 images across its light and dark quadrants —
at least **4 must be student screens** and at least **4 must be teacher
screens**. The remaining 2 are free, so a language can lean 6/4 either way but
never starve an audience.

That minimum is per language, not per quadrant: a quadrant holds 5 images and so
cannot carry 4 of each role.

On top of it, **every quadrant must contain at least one image of each role**.
Without that, a set whose light images were all student and whose dark images
all teacher would satisfy the per-language count while showing anyone browsing
in dark mode only one of the two audiences.

The two constraints together leave each role between 4 and 6 images per
language. A split like light 3 student / 2 teacher and dark 2 student /
3 teacher satisfies both.

Every screenshot's path must say its role, so the layout carries all three
facts:

    <set>/english/dark/teacher/01-teacher-home.png
    <set>/hebrew/light/student/03-rate-lesson.png

### Output spec

Every screenshot is exactly one of these sizes, **RGB, no alpha**:

| Portrait | Landscape | Simulator that captures it natively |
|----------|-----------|-------------------------------------|
| 1206 × 2622 | 2622 × 1206 | iPhone 17 Pro (or 16 Pro, 17) |
| 1179 × 2556 | 2556 × 1179 | iPhone 16 (or 15 Pro, 15) |
| 2064 × 2752 | 2752 × 2064 | iPad Pro 13-inch (M5 or M4) |
| 2048 × 2732 | 2732 × 2048 | iPad Pro 12.9-inch (6th generation) |

The first two rows are the iPhone sets, the last two the 13-inch iPad sets; an
iPad set follows the same matrix and role rules as an iPhone set and lives in
its own set directory.

No other size. One size per set — a set with mixed sizes fails upload — and App
Store Connect rejects alpha channels. Screenshots are portrait unless asked
otherwise.

App previews (videos, not screenshots) are 886 × 1920 portrait or 1920 × 886
landscape.

### Capture natively, never rescale

Shoot on a simulator whose screen is already the target size. For 1206 × 2622:

```bash
xcrun simctl create "TIM 6.3in" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-3
```

`xcrun simctl io <udid> screenshot out.png` then yields exactly 1206 × 2622.
For 1179 × 2556 use `com.apple.CoreSimulator.SimDeviceType.iPhone-16`; for the
iPad 2064 × 2752 use `com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB`.

Do **not** rescale from another device size. Nearby iPhone aspect ratios are
close but not equal, so rescaling stretches the image slightly and softens every
glyph. A composited marketing image (headline, frame) is built at the same
pixel size as its captures. Two simulators are needed for any screen involving a
live lesson (one teacher, one student) — create both at the same device type.

### Per-image settings

- **Language** is an app setting, not a device setting. Leave the simulator's own
  language alone. Writing `settings.language.preference` = `english` | `hebrew`
  with `defaults write` is enough before the first launch, but switching an
  existing install that way is not: it skips `LocalizationManager`, so the
  `user_language` Analytics property (which Remote Config's `HebrewApp`
  condition reads) keeps its old value and the screens show the other
  language's strings. Switch in the app instead — Settings → Language, pick the
  other language and then the one you want — and check a screen before
  capturing.
- **Appearance**: `xcrun simctl ui <udid> appearance light|dark`, with the app's
  `appearanceMode` left on `system` so the capture is what a real user sees.
- **Status bar**: always override before capturing.
  ```bash
  xcrun simctl status_bar <udid> override --time "9:41" --dataNetwork wifi \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100
  ```

### Accounts

Reuse the standing demo accounts (password `123456` for all four):

| Language | Teacher | Student |
|----------|---------|---------|
| English  | `teacher_demo_english@example.com` | `student_demo_english@example.com` |
| Hebrew   | `teacher_demo_hebrew@example.com` | `student_demo_hebrew@example.com` |

The apps sign in against the live Firebase backend, so Claude cannot type these
passwords itself: navigate to the login screen and ask the user to sign in.
Make it easy for them: paste the email in (`simctl pbcopy` + Paste — don't use
the simulator tool's `text` action, which leaves the device in hardware-keyboard
mode and hides the on-screen keyboard), tap into the password field so the
on-screen keyboard is showing, and tell the user to tap `123` → `123456` → ✓
on that keyboard **inside the Claude simulator preview panel**. Typing on the
Mac keyboard, or clicking in Simulator.app itself, does not reach the field.
If the on-screen keyboard is gone, set `ConnectHardwareKeyboard` false in
`com.apple.iphonesimulator` and reboot the simulator.

Create new accounts only when the screen being captured *is* a sign-up or
onboarding step, since those screens cannot be reached on an existing account.
Record any new account in the set's README with role, email, password and
display name.

### Never send a demo question to a real teacher

Dispatch fans a question out to every online teacher matching its topic
(`WAVE_SIZES = [3, 5, 10]`), so a demo question can reach a real person and bill
them for a real session. Before submitting one:

1. Read `onlineTeachers` in RTDB and see who is actually online.
2. Pick a topic **no live teacher covers** and give it only to the demo teacher.
3. Re-check immediately before submitting — presence changes.

Take the demo teachers offline afterwards, and confirm `onlineTeachers` is back
to what it was. Signing out does not clear presence on its own. Neither does
closing or killing the app, for a teacher with a push token: the backend keeps
a teacher whose app has gone silent available by push
(`backend/Firebase/functions/src/keepAlive.ts`). Turn the toggle off in the app.

### Capture mechanics that are not obvious

- A fast synthetic tap does not move a SwiftUI `Toggle`. Use a press-and-hold-
  then-release of ~100 ms (`touch_path`) for switches.
- `xcrun simctl pbcopy` decodes stdin as MacRoman unless the locale says
  otherwise, which mangles Hebrew. Always
  `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 xcrun simctl pbcopy`. Hebrew cannot be
  typed directly — paste it.
- The availability toggle only fires once per app launch; relaunch to reset it.
- If a live lesson fails with "We couldn't establish an audio connection", read
  the app log before blaming the network: `[LiveKit] connect attempt … failed
  … Audio Engine Error(Audio engine returned error code: -3010)` next to
  `Could not find default device for dOut/dIn` means the simulator lost its
  CoreAudio device (common after the Mac's audio devices change). Shut down and
  reboot both simulators (`xcrun simctl shutdown <udid>` then `boot`), then
  re-apply appearance and the status-bar override. Restarting the app is not
  enough.

### Verify before delivering

```bash
python3 marketing-screenshots/verify-screenshots.py <set-directory>
```

It fails the set on wrong dimensions, an alpha channel, a non-RGB mode, or a
quadrant that does not hold exactly 5 images.
