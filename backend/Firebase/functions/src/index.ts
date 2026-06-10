import * as admin from "firebase-admin";
admin.initializeApp();

// Auth lifecycle
export { onUserCreate } from "./users";

// Dispatch pipeline
export { dispatchQuestion, evaluateWave } from "./dispatch";

// Question lifecycle (all callable — FR-B-010)
export { createQuestion, cancelQuestion, acceptInvite, declineInvite, getQuestionStatus } from "./questions";

// Lesson lifecycle (all callable — FR-B-010)
export { startLesson, endLesson, forceEndLesson, rateTeacher } from "./lessons";

// Coupons
export { redeemCoupon } from "./coupons";

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
} from "./admin";

// Payments — PayPal Checkout
export {
  createCheckoutSession,
  createPaymentSettingsSession,
  paypalSuccess,
  paypalCancel,
  paypalWebhook,
  billingPage,
} from "./payments";
