"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ROUND_UP_SECONDS = exports.MIN_BILLABLE_SECONDS = exports.CONNECTION_FEE_CENTS = exports.BASE_RATE_PER_MIN_CENTS = exports.HARD_CAP_MINUTES = exports.WAVE_TIMEOUT_SECONDS = exports.WAVE_SIZES = void 0;
// ─── Pricing / dispatch constants (pilot hard-coded; move to Remote Config later) ───
exports.WAVE_SIZES = [3, 5, 10];
exports.WAVE_TIMEOUT_SECONDS = 12;
exports.HARD_CAP_MINUTES = 30;
exports.BASE_RATE_PER_MIN_CENTS = 99;
exports.CONNECTION_FEE_CENTS = 50;
exports.MIN_BILLABLE_SECONDS = 30;
exports.ROUND_UP_SECONDS = 30;
//# sourceMappingURL=types.js.map