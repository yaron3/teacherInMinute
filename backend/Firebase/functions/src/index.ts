import * as admin from "firebase-admin";
admin.initializeApp();

// Auth lifecycle
export { onUserCreate } from "./users";

// Dispatch pipeline
export { dispatchQuestion, evaluateWave, questionWatchdog, onTeacherStatusChange } from "./dispatch";

// Question lifecycle (all callable — FR-B-010)
export { createQuestion, cancelQuestion, acceptInvite, declineInvite, getQuestionStatus } from "./questions";

// Lesson lifecycle (all callable — FR-B-010)
export { startLesson, endLesson, forceEndLesson, rateTeacher } from "./lessons";

// Platform statistics
export { onUserRoleChange } from "./stats";

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

// Admin dashboard
export {
  adminDashboardStatus,
  adminListUsers,
  adminGetUserDetail,
  adminMutateUser,
  adminListQuestions,
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
