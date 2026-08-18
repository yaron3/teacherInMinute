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
        // Teacher dashboard and lesson history. The Remote Config template has
        // no entries for these yet, so the fallback is what actually renders.
        "Go Online": "עבור למצב מקוון",
        "Go Offline": "עבור למצב לא מקוון",
        "ONLINE": "מחובר",
        "OFFLINE": "לא מחובר",
        "Teaching History": "היסטוריית הוראה",
        "Past": "קודמים",
        "Earnings": "רווחים",
        "Time Taught": "זמן הוראה",
        "%@%d%% vs last week": "%@%d%% מהשבוע שעבר",
        // Onboarding copy, rebranded from the old "Math Connect" placeholder.
        // The published Remote Config values still carry the old name, so these
        // stand in until the template is republished.
        "Log in to Teacher in a Minute to continue your\njourney.": "התחבר כדי להמשיך\nאת הדרך שלך.",
        "Tell us a bit about yourself to get started with\nTeacher in a Minute.": "ספר לנו קצת על עצמך כדי להתחיל עם\nTeacher in a Minute.",
        "How do you want to use Teacher in a Minute? You\ncan change this later in settings.": "איך תרצה להשתמש ב־Teacher in a Minute? תוכל\nלשנות זאת מאוחר יותר בהגדרות.",
        "Send me occasional updates and tips about\nTeacher in a Minute.": "שלחו לי מדי פעם עדכונים וטיפים על\nTeacher in a Minute.",
        "Help you anywhere": "עזרה מכל מקום",
        // Title of the photo-source dialog; its buttons already had Hebrew, so
        // only the heading was showing through in English.
        "Add a photo": "הוספת תמונה",
        // Grade ordinals, mirroring the `grade_1`...`grade_12` Remote Config
        // entries so the chips read correctly even before the template is
        // published to the console.
        "Grade 1": "כיתה א׳",
        "Grade 2": "כיתה ב׳",
        "Grade 3": "כיתה ג׳",
        "Grade 4": "כיתה ד׳",
        "Grade 5": "כיתה ה׳",
        "Grade 6": "כיתה ו׳",
        "Grade 7": "כיתה ז׳",
        "Grade 8": "כיתה ח׳",
        "Grade 9": "כיתה ט׳",
        "Grade 10": "כיתה י׳",
        "Grade 11": "כיתה י״א",
        "Grade 12": "כיתה י״ב",
        "I agree to the [Terms of Service](teacherminute://terms) and [Privacy Policy.](teacherminute://privacy)": "אני מסכים/ה ל[תנאי השירות](teacherminute://terms) ול[מדיניות הפרטיות.](teacherminute://privacy)",
        "Terms of Service": "תנאי השירות",
        "Save board to gallery?": "לשמור את הלוח לגלריה?",
        "The session ended. Do you want to save the board image to your device gallery?": "השיעור הסתיים. האם ברצונך לשמור את תמונת הלוח לגלריית המכשיר?",
        "The board will be saved to the chat. Do you also want to save it to your device gallery?": "הלוח יישמר בצ׳אט. האם ברצונך לשמור אותו גם לגלריית המכשיר?",
        "Save to gallery": "שמירה לגלריה",
        "Save to chat only": "שמירה לצ׳אט בלבד",
        "Don't save": "לא לשמור",
        "Setting up the session": "מתחבר לשיעור",
        "Waiting now": "ממתין עכשיו",
        "Choose a payment method": "בחר אמצעי תשלום",
        // Prefix for the branded PayPal button, where the logo follows the text.
        "Pay with": "תשלום באמצעות",
        // Confirmation shown after a successful purchase.
        "Purchase complete": "הרכישה הושלמה",
        "%@ purchased for %@.": "נרכש %@ בעלות %@.",
        "Added %@ to your balance.": "נוספו %@ ליתרה שלך.",
        "Pay with PayPal": "תשלום באמצעות PayPal",
        "Pay with Apple Pay": "תשלום באמצעות Apple Pay",
        "Pay with Google Pay": "תשלום באמצעות Google Pay",
        "Pay with Bit": "תשלום באמצעות ביט",
        "Pay with credit card": "תשלום בכרטיס אשראי",
        "PayPal, Bit, or credit card": "PayPal, ביט או כרטיס אשראי",
        // Settings, chat status, notification and payment-history copy that had
        // no template entry. Translated alongside the Remote Config additions.
        "%@/min": "%@ לדקה",
        "Attach a photo (optional)": "צירוף תמונה (רשות)",
        "Debug builds only": "גרסאות פיתוח בלבד",
        "Enabling...": "מפעיל...",
        "Image": "תמונה",
        "Images": "תמונות",
        "Loading...": "טוען...",
        "No payments yet": "אין עדיין תשלומים",
        "No subjects selected": "לא נבחרו מקצועות",
        "Not now": "לא עכשיו",
        "Payment History": "היסטוריית תשלומים",
        "Please sign out and sign in again before deleting your account.": "התנתקו והתחברו מחדש לפני מחיקת החשבון.",
        "Stay in the loop": "הישארו מעודכנים",
        "Student is reading chat — video paused": "התלמיד קורא את הצ׳אט — הווידאו מושהה",
        "Switching to text chat…": "עובר לצ׳אט טקסט…",
        "Teacher is reading chat — video paused": "המורה קורא את הצ׳אט — הווידאו מושהה",
        "Test Crashlytics Crash": "בדיקת קריסה ב־Crashlytics",
        "This session type is preselected when you ask a teacher a question. You can still change it for each question.": "סוג שיעור זה נבחר מראש כששואלים מורה שאלה. עדיין אפשר לשנות אותו בכל שאלה.",
        "Turn on notifications so we can let you know the moment a teacher accepts your request, replies to a message, or your session is about to start.": "הפעילו התראות כדי שנוכל לעדכן אתכם ברגע שמורה מקבל את הבקשה, משיב להודעה, או כשהשיעור עומד להתחיל.",
        "View your lesson payment history": "צפייה בהיסטוריית תשלומי השיעורים",
        "When turned off, your profile photo won't be shared with the other participant during a session.": "כאשר האפשרות כבויה, תמונת הפרופיל שלכם לא תשותף עם המשתתף השני במהלך השיעור.",
        "You don't have any recent activity": "אין לכם פעילות אחרונה",
        "You need to be signed in to attach a photo.": "יש להתחבר כדי לצרף תמונה.",
        "Your currency is set to Israeli Shekel (ILS) and cannot be changed for now.": "המטבע שלכם מוגדר לשקל חדש (₪) ולא ניתן לשנותו כרגע.",
        "Your lesson payments will appear here.": "תשלומי השיעורים שלכם יופיעו כאן.",
        "Default Session Type": "סוג שיעור ברירת מחדל",
        "Default session type and currency": "סוג שיעור ומטבע ברירת מחדל",
        "Enter your password to confirm account deletion.": "הזינו את הסיסמה שלכם כדי לאשר את מחיקת החשבון.",
        // Demo tooling (simulate a student question) and the teacher
        // verification prompts. Not in the published Remote Config template
        // yet, so these fallbacks are what actually render in Hebrew.
        "Demo Mode": "מצב הדגמה",
        "Send yourself a question from a simulated student.": "שלחו לעצמכם שאלה מתלמיד מדומה.",
        "Simulate a Student Question": "הדמיית שאלת תלמיד",
        "A demo student writes the question with a local AI model and sends it to you, so you can practise the whole flow without a real student.": "תלמיד הדגמה מנסח את השאלה בעזרת מודל AI מקומי ושולח אותה אליכם, כדי שתוכלו להתאמן על התהליך המלא בלי תלמיד אמיתי.",
        "Difficulty": "רמת קושי",
        "What should it be about? (optional)": "במה תעסוק השאלה? (רשות)",
        "e.g. solving quadratic equations": "לדוגמה: פתרון משוואות ריבועיות",
        "Send Simulated Question": "שליחת שאלה מדומה",
        "The question takes a few seconds to write. You will get it on your dashboard like any other request.": "כתיבת השאלה אורכת כמה שניות. היא תגיע ללוח הבקרה שלכם כמו כל בקשה אחרת.",
        "Writing a question with the local AI model...": "כותב שאלה בעזרת מודל ה־AI המקומי...",
        "Question sent — it should appear in your queue now.": "השאלה נשלחה — היא אמורה להופיע בתור שלכם עכשיו.",
        "Question sent — the local AI model was unreachable, so a sample question was used.": "השאלה נשלחה — מודל ה־AI המקומי לא היה זמין, ולכן נעשה שימוש בשאלה לדוגמה.",
        "The local AI is offline — sent a standard demo question instead.": "ה־AI המקומי אינו פעיל — נשלחה במקומו שאלת הדגמה סטנדרטית.",
        "The demo question feature is currently turned off.": "תכונת שאלת ההדגמה כבויה כרגע.",
        "Sign in as a teacher to simulate a question.": "התחברו כמורה כדי להדמות שאלה.",
        "The demo student service did not respond. Make sure it is running on your machine.": "שירות תלמיד ההדגמה לא הגיב. ודאו שהוא פועל במחשב שלכם.",
        "The demo student service could not create the question.": "שירות תלמיד ההדגמה לא הצליח ליצור את השאלה.",
        "Camera access is required to take a photo.": "נדרשת גישה למצלמה כדי לצלם תמונה.",
        "Complete now": "להשלים עכשיו",
        "Complete your verification": "השלימו את האימות שלכם",
        "Continue - upload later": "המשך - העלאה מאוחר יותר",
        "Maybe later": "אולי מאוחר יותר",
        "Nice work on your first lesson! Uploading the rest of your verification documents helps us confirm you as a teacher faster. It's optional — you can also do it anytime from your Profile.": "כל הכבוד על השיעור הראשון! העלאת שאר מסמכי האימות עוזרת לנו לאשר אתכם כמורים מהר יותר. ההעלאה אינה חובה — תוכלו לבצע אותה בכל עת מהפרופיל שלכם.",
        "Upload your remaining verification documents": "העלו את מסמכי האימות שנותרו",
        "Upload a clear photo of your passport, driver's license,\nor national ID. A valid government ID is required to\nbecome a verified teacher.": "העלו תמונה ברורה של דרכון, רישיון נהיגה\nאו תעודת זהות. נדרשת תעודה מזהה ממשלתית תקפה\nכדי להפוך למורה מאומת.",
        "You can pay with PayPal, Bit, or a credit card. Choose your preferred method at checkout. There is no need to save a payment method in the app; your credentials are requested during each purchase.": "ניתן לשלם באמצעות PayPal, ביט או כרטיס אשראי. בחרו את אמצעי התשלום המועדף עליכם בעת התשלום. אין צורך לשמור אמצעי תשלום באפליקציה; פרטי התשלום מתבקשים בכל רכישה."
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
        // Shared `enter_your_password` with the login field, so the delete-account
        // confirmation was showing the login prompt's translation.
        "Enter your password to confirm account deletion.": "enter_password_delete_account",
        // Shared `default_session_type` with the settings section title.
        "Default session type and currency": "default_session_type_currency",
        // Both demo-service errors generate `the_demo_student`, which would make
        // one translation serve two different failures.
        "The demo student service did not respond. Make sure it is running on your machine.": "demo_service_no_response",
        "The demo student service could not create the question.": "demo_service_create_failed",
        "Could not send your message.": "could_not_send_dot_b",
        "Could not start the audio/video connection. Please try again.": "could_not_start_audio_video",
        "Enter your email address first.": "enter_your_email_dot_a",
        "Enter your email or phone number and we'll\nsend you instructions to reset your password.": "enter_your_email_dot_b",
        "End session?": "end_session_qmark",
        // "Go Online" and the "ONLINE" status pill both reduce to `online`,
        // which would make one translation serve two unrelated strings.
        "Go Online": "go_online",
        "Go Offline": "go_offline",
        "ONLINE": "online_caps",
        "OFFLINE": "offline_caps",
        "%@%d%% vs last week": "fmt_vs_last_week",
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
        // Rebranded onboarding copy. These deliberately use new keys: the old
        // ones still resolve to published values carrying the "Math Connect"
        // name, and a non-empty config value always wins over the source
        // string, so reusing them would keep serving the old brand.
        "Send me occasional updates and tips about\nTeacher in a Minute.": "send_occasional_updates_tim_a",
        "Send me occasional updates and tips about\\nTeacher in a Minute.": "send_occasional_updates_tim_b",
        "Tell us a bit about yourself to get started with\nTeacher in a Minute.": "tell_bit_about_tim",
        "How do you want to use Teacher in a Minute? You\ncan change this later in settings.": "how_you_want_tim",
        "Signing In…": "signing_ellipsis_a",
        "Signing in…": "signing_ellipsis_b",
        "Step 1 of 2": "step_1_2",
        "Step 2 of 2": "step_2_2",
        "Student": "student_b",
        "Subjects": "subjects_title",
        "Teacher": "teacher_b",
        "Terms of Service": "terms_of_service",
        "Upload a clear photo of your passport, driver's license,\nor national ID.": "upload_clear_photo_dot",
        // The longer variant generated `upload_clear_photo` — the same key as
        // the student's "photo of your math problem" tip, so the ID screen was
        // showing the math-problem translation in Hebrew.
        "Upload a clear photo of your passport, driver's license,\nor national ID. A valid government ID is required to\nbecome a verified teacher.": "upload_clear_photo_id",
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
		"Loading profile...": "loading_profile",
		"%d completed": "completed_count",
		"Documents Uploaded": "documents_uploaded",
		"View the verification documents you uploaded": "view_uploaded_documents",
		"These are the verification documents you uploaded.": "uploaded_documents_intro",
		"Loading documents...": "loading_documents",
		"No documents uploaded yet.": "no_documents_uploaded",
		"Could not load this document.": "could_not_load_document",
		"Could not load documents.": "could_not_load_documents",
		"Close": "close",
		"Add missing documents": "add_missing_documents",
		"Uploading the remaining documents helps us verify you as a teacher faster.": "upload_remaining_documents_hint",
		"Not uploaded yet": "not_uploaded_yet",
		"Upload": "upload_action",
		"Set date of birth": "set_date_of_birth"
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
