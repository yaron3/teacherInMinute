//
//  StudentHomeViewModeling+QuestionHome.swift
//  teacher-minute
//
//  The student's home: the camera the question is photographed with, and the
//  panel it can be written on instead (`StudentQuestionHomeView`).
//

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

/// Which face of the home is showing.
enum QuestionHomeMode: Hashable {
  case photo
  case text
}

/// Where the not-enough-minutes prompt sends the student.
enum NotEnoughMinutesNextStep {
  case createAccount
  case buyMinutes
}

/// Where an attached photo came from, for analytics.
enum QuestionPhotoSource: String {
  case camera
  case library
}

extension StudentHomeViewModeling {

  // MARK: Question home — copy

  var photoModeLabel: String { LocalizationSupport.localized("Photo") }
  var textModeLabel: String { LocalizationSupport.localized("Text") }
  var attachPhotoLabel: String { LocalizationSupport.localized("Attach photo") }
  /// The character's first bubble on the camera. Broken into lines by hand:
  /// the bubble sets its lines closer than a paragraph would.
  var snapYourQuestionText: String { LocalizationSupport.localized("Snap your\nquestion") }
  /// The character's first bubble on the writing panel, and the hint on it.
  var typeYourQuestionText: String { LocalizationSupport.localized("Write your\nquestion") }
  /// The character's third bubble: two lines in English, one in Hebrew.
  var pricePerMinuteBubbleText: String { LocalizationSupport.localized("₪2\nper minute") }
  var noFixedLessonsText: String { LocalizationSupport.localized("₪2 per minute • no fixed lessons") }
  var chooseKeyboardTitle: String { LocalizationSupport.localized("Choose keyboard") }
  var deletePhotoLabel: String { LocalizationSupport.localized("Delete photo") }
  var findTeacherLabel: String { LocalizationSupport.localized("Find a Teacher") }
  var loadMinutesLabel: String { LocalizationSupport.localized("Load minutes") }
  var emptyQuestionTitle: String { LocalizationSupport.localized("Add your question") }
  var emptyQuestionMessage: String {
    LocalizationSupport.localized("Take a photo of it, or write at least 10 characters.")
  }
  var photoNotAttachedTitle: String { LocalizationSupport.localized("Photo not attached") }

  /// Teachers who could take a question now. One in a lesson is online but
  /// not available, so is not counted.
  var availableTeacherCount: Int {
    onlineTeachers.filter { !$0.isBusy }.count
  }

  /// The count in the character's second bubble; `teachersOnlineBubbleLabel`
  /// goes under it.
  var teachersOnlineBubbleCount: String { "\(availableTeacherCount)" }

  var teachersOnlineBubbleLabel: String {
    availableTeacherCount == 1
      ? LocalizationSupport.localized("teacher\nonline")
      : LocalizationSupport.localized("teachers\nonline")
  }

  // MARK: Question home — not enough minutes

  var notEnoughMinutesTitle: String { LocalizationSupport.localized("Not enough minutes") }
  var currentBalanceLabel: String { LocalizationSupport.localized("Current balance") }
  var createAccountForMinutesLabel: String { LocalizationSupport.localized("Create a user account") }
  var buyMinutesLabel: String { LocalizationSupport.localized("Buy minutes") }
  var alreadyHaveAccountLabel: String { LocalizationSupport.localized("Already have an account?") }

  /// A student who started without an account. Minutes come with one: a
  /// verified address earns the welcome reward (functions/src/emailRewards.ts).
  var isAnonymousAccount: Bool {
    Auth.auth().currentUser?.isAnonymous == true
  }

  /// The free minutes a verified account earns, as the backend reads them:
  /// the Remote Config value when it has a usable one, 30 when it has none.
  var signUpRewardMinutes: Int {
    let configured = RemoteConfigService.readString("email_reward_student_minutes")
    guard let minutes = Double(configured), minutes.isFinite else { return 30 }
    return max(0, Int(minutes))
  }

  /// Why the question cannot go out, and what would let it: an account for a
  /// student who has none — with its free minutes, while there are any on
  /// offer — or more minutes for one who has.
  var notEnoughMinutesMessage: String {
    guard isAnonymousAccount else {
      return LocalizationSupport.localized("Load more minutes to send your question to a teacher.")
    }
    let reward = signUpRewardMinutes
    guard reward > 0 else {
      return LocalizationSupport.localized("Sign up to send your question to a teacher.")
    }
    return String(
      format: LocalizationSupport.localized("Create an account to send your question to a teacher, and get %d free minutes."),
      reward
    )
  }

  /// Why an anonymous student who asked to buy minutes is offered an account
  /// first: purchases belong to one.
  var accountForPurchaseMessage: String {
    LocalizationSupport.localized("Create an account or log in to buy minutes.")
  }

  var currentBalanceText: String {
    remainingMinutes == 1
      ? LocalizationSupport.localized("1 minute")
      : String(format: LocalizationSupport.localized("%d minutes"), max(0, remainingMinutes))
  }

  var notEnoughMinutesPrimaryLabel: String {
    isAnonymousAccount ? createAccountForMinutesLabel : buyMinutesLabel
  }

  /// What the prompt's main button leads to, logged as it is taken.
  func notEnoughMinutesPrimaryTapped() -> NotEnoughMinutesNextStep {
    let step: NotEnoughMinutesNextStep = isAnonymousAccount ? .createAccount : .buyMinutes
    logNotEnoughMinutesAction(step == .createAccount ? "sign_up" : "buy")
    return step
  }

  /// An anonymous student who already has an account asks for the login form.
  func notEnoughMinutesLogInTapped() {
    logNotEnoughMinutesAction("log_in")
  }

  func notEnoughMinutesDismissed() {
    logNotEnoughMinutesAction("dismiss")
  }

  func logNotEnoughMinutesShown() {
    AnalyticsService.shared.logEvent(AnalyticsEvent.notEnoughMinutesShown, parameters: [
      "is_anonymous": isAnonymousAccount ? 1 : 0,
      "remaining_minutes": remainingMinutes
    ])
  }

  /// `action` is "sign_up", "buy" or "dismiss".
  func logNotEnoughMinutesAction(_ action: String) {
    AnalyticsService.shared.logEvent(AnalyticsEvent.notEnoughMinutesAction, parameters: [
      "action": action,
      "is_anonymous": isAnonymousAccount ? 1 : 0
    ])
  }

  // MARK: Buying minutes (MinutesPurchaseView)

  var purchaseTitle: String { LocalizationSupport.localized("Purchase minutes") }
  var purchaseSubtitle: String { LocalizationSupport.localized("Choose the package that fits your next question") }
  var purchaseBackLabel: String { LocalizationSupport.localized("Back") }
  var bestValueLabel: String { LocalizationSupport.localized("Best value") }
  var paymentMethodTitle: String { LocalizationSupport.localized("Payment Method") }
  var changePaymentMethodLabel: String { LocalizationSupport.localized("Change") }
  var purchaseSummaryTitle: String { LocalizationSupport.localized("Purchase summary") }
  var minutesPackageLabel: String { LocalizationSupport.localized("Minutes package") }
  var totalToPayLabel: String { LocalizationSupport.localized("Total to pay") }
  var securePaymentNote: String { LocalizationSupport.localized("Your payment is secure and encrypted") }

  var purchaseBalanceText: String {
    remainingMinutes == 1
      ? LocalizationSupport.localized("Balance: 1 minute")
      : String(format: LocalizationSupport.localized("Balance: %d minutes"), max(0, remainingMinutes))
  }

  /// The big figure on a package's card: its minutes, or the package's name
  /// for one that grants a period of time instead.
  func packageQuantityText(for option: PricingOption) -> String {
    option.minutesGranted.map { "\($0)" } ?? localizedName(for: option)
  }

  func packageUnitText(for option: PricingOption) -> String {
    if option.minutesGranted != nil {
      return LocalizationSupport.localized("minutes")
    }
    return option.type.billingPeriodText.map { LocalizationSupport.localized($0) } ?? ""
  }

  /// What a minute comes to in the package, empty for one without minutes.
  func perMinutePriceText(for option: PricingOption) -> String {
    guard let minutes = option.minutesGranted, minutes > 0 else { return "" }
    let cents = Int((Double(option.priceCents) / Double(minutes)).rounded())
    let price = LessonFormatting.currencyText(cents: cents, currencyCode: option.currency)
    return String(format: LocalizationSupport.localized("%@/min"), price)
  }

  func packageSummaryText(for option: PricingOption) -> String {
    guard let minutes = option.minutesGranted else { return localizedName(for: option) }
    return minutes == 1
      ? LocalizationSupport.localized("1 minute")
      : String(format: LocalizationSupport.localized("%d minutes"), minutes)
  }

  func payLabel(for option: PricingOption) -> String {
    String(format: LocalizationSupport.localized("Pay %@"), option.priceText)
  }

  /// The chosen method's title: "Paying by PayPal", short enough for its
  /// card, and a card payment in the app's own words.
  func paymentMethodTitle(_ method: PaymentMethod) -> String {
    method == .creditCard
      ? method.displayName
      : String(format: LocalizationSupport.localized("Paying by %@"), paymentMethodShortName(method))
  }

  /// The name in the method's box. Brand names stay as their owners write
  /// them, in every language.
  func paymentMethodShortName(_ method: PaymentMethod) -> String {
    switch method {
    case .applePay: return "Apple Pay"
    case .googlePay: return "Google Pay"
    case .paypal, .savedPayPal: return "PayPal"
    case .bit: return "Bit"
    case .creditCard: return LocalizationSupport.localized("Credit card")
    }
  }

  func logPurchaseScreenShown() {
    AnalyticsService.shared.logEvent(AnalyticsEvent.purchaseScreenShown, parameters: [
      "is_anonymous": isAnonymousAccount ? 1 : 0,
      "remaining_minutes": remainingMinutes
    ])
  }

  func logPurchaseStarted(_ option: PricingOption, method: PaymentMethod) {
    AnalyticsService.shared.logEvent(AnalyticsEvent.purchaseStarted, parameters: [
      "pricing_option_id": option.id,
      "payment_method": method.rawValue
    ])
  }

  // MARK: Buying minutes — the confirmation (PurchaseSuccessView)

  var minutesAddedTitle: String { LocalizationSupport.localized("Minutes added successfully") }
  var minutesAddedMessage: String {
    LocalizationSupport.localized("You can go back to your question and pick up exactly where you left off.")
  }
  var topUpDetailsTitle: String { LocalizationSupport.localized("Top-up details") }
  var completedLabel: String { LocalizationSupport.localized("Payment completed") }
  var updatedBalanceLabel: String { LocalizationSupport.localized("Updated balance") }
  var minutesPurchasedLabel: String { LocalizationSupport.localized("Minutes purchased") }
  var readyForNextQuestionText: String { LocalizationSupport.localized("All set for the next question") }
  var backToQuestionLabel: String { LocalizationSupport.localized("Back to the question") }

  /// The minutes bought, or the package's name for one without minutes.
  func purchasedMinutesValue(_ summary: PurchaseSummary) -> String {
    summary.minutes.map { "\($0)" } ?? LocalizationSupport.localized(summary.packageName)
  }

  func logPurchaseSuccessShown(_ summary: PurchaseSummary) {
    AnalyticsService.shared.logEvent(AnalyticsEvent.purchaseSuccessShown, parameters: [
      "minutes": summary.minutes ?? 0,
      "remaining_minutes": remainingMinutes
    ])
  }

  // MARK: Question home — asking

  /// The home asks without a topic: any teacher online may take the question.
  var anyTopic: String { "any" }

  /// The session a question asks for, as chosen in Settings. An audio call
  /// when the student has not chosen.
  var defaultConversationType: String {
    UserDefaults.standard.string(forKey: SessionPreferences.defaultQuestionTypeKey)
      ?? ConversationType.audio.rawValue
  }

  // MARK: Question home — camera

  var questionCameraAccess: PermissionState {
    PermissionService.shared.captureStatus(for: .camera)
  }

  func requestQuestionCameraAccess() async -> PermissionState {
    await PermissionService.shared.requestCapturePermission(for: .camera)
  }

  func openCameraSettings() {
    PermissionService.shared.openAppSettings()
  }

  /// Photographs the question with the camera on screen.
  func takeQuestionPhoto() async throws -> Data {
    do {
      return try await QuestionCamera.capturePhoto()
    } catch {
      logQuestionPhotoFailure(error, source: .camera)
      throw error
    }
  }

#if os(iOS)
  /// A photo picked from the library, made ready to upload.
  func preparedLibraryPhoto(_ data: Data) throws -> Data {
    do {
      return try QuestionCamera.preparedForUpload(data)
    } catch {
      logQuestionPhotoFailure(error, source: .library)
      throw error
    }
  }
#endif

#if os(Android)
  /// A photo from the gallery, or nil when the student backed out of it.
  func pickQuestionPhotoFromLibrary() async throws -> Data? {
    do {
      let base64 = try await Task.detached(priority: .userInitiated) {
        try AndroidAskTeacherImagePickerBridge.pickImageBase64()
      }.value
      guard !base64.isEmpty else { return nil }
      guard let data = Data(base64Encoded: base64) else { throw QuestionCamera.CaptureError.unreadable }
      return data
    } catch {
      logQuestionPhotoFailure(error, source: .library)
      throw error
    }
  }
#endif

  /// Uploads a photo of the question, returning its URL.
  func uploadQuestionPhoto(_ data: Data, source: QuestionPhotoSource) async throws -> String {
    guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
      throw QuestionPhotoError.signedOut(message: signInToAttachPhotoError)
    }
    do {
      let url = try await StorageService.shared.uploadQuestionImage(data: data, uid: uid)
      AnalyticsService.shared.logEvent(AnalyticsEvent.questionPhotoAttached, parameters: [
        "source": source.rawValue,
        "bytes": data.count
      ])
      return url
    } catch {
      logQuestionPhotoFailure(error, source: source)
      throw error
    }
  }

  private func logQuestionPhotoFailure(_ error: Error, source: QuestionPhotoSource) {
    logger.error("[QuestionHome] photo from \(source.rawValue) failed: \(error.localizedDescription)")
    AnalyticsService.shared.logEvent(AnalyticsEvent.questionPhotoFailed, parameters: [
      "source": source.rawValue
    ])
    AnalyticsService.shared.recordError(error, context: "question_photo_\(source.rawValue)")
  }
}

enum QuestionPhotoError: LocalizedError {
  case signedOut(message: String)

  var errorDescription: String? {
    switch self {
    case .signedOut(let message): return message
    }
  }
}
