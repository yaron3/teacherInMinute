"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.USD = exports.DEFAULT_CURRENCY = void 0;
exports.getStudentCurrency = getStudentCurrency;
exports.getExchangeRateToUsd = getExchangeRateToUsd;
exports.getPricePerMinute = getPricePerMinute;
exports.getTeacherShare = getTeacherShare;
exports.resolvePricingForStudent = resolvePricingForStudent;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const firestore = admin.firestore();
exports.DEFAULT_CURRENCY = "ILS";
exports.USD = "USD";
const DEFAULT_PRICE_PER_MINUTE_USD = 0.5;
const DEFAULT_PRICE_PER_MINUTE_ILS = 2.0;
const DEFAULT_EXCHANGE_RATE_ILS = 4.0;
const DEFAULT_TEACHER_SHARE = 0.75;
function normalizeCurrencyCode(value) {
    if (typeof value !== "string")
        return exports.DEFAULT_CURRENCY;
    const trimmed = value.trim().toUpperCase();
    return trimmed.length === 3 ? trimmed : exports.DEFAULT_CURRENCY;
}
async function readRcNumber(key) {
    var _a, _b;
    try {
        const template = await admin.remoteConfig().getTemplate();
        const param = (_a = template.parameters) === null || _a === void 0 ? void 0 : _a[key];
        const raw = (_b = param === null || param === void 0 ? void 0 : param.defaultValue) === null || _b === void 0 ? void 0 : _b.value;
        if (raw == null)
            return undefined;
        const parsed = Number(raw);
        return Number.isFinite(parsed) ? parsed : undefined;
    }
    catch (error) {
        firebase_functions_1.logger.warn(`[pricing] failed reading Remote Config ${key}`, error);
        return undefined;
    }
}
async function getStudentCurrency(studentUid) {
    var _a;
    try {
        const snap = await firestore.collection("users").doc(studentUid).get();
        return normalizeCurrencyCode((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.currency);
    }
    catch (error) {
        firebase_functions_1.logger.warn(`[pricing] failed reading currency for uid=${studentUid}`, error);
        return exports.DEFAULT_CURRENCY;
    }
}
function defaultPricePerMinute(currency) {
    if (currency === exports.USD)
        return DEFAULT_PRICE_PER_MINUTE_USD;
    if (currency === "ILS")
        return DEFAULT_PRICE_PER_MINUTE_ILS;
    return undefined;
}
function defaultExchangeRate(currency) {
    if (currency === exports.USD)
        return 1;
    if (currency === "ILS")
        return DEFAULT_EXCHANGE_RATE_ILS;
    return undefined;
}
async function getExchangeRateToUsd(currency) {
    if (currency === exports.USD)
        return 1;
    const rcKey = `exchange_rate_${currency.toLowerCase()}`;
    const fromRc = await readRcNumber(rcKey);
    if (fromRc !== undefined && fromRc > 0)
        return fromRc;
    const fallback = defaultExchangeRate(currency);
    if (fallback !== undefined)
        return fallback;
    throw new Error(`No exchange rate configured for currency ${currency}`);
}
async function getPricePerMinute(currency) {
    var _a;
    const rcKey = `price_per_minute_${currency.toLowerCase()}`;
    const native = await readRcNumber(rcKey);
    if (native !== undefined && native > 0)
        return native;
    if (currency === exports.USD) {
        const fallback = defaultPricePerMinute(exports.USD);
        if (fallback === undefined) {
            throw new Error("price_per_minute_usd missing in Remote Config and no default");
        }
        return fallback;
    }
    const usdPrice = (_a = await readRcNumber("price_per_minute_usd")) !== null && _a !== void 0 ? _a : defaultPricePerMinute(exports.USD);
    if (usdPrice === undefined || usdPrice <= 0) {
        throw new Error("price_per_minute_usd missing — cannot derive other currencies");
    }
    const rate = await getExchangeRateToUsd(currency);
    return Math.round(usdPrice * rate * 100) / 100;
}
async function getTeacherShare() {
    const fromRc = await readRcNumber("teacher_share");
    if (fromRc !== undefined && fromRc > 0 && fromRc <= 1)
        return fromRc;
    return DEFAULT_TEACHER_SHARE;
}
async function resolvePricingForStudent(studentUid) {
    const currency = await getStudentCurrency(studentUid);
    const [pricePerMinute, exchangeRateToUsd, teacherShare] = await Promise.all([
        getPricePerMinute(currency),
        getExchangeRateToUsd(currency),
        getTeacherShare(),
    ]);
    return { currency, pricePerMinute, exchangeRateToUsd, teacherShare };
}
//# sourceMappingURL=pricing.js.map