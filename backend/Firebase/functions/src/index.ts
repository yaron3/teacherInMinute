import * as admin from "firebase-admin";
admin.initializeApp();

// Auth lifecycle
export { onUserCreate } from "./users";

// Dispatch pipeline
export { dispatchQuestion, evaluateWave, questionWatchdog, onTeacherStatusChange } from "./dispatch";

// Question lifecycle (all callable — FR-B-010)
export { createQuestion, cancelQuestion, acceptInvite, declineInvite, getQuestionStatus } from "./questions";

// Lesson lifecycle (all callable — FR-B-010)
export {
  startLesson,
  endLesson,
  forceEndLesson,
  endAbandonedLesson,
  rateTeacher,
} from "./lessons";

// Public online-teacher projection students can read
export {
  onTeacherPresenceStatusWritten,
  onTeacherPresenceSubjectsWritten,
  onTeacherPresenceBusyWritten,
} from "./presence";

// Takes offline teachers whose app stopped sending keep-alives and who have no
// push token to be reached by instead
export { teacherKeepAliveWatchdog } from "./keepAlive";

// Platform statistics
export { onUserRoleChange } from "./stats";

// Demo tooling — simulated student questions (local AI service, or canned
// Remote Config messages when it is not running)
export { simulateDemoQuestion, demoStudentAutoReply } from "./demoStudent";

// Coupons
export { redeemCoupon } from "./coupons";

// Teacher rating aggregates (star average + review count)
export { teacherRatingSummary } from "./ratings";

// Teacher earnings, payout schedule and payout method
export {
  teacherEarningsSummary,
  updateTeacherPayoutMethod,
  verifyPayPalPayoutAccount,
} from "./earnings";

// Welcome reward for a verified email, once per real mailbox
export { claimEmailReward } from "./emailRewards";

// Shared email checking — used by the payout form and available to signup
export { validateEmailAddress } from "./emailValidation";

// Admin dashboard
export {
  adminDashboardStatus,
  adminListUsers,
  adminGetUserDetail,
  adminMutateUser,
  adminListQuestions,
  adminListLessons,
  adminListPricing,
  adminListCoupons,
  adminCreateCoupon,
  adminDeleteCoupon,
  adminListPayments,
  adminListContactRequests,
  adminListPendingTeachers,
  adminGetTeacherDocs,
  adminVerifyTeacher,
  adminSendTeacherMessage,
  adminRecomputePlatformStats,
  adminRepublishOnlineTeachers,
} from "./admin";

// Payments — PayPal Checkout + Braintree (Apple Pay, Google Pay)
export {
  createCheckoutSession,
  createPaymentSettingsSession,
  createApplePayCheckout,
  confirmApplePayPayment,
  createGooglePayCheckout,
  confirmGooglePayPayment,
  createPayPalVaultClientToken,
  savePayPalVault,
  removeSavedPayPal,
  chargeSavedPayPal,
  payCardCheckout,
  paypalSuccess,
  paypalCancel,
  paypalWebhook,
  billingPage,
} from "./payments";
