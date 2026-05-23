"use strict";
var _a, _b;
Object.defineProperty(exports, "__esModule", { value: true });
exports.mintLiveKitToken = mintLiveKitToken;
const livekit_server_sdk_1 = require("livekit-server-sdk");
const API_KEY = (_a = process.env.LIVEKIT_API_KEY) !== null && _a !== void 0 ? _a : "";
const API_SECRET = (_b = process.env.LIVEKIT_API_SECRET) !== null && _b !== void 0 ? _b : "";
// Tokens are valid for 60 minutes (FR-B-009).
// Lessons hard-cap at 30 min so a token never expires during a lesson.
const TOKEN_TTL_SECONDS = 3600;
async function mintLiveKitToken(roomName, participantUid) {
    if (!API_KEY || !API_SECRET) {
        throw new Error("LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set in functions/.env");
    }
    const grant = {
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
    };
    const token = new livekit_server_sdk_1.AccessToken(API_KEY, API_SECRET, {
        identity: participantUid,
        ttl: TOKEN_TTL_SECONDS,
    });
    token.addGrant(grant);
    return {
        token: await token.toJwt(),
        expiresAt: new Date(Date.now() + TOKEN_TTL_SECONDS * 1000),
    };
}
//# sourceMappingURL=livekit.js.map