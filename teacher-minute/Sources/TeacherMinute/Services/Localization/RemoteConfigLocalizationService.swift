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
        "Earnings": "הכנסות",
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
        "Camera disabled": "המצלמה כבויה",
        "Camera access is disabled. Open Settings and enable camera access to take a photo.": "הגישה למצלמה כבויה. פתחו את ההגדרות ואפשרו גישה למצלמה כדי לצלם תמונה.",
        "Open Settings": "פתיחת הגדרות",
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
        "You can pay with PayPal, Bit, or a credit card. Choose your preferred method at checkout. There is no need to save a payment method in the app; your credentials are requested during each purchase.": "ניתן לשלם באמצעות PayPal, ביט או כרטיס אשראי. בחרו את אמצעי התשלום המועדף עליכם בעת התשלום. אין צורך לשמור אמצעי תשלום באפליקציה; פרטי התשלום מתבקשים בכל רכישה.",
        // Student home screen — new UI structure
        "Available Subjects": "מקצועות זמינים",
        "Meet": "פגוש",
        "Ask a question": "שאל שאלה",
        "Describe the problem – text, image, or whiteboard drawing": "תאר את הבעיה – טקסט, תמונה, או ציור בלוח",
        "Teacher connects within 90 sec": "מורה מחובר תוך 90 שני׳",
        "The system finds an available teacher for your subject": "המערכת מוצאת מורה פנוי ומתאים למקצוע",
        "Chat, whiteboard, voice messages – real time": "צ׳אט, לוח לבן, הודעות קוליות – בזמן אמת",
        "2 NIS connection • only billed minutes count": "2₪ לחיבור • דקות נספרות בשרת בלבד",
        // Hero section
        "Hello, %@": "שלום, %@",
        "Teacher in a Moment": "מורה ברגע",
        "When AI gets stuck, a human teacher connects in 90 seconds": "כש-AI נתקע – מורה אנושי ב-90 שניות",
        "%d teachers available now": "%d מורים פניים עכשיו",
        "90 sec avg to connect": "ממוצע 90 שנ' להתחברות",
        "Ask a question now": "שאל שאלה עכשיו",
        "2 NIS connection fee • pay only for time used": "2₪ לחיבור • משלמים רק על זמן שהשתמשת",
        // Section headers
        "%d registered teachers": "%d מורים רשומים",
        "Teachers online now": "מורים מחוברים עכשיו",
        "Credits": "קרדיטים",
        // Subject cards
        "%d teachers": "%d מורים",
        "Chemistry": "כימיה",
        "Biology": "ביולוגיה",
        "Algebra, trigonometry, 5 units": "אלגברה, טריגונומטריה, 5 יח'",
        "Mechanics, electricity, optics": "מכניקה, חשמל, אופטיקה",
        "Organic, physical, matriculation": "אורגנית, פיזיקלית, בגרות",
        "Probability, regression, SPSS": "הסתברות, רגרסיה, SPSS",
        "Python, algorithms, data structures": "Python, אלגוריתמים, מבני נתונים",
        "Genetics, cells, molecular": "גנטיקה, תאים, מולקולרית",
        "Teacher available now": "מורה פנוי עכשיו",
        "No one available now": "אין פנויים עכשיו",
        // Online teacher cards (mock names)
        "Cohen": "כהן",
        "Levi": "לוי",
        "Mizrahi": "מזרחי",
        "Shalev": "שלו",
        // How it works panel
        "How it works": "איך זה עובד",
        "Live lesson": "שיעור חי",
        "Pay only for what you used": "משלמים רק על מה שהשתמשת",
        // Dashboard cards
        "Last Lesson": "שיעור אחרון",
        "None yet": "טרם היה",
        "Ask a teacher to start": "שאל מורה כדי להתחיל",
        "Your Balance": "יתרה שלך",
        "Buy More +": "רכוש עוד +",
        // Ask teacher sheet — updated UI
        "Mathematical symbols – tap to add:": "סמלים מתמטיים – לחץ להוספה:",
        "Tap to upload a photo of your question": "לחץ להעלאת תמונה של השאלה",
        "Average response time: 90 seconds": "זמן ממוצע לשידור: 90 שניות",
        "Find me a Teacher Now": "מצא לי מורה עכשיו",
        "You have %d minutes": "יש לך %d דקות",
        "~%@ value": "כ-%@ שווי",
        // Teacher dashboard — updated UI
        "Not available": "לא זמינה",
        "Available": "זמינה",
        "Tap to start": "לחצי כדי להתחיל",
        "Lessons": "שיעורים",
        "Monthly income": "הכנסה החודש",
        "My Rating": "הדירוג שלי",
        "%d reviews": "%d ביקורות",
        // Teacher earnings tab
        "Income and Payments": "הכנסות ותשלומים",
        "Teacher Profile": "פרופיל מורה",
        "Monthly Summary": "סיכום חודשי",
        "Current Month": "חודש שוטף",
        "Total Income": "סה\"כ הכנסות",
        "%d months": "%d חודשים",
        "Next Payment": "תשלום הבא",
        "In progress": "בתהליך",
        "Weekly Breakdown": "פירוט שבועי",
        "Week %d (%d-%d)": "שבוע %d (%d-%d)",
        "Teacher profile coming soon": "פרופיל מורה בקרוב",
        "Username": "שם משתמש",
        // Saved PayPal (student profile)
        "Saved PayPal": "פייפאל שמור",
        "+ Add": "+ הוסף",
        "PayPal": "פייפאל",
        "Remove": "הסר",
        "No saved PayPal account. Tap \"+ Add\" to save one.": "אין חשבון פייפאל שמור. לחץ \"+ הוסף\" לשמירה חד פעמית.",
        "Quick Payment": "תשלום מהיר",
        "After saving your PayPal account, every future purchase is one tap away — no need to log in again.": "אחרי שמירת חשבון הפייפאל, כל רכישה עתידית תהיה בלחיצה אחת – ללא צורך להתחבר שוב.",
        "Could not save your PayPal account. Please try again.": "לא ניתן היה לשמור את חשבון הפייפאל. נסה שוב.",
        "Could not remove your saved PayPal account. Please try again.": "לא ניתן היה להסיר את חשבון הפייפאל השמור. נסה שוב.",
        // Teacher earnings
        "%@ %d": "%@ %d",
        "%@ (current)": "%@ (שוטף)",
        "Bit": "ביט",
        "No earnings yet. Your first lesson will show up here.": "אין עדיין הכנסות. השיעור הראשון שלך יופיע כאן.",
        "Could not load earnings.": "לא ניתן היה לטעון את ההכנסות.",
        // Teacher payout method
        "Payment Method": "אמצעי תשלום",
        "Choose where we should send your monthly payout.": "בחר לאן לשלוח את התשלום החודשי שלך.",
        "No payment method yet. Add one so we can pay you.": "עדיין אין אמצעי תשלום. הוסף אחד כדי שנוכל לשלם לך.",
        "Bank Account": "חשבון בנק",
        "Bank Name": "שם הבנק",
        "e.g. Bank Hapoalim": "לדוגמה: בנק הפועלים",
        "Branch Number": "מספר סניף",
        "e.g. 123": "לדוגמה: 123",
        "Account Number": "מספר חשבון",
        "e.g. 45678901": "לדוגמה: 45678901",
        "Account Holder Name": "שם בעל החשבון",
        "Full name as it appears at the bank": "שם מלא כפי שמופיע בבנק",
        "Bit Phone Number": "מספר טלפון בביט",
        "Use the phone number registered with your Bit account.": "השתמש במספר הטלפון הרשום בחשבון הביט שלך.",
        "name@example.com": "name@example.com",
        "Use the email address on your PayPal account.": "השתמש בכתובת המייל של חשבון הפייפאל שלך.",
        "Saving...": "שומר...",
        "Could not save your payment method. Please try again.": "לא ניתן היה לשמור את אמצעי התשלום. נסה שוב.",
        // Payout method verification
        "Bank": "בנק",
        "Connect PayPal": "התחבר לפייפאל",
        "Connect a different account": "התחבר לחשבון אחר",
        "Connecting...": "מתחבר...",
        "PayPal account confirmed": "חשבון הפייפאל אומת",
        "You will sign in to PayPal so we can confirm the account is yours. We never see your PayPal password.":
            "תתחבר לפייפאל כדי שנוכל לוודא שהחשבון שלך. אנחנו לעולם לא רואים את הסיסמה שלך.",
        "Could not confirm your PayPal account. Please try again.": "לא ניתן היה לאמת את חשבון הפייפאל. נסה שוב.",
        "Connecting PayPal is not available on this device yet. Please choose another payment method.":
            "חיבור לפייפאל אינו זמין במכשיר הזה עדיין. בחר אמצעי תשלום אחר.",
        "Use my profile number (%@)": "השתמש במספר מהפרופיל (%@)",
        "Update your profile?": "לעדכן את הפרופיל?",
        "Save this number as your profile phone number too?": "לשמור את המספר הזה גם כמספר הטלפון בפרופיל?",
        "Update": "עדכן",
        "Not now": "לא עכשיו"
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
        "Camera disabled": "camera_disabled",
        "Camera access is disabled. Open Settings and enable camera access to take a photo.": "camera_access_disabled_settings_photo",
        "Could not send rating. Please try again next time.": "could_not_send_dot_a",
        "Could not send your message.": "could_not_send_dot_b",
        "Could not start the audio/video connection. Please try again.": "could_not_start_audio_video",
        "Enter your email address first.": "enter_your_email_dot_a",
        "Enter your email or phone number and we'll\nsend you instructions to reset your password.": "enter_your_email_dot_b",
        "End session?": "end_session_qmark",
        // "Go Online" and the "ONLINE" status pill both reduce to `online`,
        // which would make one translation serve two unrelated strings.
//        "Go Online": "go_online",
//        "Go Offline": "go_offline",
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
//        "OK": "ok",
        "ON": "on_caps",
        "Open Settings": "open_settings",
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
//        "Terms of Service": "terms_of_service",
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
		"Loading profile...": "loading_profile",
		"%d completed": "completed_count",
//		"Documents Uploaded": "documents_uploaded",
		"View the verification documents you uploaded": "view_uploaded_documents",
		"These are the verification documents you uploaded.": "uploaded_documents_intro",
		"Loading documents...": "loading_documents",
		"No documents uploaded yet.": "no_documents_uploaded",
		"Could not load this document.": "could_not_load_document",
		"Could not load documents.": "could_not_load_documents",
//		"Close": "close",
//		"Add missing documents": "add_missing_documents",
		"Uploading the remaining documents helps us verify you as a teacher faster.": "upload_remaining_documents_hint",
//		"Not uploaded yet": "not_uploaded_yet",
		"Upload": "upload_action",
		"Set date of birth": "set_date_of_birth"
    ]

    /// Deterministic three-word snake-case slug for any source string that
    /// doesn't have an explicit override.
    private static func generatedKey(for english: String) -> String {
        var normalized = ""
		let text = english.lowercased()
	  if text.first?.isNumber == true {
		normalized = "_"
	  }
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
