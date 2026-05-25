"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.billingPage = exports.paypalWebhook = exports.paypalCancel = exports.paypalSuccess = exports.createPaymentSettingsSession = exports.createCheckoutSession = exports.rateTeacher = exports.forceEndLesson = exports.endLesson = exports.startLesson = exports.getQuestionStatus = exports.declineInvite = exports.acceptInvite = exports.cancelQuestion = exports.createQuestion = exports.evaluateWave = exports.dispatchQuestion = exports.onUserCreate = void 0;
const admin = require("firebase-admin");
admin.initializeApp();
// Auth lifecycle
var users_1 = require("./users");
Object.defineProperty(exports, "onUserCreate", { enumerable: true, get: function () { return users_1.onUserCreate; } });
// Dispatch pipeline
var dispatch_1 = require("./dispatch");
Object.defineProperty(exports, "dispatchQuestion", { enumerable: true, get: function () { return dispatch_1.dispatchQuestion; } });
Object.defineProperty(exports, "evaluateWave", { enumerable: true, get: function () { return dispatch_1.evaluateWave; } });
// Question lifecycle (all callable — FR-B-010)
var questions_1 = require("./questions");
Object.defineProperty(exports, "createQuestion", { enumerable: true, get: function () { return questions_1.createQuestion; } });
Object.defineProperty(exports, "cancelQuestion", { enumerable: true, get: function () { return questions_1.cancelQuestion; } });
Object.defineProperty(exports, "acceptInvite", { enumerable: true, get: function () { return questions_1.acceptInvite; } });
Object.defineProperty(exports, "declineInvite", { enumerable: true, get: function () { return questions_1.declineInvite; } });
Object.defineProperty(exports, "getQuestionStatus", { enumerable: true, get: function () { return questions_1.getQuestionStatus; } });
// Lesson lifecycle (all callable — FR-B-010)
var lessons_1 = require("./lessons");
Object.defineProperty(exports, "startLesson", { enumerable: true, get: function () { return lessons_1.startLesson; } });
Object.defineProperty(exports, "endLesson", { enumerable: true, get: function () { return lessons_1.endLesson; } });
Object.defineProperty(exports, "forceEndLesson", { enumerable: true, get: function () { return lessons_1.forceEndLesson; } });
Object.defineProperty(exports, "rateTeacher", { enumerable: true, get: function () { return lessons_1.rateTeacher; } });
// Payments — PayPal Checkout
var payments_1 = require("./payments");
Object.defineProperty(exports, "createCheckoutSession", { enumerable: true, get: function () { return payments_1.createCheckoutSession; } });
Object.defineProperty(exports, "createPaymentSettingsSession", { enumerable: true, get: function () { return payments_1.createPaymentSettingsSession; } });
Object.defineProperty(exports, "paypalSuccess", { enumerable: true, get: function () { return payments_1.paypalSuccess; } });
Object.defineProperty(exports, "paypalCancel", { enumerable: true, get: function () { return payments_1.paypalCancel; } });
Object.defineProperty(exports, "paypalWebhook", { enumerable: true, get: function () { return payments_1.paypalWebhook; } });
Object.defineProperty(exports, "billingPage", { enumerable: true, get: function () { return payments_1.billingPage; } });
//# sourceMappingURL=index.js.map