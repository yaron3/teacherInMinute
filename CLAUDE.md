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

Exactly **1242 × 2688 px**, portrait, **RGB, no alpha**. No exceptions — App
Store Connect rejects alpha channels, and a set with mixed sizes fails upload.

### Capture natively, never rescale

Shoot on a simulator whose screen is already 1242 × 2688:

```bash
xcrun simctl create "TIM 6.5in" com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-3
```

`xcrun simctl io <udid> screenshot out.png` then yields exactly 1242 × 2688.

Do **not** downscale from the 6.9" size (1320 × 2868). The two aspect ratios are
close but not equal, so rescaling stretches the image ~0.4% and softens every
glyph. Two simulators are needed for any screen involving a live lesson (one
teacher, one student) — create both at this device type.

### Per-image settings

- **Language** is an app setting, not a device setting: `settings.language.preference`
  = `english` | `hebrew` in the app's `UserDefaults` plist, or Settings → Language
  in-app. Leave the simulator's own language alone.
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
to what it was. Signing out does not clear presence on its own.

### Capture mechanics that are not obvious

- A fast synthetic tap does not move a SwiftUI `Toggle`. Use a press-and-hold-
  then-release of ~100 ms (`touch_path`) for switches.
- `xcrun simctl pbcopy` decodes stdin as MacRoman unless the locale says
  otherwise, which mangles Hebrew. Always
  `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 xcrun simctl pbcopy`. Hebrew cannot be
  typed directly — paste it.
- The availability toggle only fires once per app launch; relaunch to reset it.

### Verify before delivering

```bash
python3 marketing-screenshots/verify-screenshots.py <set-directory>
```

It fails the set on wrong dimensions, an alpha channel, a non-RGB mode, or a
quadrant that does not hold exactly 5 images.
