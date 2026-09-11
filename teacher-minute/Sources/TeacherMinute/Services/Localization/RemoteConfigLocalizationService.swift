import Foundation

/// Production `LocalizationServiceProtocol` impl. Maps the source English
/// string to a stable snake-case key (matching the Firebase Remote Config
/// template), looks it up via `RemoteConfigService`, and falls back to the
/// source string if the active config has no entry.
/// Resolved strings, keyed by language + source string.
///
/// Every resolution costs a Remote Config lookup, which on Android is a JNI
/// round trip. A screen can ask for the same string dozens of times across
/// re-renders (ProfileView alone has ~50 call sites), so without this the cost
/// scales with render count rather than with the number of distinct strings.
/// Cleared by `RemoteConfigLocalizationService.invalidateCache()` when Remote
/// Config activates new values; a language switch needs no invalidation because
/// the language code is part of the key.
private final class LocalizationCache: @unchecked Sendable {
    static let shared = LocalizationCache()

    private let lock = NSLock()
    private var entries: [String: String] = [:]

    func value(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = value
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

struct LocalizationServiceMock: LocalizationServiceProtocol {
  func localized(_ english: String) -> String {
	return english
  }
  
  
}
struct RemoteConfigLocalizationService: LocalizationServiceProtocol {
	
  nonisolated(unsafe) static let shared:LocalizationServiceProtocol = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? LocalizationServiceMock() : RemoteConfigLocalizationService()
  private init() {
	
  }
    func localized(_ english: String) -> String {
        let languageCode = LocalizationSupport.currentLanguageCode
        let cacheKey = "\(languageCode)|\(english)"
        if let cached = LocalizationCache.shared.value(forKey: cacheKey) {
            return cached
        }

        let key = LocalizationKey.key(for: english)
        let value = RemoteConfigService.readString(key)
        let fallback = Self.localFallback(for: english, languageCode: languageCode)
        let shouldUseFallback = value.isEmpty || (languageCode != "en" && value == english)
        let resolvedValue = shouldUseFallback ? (fallback ?? english) : value
        LocalizationCache.shared.set(resolvedValue, forKey: cacheKey)
        #if os(Android)
        // Logged only on a cache miss — i.e. once per string per language —
        // so the diagnostic survives without re-logging on every render.
        logger.info("[Localization][Android] english='\(Self.debugSnippet(english))' key='\(key)' language=\(languageCode) fallback=\(shouldUseFallback) value='\(Self.debugSnippet(resolvedValue))'")
        #endif
        return resolvedValue
    }

    /// Drops cached strings so newly activated Remote Config values take effect.
    static func invalidateCache() {
        LocalizationCache.shared.removeAll()
    }

    private static func localFallback(for english: String, languageCode: String) -> String? {
        guard languageCode == "he" else { return nil }
        return hebrewFallbacks[english]
    } 

    private static let hebrewFallbacks: [String: String] = [
        // Backing out of the first onboarding step, which signs the user out.
        "Log out?": "להתנתק?",
        "Going back from here returns you to the sign-in screen and signs you out.": "חזרה מכאן תחזיר אותך למסך ההתחברות ותנתק אותך מהחשבון.",
        // Teacher dashboard and lesson history. The Remote Config template has
        // no entries for these yet, so the fallback is what actually renders.
        "Go Online": "עבור למצב מקוון",
        "Go Offline": "עבור למצב לא מקוון",
        // Starting a lesson by chat while its audio connects. Remote Config
        // carries these too; the fallback covers the time before it deploys.
        "Audio is taking longer than usual": "חיבור השמע לוקח יותר זמן מהרגיל",
        "Video is taking longer than usual": "חיבור הווידאו לוקח יותר זמן מהרגיל",
        "You can start with your teacher by chat now. We'll keep connecting in the background.": "אפשר להתחיל עם המורה בצ׳אט כבר עכשיו. נמשיך להתחבר ברקע.",
        "Start with chat": "התחל בצ׳אט",
        "Keep waiting": "המשך להמתין",
        "Audio is still connecting — you can chat meanwhile.": "השמע עדיין מתחבר — אפשר להתכתב בצ׳אט בינתיים.",
        "Audio couldn't connect. Tap to try again.": "לא הצלחנו לחבר את השמע. הקש כדי לנסות שוב.",
        "Your teacher's audio isn't connected yet — use the chat.": "השמע של המורה עדיין לא מחובר — אפשר להתכתב בצ׳אט.",
        "The student's audio isn't connected yet — use the chat.": "השמע של התלמיד עדיין לא מחובר — אפשר להתכתב בצ׳אט.",
        "ONLINE": "מחובר",
        "OFFLINE": "לא מחובר",
        "Teaching History": "היסטוריית הוראה",
        "Past": "עבר",
        "Earnings": "הכנסות",
        "Time Taught": "זמן הוראה",
        "%@%d%% vs last week": "%@%d%% מהשבוע שעבר",
        "Updating\u{2026}": "מתעדכן\u{2026}",
        "Since %@": "החל מ-%@",
        // Onboarding copy, rebranded from the old "Math Connect" placeholder.
        // The published Remote Config values still carry the old name, so these
        // stand in until the template is republished.
        "Log in to Teacher in a Minute to continue your\njourney.": "התחבר כדי להמשיך\nאת הדרך שלך.",
        "Tell us a bit about yourself to get started with\nTeacher in a Minute.": "ספר לנו קצת על עצמך כדי להתחיל עם\nTeacher in a Minute.",
		"Choose your role": "בחר תפקיד",
        "Send me occasional updates and tips about\nTeacher in a Minute.": "שלחו לי מדי פעם עדכונים וטיפים על\nTeacher in a Minute.",
        "Help you anywhere": "",
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
        // Phone validation, shown under every field that takes a number. Stands
        // in until `enter_valid_phone` is published to the template.
        "Enter a valid phone number.": "יש להזין מספר טלפון תקין.",
        "Enter your full name.": "יש להזין שם מלא.",
        // Firebase Auth errors — the SDK always returns English; these provide Hebrew fallbacks.
        "This email address is already in use.": "כתובת המייל הזו כבר רשומה במערכת.",
        "Incorrect email or password.": "כתובת המייל או הסיסמה שגויים.",
        "Too many failed attempts. Please try again later.": "יותר מדי ניסיונות כושלים. נסה שוב מאוחר יותר.",
        "A network error occurred. Please try again.": "שגיאת רשת. בדוק את החיבור ונסה שוב.",
        "An unexpected error occurred. Please try again.": "אירעה שגיאה בלתי צפויה. נסה שוב.",
        "Could not retrieve user session. Please try again.": "לא ניתן לאחזר את פרטי המשתמש. נסה שוב.",
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
        "Opening secure checkout\u{2026}": "פותח תשלום מאובטח\u{2026}",
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
        // Hero section
        "Hello, %@": "שלום, %@",
        "Teacher in a Moment": "מורה לרגע",
        "When AI gets stuck, a human teacher connects in 90 seconds": "כש-AI נתקע – מורה אנושי ב-90 שניות",
        "%d teachers available now": "%d מורים פניים עכשיו",
        "90 sec avg to connect": "ממוצע 90 שנ' להתחברות",
        "Ask a question now": "שאל שאלה עכשיו",
        // Section headers
        "%d registered teachers": "%d מורים רשומים",
        "Teachers online now": "מורים מחוברים עכשיו",
        "Credits": "קרדיטים",
        // Subject cards
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
        // Online teacher cards — preview-only names (MockStudentHomeViewModel)
        "Cohen": "כהן",
        "Levi": "לוי",
        "Mizrahi": "מזרחי",
        "Shalev": "שלו",
        // Ratings and platform figures. These replaced fixed copy ("4.9",
        // "(127 reviews)", "90 seconds") once the numbers started coming from
        // the backend, so the Remote Config template has no entries for them yet.
        "(1 review)": "(ביקורת אחת)",
        "(%d reviews)": "(%d ביקורות)",
        "No reviews yet": "אין ביקורות עדיין",
        "%d seconds": "%d שניות",
        "%d minutes": "%d דקות",
        "%d sec": "%d שנ׳",
        "%@ avg to connect": "%@ בממוצע לחיבור",
        "Average response time: %@": "זמן תגובה ממוצע: %@",
        "When AI gets stuck, a human teacher connects in %@": "כש-AI נתקע – מורה אנושי מתחבר תוך %@",
        "When AI gets stuck, a human teacher connects in moments": "כש-AI נתקע – מורה אנושי מתחבר תוך רגעים",
        "Teacher connects within %@": "מורה מתחבר תוך %@",
        "A teacher connects quickly": "מורה מתחבר במהירות",
        "%@ per minute • pay only for time used": "%@ לדקה • משלמים רק על הזמן שנוצל",
        "Only billed minutes count": "נספרות רק הדקות שחויבו",
        "1 teacher": "מורה אחד",
        // Sign-up confirm password field
        "Confirm Password": "אימות סיסמה",
        "Re-enter your password": "הזן שוב את הסיסמה",
        "Passwords do not match.": "הסיסמאות אינן תואמות.",
        "%d teachers": "%d מורים",
        // Teacher payout method on the profile screen
        "Not set up yet": "טרם הוגדר",
        "Add where your payouts should be sent": "הוסיפו לאן לשלוח את התשלומים",
        // A teacher is introduced by the subjects they actually teach
        "%@ Teacher": "מורה ל%@",
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
        "Tap to upload a photo of your question": "לחץ להעלאת תמונה של השאלה",
        "Average response time: 90 seconds": "זמן ממוצע לשידור: 90 שניות",
        "Find me a Teacher Now": "מצא לי מורה עכשיו",
        "You have %d minutes": "יש לך %d דקות",
        "~%@ value": "כ-%@ שווי",
        // Teacher dashboard — updated UI
        "Not available": "לא זמין",
        "Available": "זמין",
        "Tap to start": "לחץ כדי להתחיל",
        "Lessons": "שיעורים",
        "Monthly income": "הכנסה החודש",
        "My Rating": "הדירוג שלי",
        "1 review": "ביקורת אחת",
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
        "Left to learn": "נותרו ללימוד",
        // Payout destination, asked at profile completion
        "How would you like to get paid?": "איך תרצה לקבל תשלום?",
        "Optional — tap again to unpick. You will add the details later, under Earnings.": "לא חובה — הקש שוב כדי לבטל את הבחירה. את הפרטים תוסיף בהמשך, במסך ההכנסות.",
        "Payout Details Missing": "חסרים פרטי תשלום",
        "You will not receive money until you add your payout details.": "לא תקבל כסף עד שתוסיף את פרטי התשלום שלך.",
        "Choose where your monthly payout is sent": "בחר לאן יישלח התשלום החודשי שלך",
        // Teacher payout method
        "Payment Method": "אמצעי תשלום",
        "Choose where we should send your monthly payout.": "בחר לאן לשלוח את התשלום החודשי שלך.",
        "Add your details so we can pay you.": "הוסף את הפרטים כדי שנוכל לשלם לך.",
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
        "PayPal Email": "אימייל PayPal",
        "Enter a valid PayPal email address.": "הזן כתובת אימייל תקינה של PayPal.",
        "Could not save your PayPal email. Please try again.": "לא ניתן לשמור את אימייל PayPal. נסה שוב.",
        "Where you get paid": "לאן מועבר התשלום",
        "Your monthly payout is sent to this address, so it must be the email on your PayPal account.": "התשלום החודשי נשלח לכתובת הזו, ולכן היא חייבת להיות האימייל של חשבון PayPal שלך.",
        "Change": "שינוי",
        "Use the email address on your PayPal account.": "השתמש בכתובת המייל של חשבון הפייפאל שלך.",
        "Saving...": "שומר...",
        "Could not save your payment method. Please try again.": "לא ניתן היה לשמור את אמצעי התשלום. נסה שוב.",
        // Payout method verification
        "Bank": "בנק",
        "Connect PayPal": "התחבר לפייפאל",
        "Connect a different account": "התחבר לחשבון אחר",
        "Connecting...": "מתחבר...",
        "PayPal account confirmed": "חשבון הפייפאל אומת",
        "We never see your PayPal password.": "אנחנו לעולם לא רואים את הסיסמה שלך.",
        "Could not confirm your PayPal account. Please try again.": "לא ניתן היה לאמת את חשבון הפייפאל. נסה שוב.",
        "Connecting PayPal is not available on this device yet. Please choose another payment method.":
            "חיבור לפייפאל אינו זמין במכשיר הזה עדיין. בחר אמצעי תשלום אחר.",
        "Use my profile number (%@)": "השתמש במספר מהפרופיל (%@)",
        "Update your profile?": "לעדכן את הפרופיל?",
        "Save this number as your profile phone number too?": "לשמור את המספר הזה גם כמספר הטלפון בפרופיל?",
        "Update": "עדכן",
        "Not now": "לא עכשיו",
        // Fixing the "Stucked?" typo moved this to a new key (`stuck_you_will`),
        // which the published config does not carry yet, so Hebrew would fall
        // through to the English source until the template is republished.
        "Stuck? You will have a teacher immediately": "נתקעת? יש לך מורה לרגע.",
        // Singular counterpart of "%d teachers available now"; a lone format
        // string rendered "1 מורים פנויים עכשיו".
        "1 teacher available now": "מורה אחד פנוי עכשיו",
        // Ask a Teacher sheet — the heading stayed English above its Hebrew
        // description.
        "Attach a photo (optional)": "צירוף תמונה (לא חובה)",
        // "How it works" panel on the teacher role card. Only the first step
        // title and the last subtitle had Hebrew, so the panel rendered half in
        // English.
        "Add your subjects, bio, and verification documents": "הוסיפו מקצועות, תיאור קצר ומסמכי אימות",
        "A student requests help": "תלמיד מבקש עזרה",
        "Get matched to students who need your subject": "מתחברים לתלמידים שצריכים את המקצוע שלכם",
        "Teach live": "מלמדים בשידור חי",
        // Rate-the-session screen. Both strings stayed English under the Hebrew
        // stars, so the whole comment block read as untranslated.
        "Add a comment (optional)": "הוספת הערה (לא חובה)",
        "Your teacher sees this without your name.": "המורה רואה את ההערה בלי השם שלך.",
        // Teacher preference: availability when the app opens.
        "Availability on launch": "זמינות בפתיחת האפליקציה",
        "Availability on launch and currency": "זמינות בפתיחה ומטבע",
        "Online": "זמין",
        "Offline": "לא זמין",
        "Last state": "המצב האחרון",
        "Choose whether you start out available for questions when the app opens. \"Last state\" reuses the availability you left the app on.":
            "בחרו אם להתחיל כזמינים לשאלות כשהאפליקציה נפתחת. \"המצב האחרון\" משחזר את הזמינות שבה סגרתם את האפליקציה.",
        // Teacher dashboard warning header — the teacher is unreachable.
        "Notifications are off. You can take questions while the app is open, and you go offline when you leave it.":
            "ההתראות כבויות. אפשר לקבל שאלות כל עוד האפליקציה פתוחה, וברגע שתצאו ממנה תעברו למצב לא זמין.",
        "No connection to the server. New questions will not reach you until it is back.":
            "אין חיבור לשרת. שאלות חדשות לא יגיעו אליכם עד שהחיבור יחזור.",
        // Ask a Teacher sheet: the keyboard switch above the question field.
        // "Regular" and "Algebra" are already published; only these are new.
        "Keyboard": "מקלדת",
        "Build the formula, then add it to your question.": "בנו את הנוסחה ואז הוסיפו אותה לשאלה."
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
        // Rating and connect-time strings whose generated keys would collide
        // with existing ones ("%d reviews" → reviews, "minutes", "seconds").
        "(1 review)": "review_1",
        "(%d reviews)": "fmt_reviews_parens",
        "%d seconds": "fmt_seconds",
        "%d minutes": "fmt_minutes",
        "%d sec": "fmt_sec",
        "When AI gets stuck, a human teacher connects in %@": "fmt_ai_stuck_connects",
        "When AI gets stuck, a human teacher connects in moments": "ai_stuck_connects_moments",
        "%@ Teacher": "fmt_subject_teacher",
        "1 teacher": "teacher_1",
        // "Re-enter your password" would generate `enter_your_password`, which
        // the published template already uses for "Enter your password".
        "Re-enter your password": "re_enter_your_password",
        "%d teachers": "fmt_teachers",
        // The published `teacher_connects_within` still holds the old fixed
        // "Teacher connects within 90 sec"; the format string needs its own key
        // so that value cannot shadow it.
        "Teacher connects within %@": "fmt_teacher_connects_within",
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
        "Camera disabled": "camera_disabled_photo",
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
        // Same collision for the bare availability-on-launch options, which
        // reduce to `online` / `offline` just as "Go Online" / "Go Offline" do.
        "Online": "online_option",
        "Offline": "offline_option",
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
        // Generated as `camera_unavailable_this`, which says nothing about what
        // the string is for.
        "Camera unavailable \u{2014} this lesson is audio only.": "camera_unavailable_audio_only",
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
        // Every word in "OK" is two letters, and `generatedKey` drops words of
        // two characters or fewer — so without this override the key comes out
        // empty and the dialog button stays English in Hebrew.
        "OK": "ok",
        "ON": "on_caps",
        "Open Settings": "open_settings",
        "ORIGINAL QUESTION": "original_question_caps",
        "On": "on",
        "PAYMENTS": "payments_caps",
        // "Preferences" and "PREFERENCES" both reduce to `preferences`, so the
        // caps section header's value was serving the sentence-case row too and
        // the row rendered as "PREFERENCES".
        "PREFERENCES": "preferences_caps",
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
		"Set date of birth": "set_date_of_birth",

        // MARK: Keys Remote Config would reject
        //
        // `generatedKey` drops words of two characters or fewer, so these three
        // reduce to a key that is empty ("%@ %d") or starts with a digit — and
        // Firebase only accepts /[A-Za-z_][A-Za-z0-9_]*/. Neither form could
        // ever resolve, so all three stayed English in Hebrew.
        "%@ %d": "fmt_month_year",
        "e.g. 123": "eg_branch_number",
        "e.g. 45678901": "eg_account_number",

        // MARK: Collision fixes
        //
        // Every entry below exists because two distinct source strings reduced
        // to the same generated key, so one published value was serving both.
        // The string that matches the value already in the template keeps the
        // original key; the other one is moved here.

        // `all` holds the "All" subject filter.
        "all": "all_lower",
        // `choose_your_role` holds the title-case navigation title.
        "Choose your role": "choose_your_role_subtitle",
        // Three different save failures all reduced to `could_not_save`.
        "Could not save your PayPal account. Please try again.": "could_not_save_paypal_account",
        "Could not save your PayPal email. Please try again.": "could_not_save_paypal_email",
        "Could not save your payment method. Please try again.": "could_not_save_payment_method",
        // `default_session_type` holds the settings row title.
        "Default session type and currency": "default_session_type_and_currency",
        // `enter_your_password` holds the login field's placeholder.
        "Enter your password to confirm account deletion.": "enter_password_confirm_deletion",
        // `ils` is the currency *symbol* (\u{20AA}); the settings row shows the code.
        "ILS": "currency_value_ils",
        // `log_out` holds the button label, not the confirmation question.
        "Log out?": "log_out_qmark",
        // `make_sure_your` holds the microphone sentence.
        "Make sure your camera is enabled so your teacher can see your work.": "make_sure_camera_enabled",
        // `min` would serve both the rate format and the bare unit label.
        "%@/min": "fmt_min_rate",
        "min": "min_short",
        // `selected` holds the "%d selected" counter.
        "selected": "selected_lower",
        // `teacher_available_now` holds the "1 teacher available now" line.
        "Teacher available now": "teacher_available_now_badge",
        // `unexpected_error_occurred` holds the shorter sentence.
        "An unexpected error occurred. Please try again.": "unexpected_error_try_again",
        // `upload_clear_photo` holds the math-problem prompt.
        "Upload a clear photo of your passport, driver's license,\nor national ID. A valid government ID is required to\nbecome a verified teacher.": "upload_clear_photo_gov_id"
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
