"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_CONVERSATION_TYPE = exports.CONVERSATION_TYPES = exports.ROUND_UP_SECONDS = exports.MIN_BILLABLE_SECONDS = exports.CONNECTION_FEE_CENTS = exports.HARD_CAP_MINUTES = exports.INVITE_EXPIRY_SECONDS = exports.WAVE_TIMEOUT_SECONDS = exports.WAVE_SIZES = void 0;
// ─── Pricing / dispatch constants ───
// Per-minute pricing now lives in Remote Config (see pricing.ts); these
// constants remain only for dispatch sizing and connection-fee fallback.
exports.WAVE_SIZES = [3, 5, 10];
exports.WAVE_TIMEOUT_SECONDS = 12;
exports.INVITE_EXPIRY_SECONDS = 90;
exports.HARD_CAP_MINUTES = 30;
exports.CONNECTION_FEE_CENTS = 50;
exports.MIN_BILLABLE_SECONDS = 30;
exports.ROUND_UP_SECONDS = 30;
exports.CONVERSATION_TYPES = ["text", "audio", "video"];
exports.DEFAULT_CONVERSATION_TYPE = "text";
//# sourceMappingURL=types.js.map