import Foundation

/// Production `LocalizationServiceProtocol` impl. Maps the source English
/// string to a stable snake-case key (matching the Firebase Remote Config
/// template), looks it up via `RemoteConfigService`, and falls back to the
/// source string if the active config has no entry.
struct RemoteConfigLocalizationService: LocalizationServiceProtocol {
    func localized(_ english: String) -> String {
        let key = LocalizationKey.key(for: english)
        let languageCode = LocalizationSupport.currentLanguageCode
        let value = RemoteConfigService.readString(key)
        let fallback = Self.localFallback(for: english, languageCode: languageCode)
        let shouldUseFallback = value.isEmpty || (languageCode != "en" && value == english)
        let resolvedValue = shouldUseFallback ? (fallback ?? english) : value
        #if os(Android)
        logger.info("[Localization][Android] english='\(Self.debugSnippet(english))' key='\(key)' language=\(languageCode) fallback=\(shouldUseFallback) value='\(Self.debugSnippet(resolvedValue))'")
        #endif
        return resolvedValue
    }

    private static func localFallback(for english: String, languageCode: String) -> String? {
        guard languageCode == "he" else { return nil }
        return hebrewFallbacks[english]
    }

    private static let hebrewFallbacks: [String: String] = [
        "I agree to the [Terms of Service](teacherminute://terms) and [Privacy Policy.](teacherminute://privacy)": "אני מסכים/ה ל[תנאי השירות](teacherminute://terms) ול[מדיניות הפרטיות.](teacherminute://privacy)",
        "Terms of Service": "תנאי השירות"
    ]

    #if os(Android)
    private static func debugSnippet(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "\n", with: "\\n")
        return sanitized.count > 80 ? String(sanitized.prefix(80)) + "..." : sanitized
    }
    #endif
}

/// Mapping from human-readable English source strings to the snake-case keys
/// stored in `backend/Firebase/remote_config_teacher_in a moment.json`. Lives
/// in one place so a new key is added by editing this file plus the Remote
/// Config template — no scattered helpers in views or view-models.
enum LocalizationKey {
    static func key(for english: String) -> String {
        if let exact = exactKeys[english] {
            return exact
        }
        return generatedKey(for: english)
    }

    /// Explicit overrides for strings whose auto-generated key would collide
    /// or read poorly. Disambiguates colliding variants by appending suffixes
    /// like `_caps`, `_dot`, `_qmark`, `_ellipsis`, `_a`/`_b`, etc.
    private static let exactKeys: [String: String] = [
        "": "empty_string",
        "(127 reviews)": "reviews_127",
        " and": "and_a",
        "!": "exclamation_mark",
        "%@ subtopics": "fmt_subtopics_a",
        "%@ • %@": "fmt_two_dot_separator",
        "%@ • %@ • %@": "fmt_three_dot_separator",
        "%d": "fmt_d",
        "%d Waiting": "fmt_waiting",
        "%d min": "fmt_min",
        "%d min ago": "fmt_min_ago",
        "%d subjects": "fmt_subjects",
        "%d subtopics": "fmt_subtopics_b",
        "%d/%d": "fmt_d_slash_d",
        "&": "ampersand",
        "/min": "min_a",
        "1 min": "min_1",
        "1 min ago": "min_ago_1",
        "4.9": "rating_4_9",
        "ABOUT": "about_caps",
        "ACCOUNT & SECURITY": "account_security_caps",
        "Algebra": "algebra_a",
        "Already have an account?": "already_have_account_qmark",
        "I agree to the [Terms of Service](teacherminute://terms) and [Privacy Policy.](teacherminute://privacy)": "agree_terms_privacy_markdown",
        "Are you sure you want to end this session?": "are_you_sure_end_session",
        "Audio": "audio_title",
        "Could not send rating. Please try again next time.": "could_not_send_dot_a",
        "Could not send your message.": "could_not_send_dot_b",
        "Could not start the audio/video connection. Please try again.": "could_not_start_audio_video",
        "Enter your email address first.": "enter_your_email_dot_a",
        "Enter your email or phone number and we'll\nsend you instructions to reset your password.": "enter_your_email_dot_b",
        "End session?": "end_session_qmark",
        "Grade 1": "grade_1",
        "Grade 10": "grade_10",
        "Grade 11": "grade_11",
        "Grade 12": "grade_12",
        "Grade 2": "grade_2",
        "Grade 3": "grade_3",
        "Grade 4": "grade_4",
        "Grade 5": "grade_5",
        "Grade 6": "grade_6",
        "Grade 7": "grade_7",
        "Grade 8": "grade_8",
        "Grade 9": "grade_9",
        "I am a Student": "student_a",
        "I am a Teacher": "teacher_a",
        "Key 1": "key_1",
        "Key 2": "key_2",
        "LANGUAGE": "language_caps",
        "Messages": "messages_a",
        "Microphone access is required for an audio session.": "microphone_access_audio_session",
        "Microphone access is required to accept an audio session.": "microphone_access_accept_audio",
        "Microphone and camera access are required for a video session.": "microphone_camera_video_session",
        "Microphone and camera access are required to accept a video session.": "microphone_camera_accept_video",
        "No messages": "messages_b",
        "OFF": "off_caps",
        "OK": "ok",
        "ON": "on_caps",
        "ORIGINAL QUESTION": "original_question_caps",
        "On": "on",
        "PAYMENTS": "payments_caps",
        "PayPal Checkout": "paypal_checkout_a",
        "PayPal at checkout": "paypal_checkout_b",
        "Privacy Policy": "privacy_policy_title",
        "Privacy Policy.": "privacy_policy_dot",
        "Privacy.": "privacy_dot",
        "Required": "required_a",
        "Send me occasional updates and tips about\nMath Connect.": "send_occasional_updates_dot_a",
        "Send me occasional updates and tips about\\nMath Connect.": "send_occasional_updates_dot_b",
        "Signing In…": "signing_ellipsis_a",
        "Signing in…": "signing_ellipsis_b",
        "Step 1 of 2": "step_1_2",
        "Step 2 of 2": "step_2_2",
        "Student": "student_b",
        "Subjects": "subjects_title",
        "Teacher": "teacher_b",
        "Terms of Service": "terms_of_service",
        "Upload a clear photo of your passport, driver's license,\nor national ID.": "upload_clear_photo_dot",
        "Use the device language": "use_the_device_language",
        "WAITING": "waiting_caps",
        "algebra": "algebra_b",
        "and": "and_b",
        "connection_setup_connecting": "connection_setup_connecting_a",
        "connection_setup_connecting_audio": "connection_setup_connecting_b",
        "required": "required_b",
        "student": "student_lower",
        "teacher": "teacher_lower",
        "video": "video_lower",
        "•": "bullet",
        "⚡ %@/min": "min_b",
		"Loading profile...": "loading_profile"
    ]

    /// Deterministic three-word snake-case slug for any source string that
    /// doesn't have an explicit override.
    private static func generatedKey(for english: String) -> String {
        var normalized = ""
        for character in english.lowercased() {
            if character.isLetter || character.isNumber {
                normalized.append(character)
            } else {
                normalized.append(" ")
            }
        }

        var words: [String] = []
        for part in normalized.split(separator: " ") {
            guard part.count > 2 else { continue }
            words.append(String(part))
            if words.count == 3 { break }
        }
        return words.joined(separator: "_")
    }
}
