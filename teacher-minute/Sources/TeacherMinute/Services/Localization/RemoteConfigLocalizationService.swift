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
        // Shown when the ask button is tapped before the balance has loaded.
        // Remote Config carries these too; the fallback covers the time
        // before it deploys.
        "Checking your balance": "בודקים את היתרה שלך",
        "Your minutes are still loading. This takes a moment the first time you open the app.":
          "הדקות שלך עדיין נטענות. זה לוקח רגע בפעם הראשונה שפותחים את האפליקציה.",
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
        // Signing in to the app built for the other role. Remote Config
        // carries these too; the fallback covers the time before it deploys.
        "This is a teacher account. Please sign in to %@, our app for teachers.": "זהו חשבון מורה. יש להתחבר אליו דרך %@, האפליקציה שלנו למורים.",
        "Students have a new app": "לתלמידים יש אפליקציה חדשה",
        "Pro Teacher is now our app for teachers only. To keep learning, download Instant Teacher, our new app for students, and sign in there with the same account.":
          "מעכשיו Pro Teacher היא האפליקציה שלנו למורים בלבד. כדי להמשיך ללמוד, הורידו את Instant Teacher, האפליקציה החדשה שלנו לתלמידים, והתחברו אליה עם אותו החשבון.",
        "Download Instant Teacher": "להורדת Instant Teacher",
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
        // Launch splash. It is on screen while Remote Config makes its first
        // fetch, so on a fresh install these are what actually render.
        "Stuck?": "נתקעת?",
        "A human teacher": "מורה אנושי",
        "within 90 seconds": "תוך 90 שניות",
        // The intro a signed-out student meets first. Remote Config carries
        // these too; the fallback covers the time before it deploys.
        "When AI can't explain it, we have a human teacher who sees exactly where you got stuck":
          "כש-AI לא מצליח להסביר, יש לנו מורה אנושי שרואה בדיוק איפה נתקעת",
        "Get started": "מתחילים",
        "₪2 per minute • no fixed lessons": "₪2 לדקה • בלי שיעורים קבועים",
        "Photo": "תמונה",
        "Attach photo": "צרף תמונה",
        "Snap your\nquestion": "צלם את\nהשאלה שלך",
        "Write your\nquestion": "תוכל להוסיף\nשאלה\nבכתב",
        "teacher\nonline": "מורה\nזמין",
        "teachers\nonline": "מורים\nזמינים",
        "₪2\nper minute": "₪2 לדקה",
        "Choose keyboard": "בחר מקלדת",
        "Delete photo": "מחק תמונה",
        "Load minutes": "טען דקות",
        "Add your question": "הוסף את השאלה שלך",
        "Take a photo of it, or write at least 10 characters.": "צלם אותה, או כתוב לפחות 10 תווים.",
        "Photo not attached": "התמונה לא צורפה",
        "General question": "שאלה כללית",
        "Text": "טקסט",
        "Find a Teacher": "מצא מורה",
        "Not enough minutes": "אין מספיק דקות",
        "Create an account to send your question to a teacher, and get %d free minutes.": "כדי לשלוח את השאלה למורה הרשם לאפליקציה ותקבל %d דקות בחינם",
        "Sign up to send your question to a teacher.": "כדי לשלוח את השאלה למורה הרשם לאפליקציה",
        "Load more minutes to send your question to a teacher.": "כדי לשלוח את השאלה למורה צריך לטעון דקות נוספות.",
        "Current balance": "היתרה הנוכחית",
        "Create a user account": "ליצירת חשבון משתמש",
        "Buy minutes": "לקניית דקות",
        "1 minute": "דקה אחת",
        "Registration": "הרשמה",
        "Registration: Create an account": "הרשמה : יצירת חשבון",
        "Manage payments, preferences, notifications and device settings.": "ניהול תשלומים, העדפות, התראות והגדרות מכשיר.",
        "Back": "חזרה",
        "Continue to get minutes": "המשך לקבלת דקות",
        "Purchase minutes": "רכישת דקות",
        "Choose the package that fits your next question": "בחרו את החבילה שמתאימה לשאלה הבאה",
        "Balance: %d minutes": "יתרה: %d דקות",
        "Balance: 1 minute": "יתרה: דקה אחת",
        "Best value": "הכי משתלם",
        "Credit card": "כרטיס אשראי",
        "Purchase summary": "סיכום הרכישה",
        "Minutes package": "חבילת דקות",
        "Total to pay": "סה״כ לתשלום",
        "Pay %@": "תשלום %@",
        "Your payment is secure and encrypted": "התשלום מאובטח ומוצפן",
        "Minutes added successfully": "הדקות נוספו בהצלחה",
        "You can go back to your question and pick up exactly where you left off.": "אפשר לחזור לשאלה ולהמשיך בדיוק מהמקום שבו עצרת.",
        "Top-up details": "פרטי הטעינה",
        "Payment completed": "הושלם",
        "Updated balance": "יתרה מעודכנת",
        "Minutes purchased": "דקות שנרכשו",
        "All set for the next question": "הכול מוכן לשאלה הבאה",
        "Back to the question": "חזרה לשאלה",
        "Paying by %@": "תשלום ב־%@",
        "Choose a package": "בחרו חבילה",
        "minutes": "דקות",
        // Instant Teacher's menu.
        "Menu": "תפריט",
        "Ask": "לשאול",
        "Minutes": "דקות",
        "Activity": "פעילות",
        // The rest of the menu. Remote Config has these in Hebrew, but its
        // Hebrew values follow the phone's language, so a phone set to
        // another language with the app in Hebrew would show them in English.
        "Profile": "פרופיל",
        "Settings": "הגדרות",
        "Help & Support": "עזרה ותמיכה",
        "Email": "אימייל",
        "Phone": "טלפון",
        "Already have an account?": "כבר יש לך חשבון?",
        "Log In": "התחבר",
        // Instant Teacher's activity, profile and settings screens.
        "Recent sessions": "מפגשים אחרונים",
        "All your recent sessions, with learning time, teacher and quick access to continue learning.": "כל המפגשים האחרונים שלך, עם זמן למידה, מורה וגישה מהירה להמשך הלימוד.",
        "Completed": "הושלמו",
        "Teachers": "מורים",
        "Your account details, contact details and device settings.": "פרטי החשבון, פרטי התקשרות והגדרות מכשיר שלך.",
        "Settings: Preferences": "הגדרות : העדפות",
        "Settings: Notifications": "הגדרות : התראות",
        "Manage push notifications, system notifications and more settings.": "ניהול התראות פוש, התראות מערכת והגדרות נוספות.",
        // The rest of those screens' copy. Remote Config has it in Hebrew, but
        // only for a phone set to Hebrew; see the menu's entries above.
        "Time Learned": "זמן שנלמד",
        "%d min": "%d דק׳",
        "1 min": "דקה אחת",
        "Student": "תלמיד",
        "Edit": "עריכה",
        "Device Permissions": "הרשאות מכשיר",
        "Microphone": "מיקרופון",
        "Camera": "מצלמה",
        "Enabled": "מאופשר",
        "Disabled": "לא מאופשר",
        "Not requested": "לא התבקש",
        "Preferences": "העדפות",
        "Language": "שפה",
        "System Language": "שפת המערכת",
        "Privacy Controls": "בקרות פרטיות",
        "About": "אודות",
        "Account & Security": "חשבון ואבטחה",
        "Password, logout and account removal": "סיסמה, התנתקות ומחיקת חשבון",
        "Audio + Text": "אודיו + טקסט",
        "Video + Audio + Text": "וידאו + אודיו + טקסט",
        "Currency": "מטבע",
        "ILS": "ש״ח",
        "Appearance": "מראה",
        "Dark": "כהה",
        "Light": "בהיר",
        "System": "מערכת",
        "System Permission": "הרשאת מערכת",
        "Push Notifications": "התראות פוש",
        "Notify me when a teacher sends an incoming message": "שלחו לי התראה כשמורה שולח הודעה נכנסת",
        "Notify me about general announcements": "שלחו לי התראות על הודעות כלליות",
        // The rest of Instant Teacher's screens in the brand's look: the settings
        // pages, Help & Support, dialogs, log-in and profile editing. Remote
        // Config has these in Hebrew, but only for a phone set to Hebrew.
        "Settings: %@": "הגדרות : %@",
        "Close": "סגור",
        "Contact Us": "צור קשר",
        "EULA": "תנאי שימוש",
        "Privacy Policy": "מדיניות פרטיות",
        "Change Password": "שינוי סיסמה",
        "Log Out": "התנתק",
        "Delete Account": "מחיקת חשבון",
        "Permanently remove your account": "מחק את חשבונך לצמיתות",
        "Privacy": "פרטיות",
        "Show my profile image": "הצג את תמונת הפרופיל שלי",
        "Allow incoming messages from a teacher while not in a call": "אפשר הודעות נכנסות ממורה כשאני לא בשיחה",
        "Use the device language": "השתמש בשפת המכשיר",
        "Send a message to support. You will preview the data before it is sent.": "שלח הודעה לתמיכה. תוכל לראות תצוגה מקדימה של הנתונים לפני השליחה.",
        "Title": "כותרת",
        "What can we help with?": "במה אפשר לעזור?",
        "Description": "תיאור",
        "Preview and Submit": "תצוגה מקדימה ושליחה",
        "Data to be sent": "הנתונים שיישלחו",
        "Preview": "תצוגה מקדימה",
        "Send": "שלח",
        "OK": "אישור",
        "Cancel": "ביטול",
        "Delete": "מחק",
        "Are you sure you want to log out?": "האם אתה בטוח שברצונך להתנתק?",
        "Welcome Back": "ברוך השב",
        "Enter your email": "הזן את האימייל שלך",
        "Password": "סיסמה",
        "Enter your password": "הזן את הסיסמה שלך",
        "Forgot Password?": "שכחת סיסמה?",
        "Signing In…": "מתחבר…",
        "Signing in…": "מתחבר…",
        "Or continue with": "או המשך עם",
        "Don't have an account?": "אין לך חשבון?",
        "Sign Up": "הרשמה",
        "Sign In Error": "שגיאת התחברות",
        "An unexpected error occurred.": "אירעה שגיאה בלתי צפויה.",
        "Edit Profile": "ערוך פרופיל",
        "Update the details students and teachers use to recognize and contact you.": "עדכן את הפרטים כך שתלמידים ומורים יוכלו לזהות אותך ולהתקשר איתך",
        "Full Name": "שם מלא",
        "Grade": "כיתה",
        "Date of Birth": "תאריך לידה",
        "Save Changes": "שמור שינויים",
        "Select": "בחר",
        "Clear": "נקה",
        "Set date of birth": "הגדר תאריך לידה",
        "Take Photo": "צלם תמונה",
        "Choose from Library": "בחר מהספרייה",
        "Searching for a teacher\u{2026}": "מחפש מורה\u{2026}",
        "This usually takes under 30 seconds.": "בדרך כלל זה לוקח פחות מ־30 שניות.",
        "No Teachers Available": "אין מורים זמינים",
        "All teachers are busy right now.\nTry again in a few minutes.": "כל המורים עסוקים כרגע.\nנסה שוב בעוד כמה דקות.",
        "Could Not Send Question": "לא ניתן לשלוח את השאלה",
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
        // Student home grid — a teacher in a session. New key (`busy`), not in
        // the published config until the template is republished.
        "Busy": "בשיעור",
        // Telling one side about the other while the lesson connects. New keys,
        // not in the published config until the template is republished.
        "Waiting for the student": "בהמתנה לתלמיד/ה",
        "Waiting for your teacher": "בהמתנה למורה",
        "The student was asked to allow access to their microphone. Do you want to wait until they approve?":
          "התלמיד/ה התבקש/ה לאשר גישה למיקרופון. רוצה להמתין עד לאישור?",
        "The student was asked to allow access to their camera. Do you want to wait until they approve?":
          "התלמיד/ה התבקש/ה לאשר גישה למצלמה. רוצה להמתין עד לאישור?",
        "Your teacher was asked to allow access to their microphone. Do you want to wait until they approve?":
          "המורה התבקש/ה לאשר גישה למיקרופון. רוצה להמתין עד לאישור?",
        "Your teacher was asked to allow access to their camera. Do you want to wait until they approve?":
          "המורה התבקש/ה לאשר גישה למצלמה. רוצה להמתין עד לאישור?",
        "The student needs to finish setting up and will join shortly. Do you want to wait?":
          "התלמיד/ה צריך/ה לסיים את ההגדרות ויצטרף/תצטרף בקרוב. רוצה להמתין?",
        "Your teacher needs to finish setting up and will join shortly. Do you want to wait?":
          "המורה צריך/ה לסיים את ההגדרות ויצטרף/תצטרף בקרוב. רוצה להמתין?",
        "The student cancelled the session.": "התלמיד/ה ביטל/ה את השיעור.",
        "Your teacher cancelled the session.": "המורה ביטל/ה את השיעור.",
        "You can take the next question.": "אפשר לקבל את השאלה הבאה.",
        "You can ask your question again.": "אפשר לשאול את השאלה שוב.",
        // Session header until both sides have connected. New key
        // (`billing_starts_once`), not in the published config until the
        // template is republished.
        "Billing starts once you're both connected.": "החיוב מתחיל כששניכם מחוברים.",
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
        "Build the formula, then add it to your question.": "בנו את הנוסחה ואז הוסיפו אותה לשאלה.",
        // Demo-student and simulator copy carried over from this branch.
        // Settings, chat status, notification and payment-history copy that had
        // no template entry. Translated alongside the Remote Config additions.
        "%@/min": "%@ לדקה",
        // Ask-a-Teacher composer copy added with the redesigned sheet. No
        // Remote Config entries yet, so these fallbacks are what renders.
        "Tell us what you're stuck on. A teacher usually joins within a minute.": "ספרו לנו במה נתקעתם. מורה בדרך כלל מצטרף תוך כדקה.",
        "For example: I got stuck on question 3 right after opening the parentheses.": "לדוגמה: נתקעתי בשאלה 3 מיד אחרי פתיחת הסוגריים.",
        "Math keyboard": "מקלדת נוסחאות",
        "Ready to send": "אפשר לשלוח",
        "Debug builds only": "גרסאות פיתוח בלבד",
        "Enabling...": "מפעיל...",
        "Image": "תמונה",
        "Images": "תמונות",
        "Loading...": "טוען...",
        "No payments yet": "אין עדיין תשלומים",
        "No subjects selected": "לא נבחרו מקצועות",
        "Payment History": "היסטוריית תשלומים",
        "Please sign out and sign in again before deleting your account.": "התנתקו והתחברו מחדש לפני מחיקת החשבון.",
        "Stay in the loop": "הישארו מעודכנים",
        "Student is reading chat — video paused": "התלמיד קורא את הצ׳אט — הווידאו מושהה",
        "Switching to text chat…": "עובר לצ׳אט טקסט…",
        "Teacher is reading chat — video paused": "המורה קורא את הצ׳אט — הווידאו מושהה",
        "Test Crashlytics Crash": "בדיקת קריסה ב־Crashlytics",
        "Refresh Remote Config": "רענון Remote Config",
        "Remote Config refreshed — %d keys loaded.": "‏Remote Config רוענן — נטענו %d מפתחות.",
        "Remote Config refresh returned no keys. Check the connection and that a template is published.": "רענון Remote Config לא החזיר מפתחות. בדקו את החיבור ושפורסמה תבנית.",
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
        // Permission-denied dialog title and per-context messages with Settings deep-link.
        "Permission required": "נדרשת הרשאה",
        "Microphone access is required for an audio session. Enable it in Settings.": "נדרשת גישה למיקרופון לשיחת שמע. הפעילו אותה בהגדרות.",
        "Microphone access is required for a video session. Enable it in Settings.": "נדרשת גישה למיקרופון לשיחת וידאו. הפעילו אותה בהגדרות.",
        "Microphone and camera access are required for a video session. Enable them in Settings.": "נדרשת גישה למיקרופון ולמצלמה לשיחת וידאו. הפעילו אותן בהגדרות.",
        // Teacher incoming-question permission prompts.
        "The student is requesting an audio call. Enable microphone access to accept.": "התלמיד מבקש שיחת שמע. הפעילו גישה למיקרופון כדי לקבל.",
        "The student is requesting a video call. Enable microphone access to accept.": "התלמיד מבקש שיחת וידאו. הפעילו גישה למיקרופון כדי לקבל.",
        "The student is requesting a video call. Enable camera access to accept.": "התלמיד מבקש שיחת וידאו. הפעילו גישה למצלמה כדי לקבל.",
        // App Permissions screen — notification row.
        "Notifications": "התראות",
        "Alerts when a teacher accepts your request or replies": "התראות כשמורה מקבל את בקשתך או עונה",
        // Contextual permission prompts (replacing the removed onboarding permissions screen).
        "App Permissions": "הרשאות אפליקציה",
        "Microphone and camera": "מיקרופון ומצלמה",
        "System Permissions": "הרשאות מערכת",
        "Required for audio and video sessions": "נדרש לשיעורי שמע וסרטון",
        "Required for video sessions and taking photos": "נדרש לשיעורי סרטון ולצילום תמונות",
        "Camera access required": "נדרשת גישה למצלמה",
        "Enable camera access in Settings to take photos.": "אפשרו גישה למצלמה בהגדרות כדי לצלם תמונות.",
        "Complete now": "להשלים עכשיו",
        "Complete your verification": "השלימו את האימות שלכם",
        "Continue - upload later": "המשך - העלאה מאוחר יותר",
        "Maybe later": "אולי מאוחר יותר",
        "Nice work on your first lesson! Uploading the rest of your verification documents helps us confirm you as a teacher faster. It's optional — you can also do it anytime from your Profile.": "כל הכבוד על השיעור הראשון! העלאת שאר מסמכי האימות עוזרת לנו לאשר אתכם כמורים מהר יותר. ההעלאה אינה חובה — תוכלו לבצע אותה בכל עת מהפרופיל שלכם.",
        "Upload your remaining verification documents": "העלו את מסמכי האימות שנותרו",
        "Upload a clear photo of your passport, driver's license,\nor national ID. A valid government ID is required to\nbecome a verified teacher.": "העלו תמונה ברורה של דרכון, רישיון נהיגה\nאו תעודת זהות. נדרשת תעודה מזהה ממשלתית תקפה\nכדי להפוך למורה מאומת.",
        // Pro Teacher's screens in the brand's look. Remote Config has these in
        // Hebrew, but only for a phone set to Hebrew.
        "Home": "בית",
        "Teacher": "מורה",
        "Teacher Dashboard": "לוח המורה",
        "Turn on notifications, Questions reach you by notification when the app is in the background.": "הפעילו התראות. שאלות מגיעות אליכם בהתראה כשהאפליקציה ברקע.",
        "Waiting for students...": "ממתין לתלמידים...",
        "Verified Expert": "מומחה מאומת",
        "Pending Verification": "ממתין לאימות",
        "Edit Subjects": "ערוך נושאים",
        "Earnings Snapshot": "סיכום הכנסות",
        "Today": "היום",
        "This Week": "השבוע",
        "All Time": "כל הזמן",
        "Total minutes tutored": "סך דקות הוראה",
        "%d mins tutored": "%d דקות לימוד",
        "Live Earnings Today": "הכנסות היום בזמן אמת",
        "Mic": "מיקרופון",
        "On": "פועל",
        "Off": "כבוי",
        "Cam": "מצלמה",
        "Ready": "מוכן",
        "Status": "מצב",
        "Connected": "מחובר",
        "Live Queue": "תור חי",
        "%d Waiting": "%d ממתינים",
        "Readiness Checklist": "רשימת מוכנות",
        "Complete your profile": "השלם את הפרופיל שלך",
        "Get paid for the time you taught": "מקבלים תשלום על הזמן שלימדתם",
        "Paid once a month": "התשלום מועבר אחת לחודש",
        "Microphone Enabled": "מיקרופון פועל",
        "Microphone Disabled": "מיקרופון כבוי",
        "Required for voice sessions.": "נדרש לשיעורי שמע.",
        "Camera Enabled": "מצלמה פועלת",
        "Camera Disabled": "מצלמה כבויה",
        "Enable for video tutoring.": "הפעל לשיעורי וידאו.",
        "Connection": "חיבור",
        "QUESTION": "שאלה",
        "Voice Message": "הודעה קולית",
        "Accept Question": "קבל שאלה",
        "Decline": "דחה",
        "WAITING": "ממתין",
        "SECONDS": "שניות",
        "Could not start the audio/video connection. Please try again.": "לא ניתן היה להתחיל את חיבור האודיו/וידאו. נסה שוב.",
        "Search lessons or students": "חפש שיעורים או תלמידים",
        "min": "דק׳",
        "Teacher Payout Settings": "הגדרות תשלום למורה",
        "Force Reload Remote Config": "טעינה מחדש של Remote Config",
        "ACCOUNT & SECURITY": "חשבון ואבטחה",
        "ABOUT": "אודות",
        "Preview only. No account was deleted.": "תצוגה מקדימה בלבד. החשבון לא נמחק.",
        "Send a password reset email to the email address on this account.": "שלח אימייל לאיפוס סיסמה לכתובת האימייל בחשבון זה.",
        "Send Reset Email": "שלח אימייל לאיפוס",
        "Notify me when a student sends an incoming message": "הודיעו לי כשתלמיד שולח הודעה",
        "Enable Notifications": "אפשר התראות",
        "Open System Settings": "פתח הגדרות מערכת",
        "Notification Preferences": "העדפות התראות",
        "Retry": "נסה שוב",
        "Teaching Details": "נתוני לימוד",
        "Grade Levels Taught": "כיתות שאני מלמד",
        "Subjects": "מקצועות",
        "Complete Your Documents": "השלם את המסמכים שלך",
        "Documents Uploaded": "מסמכים שהועלו",
        "View the verification documents you uploaded": "צפייה במסמכי האימות שהעלית",
        "Choose grades": "בחר כיתות",
        "%d selected": "%d נבחרו",
        "Connect instantly with verified math\nteachers for on-demand help, or share your\nexpertise.": "התחבר מיידית למורים מאומתים\nלמתמטיקה לקבלת עזרה לפי דרישה, או שתף\nאת המומחיות שלך.",
        "App Preview": "תצוגה מקדימה של האפליקציה",
        "Verified Tutors": "מורים מאומתים",
        "Privacy Protected": "פרטיות מוגנת",
        "Already have an account? Log In": "כבר יש לך חשבון? התחבר",
        "What can you teach?": "מה אתה יכול ללמד?",
        "Step 2 of 2": "שלב 2 מתוך 2",
        "Choose a subject area, then select at least\none subtopic students can request.": "בחר תחום לימוד, ואז בחר לפחות\nתת־נושא אחד שתלמידים יכולים לבקש.",
        "Checking your subjects…": "בודק את הנושאים שלך…",
        "Subject Area": "תחום לימוד",
        "Choose one or more subjects to see subtopics.": "בחר נושא אחד או יותר כדי לראות תתי־נושאים.",
        "Search subjects or subtopics": "חפש נושאים או תתי־נושאים",
        "%@ subtopics": "%@ תתי־נושאים",
        "Required": "חובה",
        "Continue to Onboarding": "המשך לקליטה",
        "Verify Your Identity": "אמת את זהותך",
        "Step 1 of 2": "שלב 1 מתוך 2",
        "Checking…": "בודק…",
        "Government ID": "תעודה מזהה ממשלתית",
        "Front Side": "צד קדמי",
        "Back Side": "צד אחורי",
        "Government ID – Front": "תעודה מזהה ממשלתית - צד קדמי",
        "Tap to upload document": "הקש להעלאת מסמך",
        "PDF, JPG or PNG (Max 5MB)": "PDF, JPG או PNG (עד 5MB)",
        "Uploading…": "מעלה…",
        "Uploading selfie…": "מעלה סלפי…",
        "Take Selfie": "צלם סלפי",
        "Ensure good lighting": "ודא תאורה טובה",
        "required": "חובה",
        "VERIFICATION STATUS": "סטטוס אימות",
        "Incomplete": "לא הושלם",
        "Optional": "אופציונלי",
        "Submit for Review": "שליחה לבדיקה",
        "Accept the terms to continue": "יש לאשר את התנאים כדי להמשיך",
        "Upload the front side of your ID to continue": "העלה את הצד הקדמי של התעודה כדי להמשיך",
        "I confirm that the uploaded documents are authentic and belong to me. I agree to the Verification Terms.": "אני מאשר שהמסמכים שהועלו אמיתיים ושייכים לי. אני מסכים לתנאי האימות.",
        "Your Privacy Matters": "הפרטיות שלך חשובה",
        "Your documents are securely encrypted and\nonly used for verification purposes. They will\nnot be shared publicly on your profile.": "המסמכים שלך מוצפנים באופן מאובטח\nומשמשים רק למטרות אימות. הם\nלא ישותפו באופן ציבורי בפרופיל שלך.",
        "Could not read selected image": "לא ניתן היה לקרוא את התמונה שנבחרה",
        "Connect & Learn": "התחבר ולמד",
        "To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly.": "כדי לתת לך את חוויית לימוד המתמטיקה\nהטובה ביותר, אנחנו צריכים כמה\nהרשאות כדי לחבר אותך מיידית.",
        "Use video in live\nlessons and update\nyour profile photo\nwhen needed.": "שימוש בשיחת וידאו לשיעורים ולתמונת פרופיל כשנדרש",
        "Continue Setup": "המשך הגדרות",
        "Not now, use limited mode": "לא עכשיו, השתמש במצב מוגבל",
        "Loading your profile…": "טוען את הפרופיל שלך…",
        "Continue": "המשך",
        "Phone Number": "מספר טלפון",
        "Phone Number (Optional)": "מספר טלפון (אופציונלי)",
        "Add Now": "הוסף עכשיו",
        "Continue Anyway": "המשך בכל זאת",
        "Your Grade": "הכיתה שלך",
        "Messages": "הודעות",
        "Loading messages": "טוען הודעות",
        "Done": "סיום",
        "No messages": "אין הודעות",
        "New updates and personal messages will appear here.": "עדכונים חדשים והודעות אישיות יופיעו כאן.",
        "Sent %@": "נשלח %@",
        "These are the verification documents you uploaded.": "אלה מסמכי האימות שהעלית.",
        "Loading documents...": "טוען מסמכים...",
        "No documents uploaded yet.": "עדיין לא הועלו מסמכים.",
        "Could not load this document.": "לא ניתן לטעון מסמך זה.",
        "Add missing documents": "הוספת מסמכים חסרים",
        "Uploading the remaining documents helps us verify you as a teacher faster.": "העלאת המסמכים הנותרים עוזרת לנו לאמת אותך כמורה מהר יותר.",
        "Not uploaded yet": "עדיין לא הועלה",
        "Upload": "העלאה",
        "Past Lessons": "שיעורים קודמים",
        "Loading session details": "טוען פרטי שיעור",
        "Lesson": "שיעור",
        "Duration": "משך",
        "Original Question": "השאלה המקורית",
        "Summary": "סיכום",
        "Chat Messages": "הודעות צ׳אט",
        "Transcript Preview": "תצוגה מקדימה של התמלול",
        "Listen to Lesson": "האזנה לשיעור",
        "Pause Audio": "השהיית ההאזנה",
        "Audio message": "הודעת שמע",
        "Video message": "הודעת וידאו",
        "Verify your email": "אמת את כתובת המייל שלך",
        "Resend email": "שלח שוב",
        "I've verified": "אימתתי",
        "Email sent": "המייל נשלח",
        "We sent a link to %@. Open it, then come back and tap “I've verified”.": "שלחנו קישור אל %@. פתח אותו, ואז חזור לכאן והקש על „אימתתי”.",
        "Couldn't send the email. Please try again later.": "לא הצלחנו לשלוח את המייל. נסה שוב מאוחר יותר.",
        "Couldn't check your email right now. Please try again.": "לא הצלחנו לבדוק את המייל כרגע. נסה שוב.",
        "Not verified yet": "המייל עדיין לא אומת",
        "Open the link we emailed you, then tap “I've verified” again.": "פתח את הקישור ששלחנו אליך במייל, ואז הקש שוב על „אימתתי”.",
        "This email address has already received its welcome reward.": "כתובת המייל הזו כבר קיבלה את מתנת ההצטרפות.",
        "Welcome bonus unlocked": "בונוס ההצטרפות הופעל",
        "Welcome bonus": "בונוס הצטרפות",
        "Thanks for verifying your email. Enjoy your first lessons!": "תודה שאימתת את המייל. תהנה מהשיעורים הראשונים!",
        "%d free minutes added": "נוספו %d דקות חינם",
        "Verify your email address and get %d free minutes.": "אמת את כתובת המייל שלך וקבל %d דקות חינם.",
        "Verify your email address and keep %d%% of your earnings for your first %d minutes of teaching.": "אמת את כתובת המייל שלך וקבל %d%% מההכנסות על %d דקות ההוראה הראשונות שלך.",
        "You keep %d%% of your earnings for your next %d minutes of teaching.": "אתה מקבל %d%% מההכנסות על %d דקות ההוראה הבאות שלך.",
        "Create Account": "יצירת חשבון",
        "Enter a valid email address.": "הזן כתובת אימייל תקינה.",
        "Min. 6 characters": "לפחות 6 תווים",
        "Must be at least 6 characters.": "חייב להכיל לפחות 6 תווים.",
        // The profile of a student without an account.
        "Anonymous": "אנונימי",
        "You're using the app anonymously": "אתה משתמש באפליקציה באופן אנונימי",
        "Create an account to keep your minutes and lessons, and to log in on any device.": "צור חשבון כדי לשמור את הדקות והשיעורים שלך ולהתחבר מכל מכשיר.",
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
        "Your question is too long. Please shorten it to %d characters.": "fmt_question_too_long",
        // Would generate `buy_more_minutes`, which the button of that name owns.
        "Buy more minutes to carry on, or end the call with a short note for your teacher.":
          "out_of_minutes_message",
        // `your_teacher_will` already belongs to "Your teacher will join shortly".
        "Your teacher will see this before the call ends.": "farewell_prompt_message",
        "You're asking too quickly. Try again in %d seconds.": "fmt_asking_too_quickly",
        "You've asked a lot of questions this hour. Try again in %d minutes.":
          "fmt_hourly_ask_limit",
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
        // Shared `enter_your_password` with the login field, so the delete-account
        // confirmation was showing the login prompt's translation.
        // Shared `default_session_type` with the settings section title.
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
        "Key 1": "key_1",
        "Key 2": "key_2",
        "LANGUAGE": "language_caps",
        "Messages": "messages_a",
        "Microphone access is required for an audio session.": "microphone_access_audio_session",
        "Microphone access is required to accept an audio session.": "microphone_access_accept_audio",
        "Microphone and camera access are required for a video session.": "microphone_camera_video_session",
        "Microphone and camera access are required to accept a video session.": "microphone_camera_accept_video",
        // Permission-denied prompts with Settings deep-link (replacing the older strings above).
        "Permission required": "permission_required",
        "Microphone access is required for an audio session. Enable it in Settings.": "mic_denied_audio_enable",
        "Microphone access is required for a video session. Enable it in Settings.": "mic_denied_video_enable",
        "Microphone and camera access are required for a video session. Enable them in Settings.": "mic_camera_denied_video_enable",
        // Incoming-question teacher prompts — all share the same auto-generated prefix.
        "The student is requesting an audio call. Enable microphone access to accept.": "student_requesting_audio_mic",
        "The student is requesting a video call. Enable microphone access to accept.": "student_requesting_video_mic",
        "The student is requesting a video call. Enable camera access to accept.": "student_requesting_video_camera",
        // App Permissions screen — notification row.
        "Notifications": "notifications_title",
        "Alerts when a teacher accepts your request or replies": "alerts_when_teacher_accepts",
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

        // The dialog that sends a student in Pro Teacher to Instant Teacher.
        // Named rather than generated, because this copy is meant to be edited
        // in the Remote Config console, where the names are what you search by.
        "Students have a new app": "student_app_prompt_title",
        "Pro Teacher is now our app for teachers only. To keep learning, download Instant Teacher, our new app for students, and sign in there with the same account.":
          "student_app_prompt_message",
        "Download Instant Teacher": "student_app_prompt_download",

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

        // Verify-email reward banner. `verify_your_email` stays with the title,
        // `this_email_address` with "…already in use", and `verified` with the
        // plain "Verified" status label.
        "Verify your email address and get %d free minutes.": "fmt_email_reward_student_offer",
        "Verify your email address and keep %d%% of your earnings for your first %d minutes of teaching.":
          "fmt_email_reward_teacher_offer",

        // Mid-session type switch. The four sentences differ only in who and
        // which medium, so each gets its own key.
        "Your teacher switched the session to audio.": "session_type_switched_teacher_audio",
        "Your teacher switched the session to video.": "session_type_switched_teacher_video",
        "The student switched the session to audio.": "session_type_switched_student_audio",
        "The student switched the session to video.": "session_type_switched_student_video",

        // Telling one side about the other while the lesson connects. The four
        // permission questions differ only in who and which device, the two
        // about finishing setup in Settings only in who, and "Waiting for the
        // student" would share `waiting_for_the` with "Waiting for the other
        // side".
        "Waiting for the student": "connection_setup_waiting_for_student",
        "Waiting for your teacher": "connection_setup_waiting_for_teacher",
        "The student was asked to allow access to their microphone. Do you want to wait until they approve?":
          "connection_setup_student_microphone_permission",
        "The student was asked to allow access to their camera. Do you want to wait until they approve?":
          "connection_setup_student_camera_permission",
        "Your teacher was asked to allow access to their microphone. Do you want to wait until they approve?":
          "connection_setup_teacher_microphone_permission",
        "Your teacher was asked to allow access to their camera. Do you want to wait until they approve?":
          "connection_setup_teacher_camera_permission",
        "The student needs to finish setting up and will join shortly. Do you want to wait?":
          "connection_setup_student_finishing_setup",
        "Your teacher needs to finish setting up and will join shortly. Do you want to wait?":
          "connection_setup_teacher_finishing_setup",
        "This email address has already received its welcome reward.": "email_reward_already_claimed",
        "I've verified": "email_reward_i_verified",

        // `all` holds the "All" subject filter.
        "all": "all_lower",
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
        // `minutes` holds the lowercase unit; the menu's section name is its own.
        "Minutes": "menu_minutes",
        // `completed` holds an old "%d completed"; the activity count's label is its own.
        "Completed": "completed_label",
        // `settings` holds the section's name; the pages' header format is its own.
        "Settings: %@": "fmt_settings_page",
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
