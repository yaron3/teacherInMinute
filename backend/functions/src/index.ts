import * as admin from "firebase-admin";
admin.initializeApp();

// Auth lifecycle
export { onUserCreate } from "./users";

// Dispatch pipeline
export { dispatchQuestion, evaluateWave } from "./dispatch";

// Question lifecycle (all callable — FR-B-010)
export { createQuestion, cancelQuestion, acceptInvite, declineInvite, getQuestionStatus } from "./questions";

// Lesson lifecycle (all callable — FR-B-010)
export { startLesson, endLesson, forceEndLesson } from "./lessons";

// Payments — PayPal Checkout
export {
  createCheckoutSession,
  createPaymentSettingsSession,
  capturePayPalOrder,
  cancelPayPalOrder,
  paypalWebhook,
  billingPage,
} from "./payments";
