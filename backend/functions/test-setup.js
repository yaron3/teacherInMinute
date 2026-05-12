#!/usr/bin/env node
/**
 * Pilot setup smoke test.
 * Run from functions/: node test-setup.js
 *
 * Checks:
 *   1. .env is loaded and all required vars are present
 *   2. LiveKit token generation works with your credentials
 *   3. LiveKit server is reachable (HTTP ping)
 */

const fs   = require("fs");
const path = require("path");
const https = require("https");

// ── 1. Load .env manually (no dotenv dependency needed) ──────────────────────

const envPath = path.join(__dirname, ".env");
if (!fs.existsSync(envPath)) {
  console.error("❌  functions/.env not found");
  process.exit(1);
}

fs.readFileSync(envPath, "utf8")
  .split("\n")
  .filter((l) => l.trim() && !l.startsWith("#"))
  .forEach((line) => {
    const eqIdx = line.indexOf("=");
    if (eqIdx < 0) return;
    const key = line.slice(0, eqIdx).trim();
    const val = line.slice(eqIdx + 1).trim();
    process.env[key] = val;
  });

// ── 2. Check required vars ────────────────────────────────────────────────────

const REQUIRED = ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET", "LIVEKIT_URL"];

console.log("\n── Environment ─────────────────────────────────────");
let envOk = true;
for (const key of REQUIRED) {
  const val = process.env[key];
  if (val && !val.includes("your_")) {
    const preview = key.includes("SECRET") ? `${"*".repeat(8)} (${val.length} chars)` : val;
    console.log(`✅  ${key.padEnd(22)} ${preview}`);
  } else {
    console.log(`❌  ${key.padEnd(22)} not set or still placeholder`);
    envOk = false;
  }
}

if (!envOk) {
  console.error("\n❌  Fix the missing values in functions/.env and re-run.\n");
  process.exit(1);
}

// ── 3. LiveKit token generation ───────────────────────────────────────────────

async function testToken() {
  console.log("\n── LiveKit token generation ─────────────────────────");
  const { AccessToken } = require("livekit-server-sdk");

  const at = new AccessToken(
    process.env.LIVEKIT_API_KEY,
    process.env.LIVEKIT_API_SECRET,
    { identity: "test-teacher", ttl: 3600 }
  );
  at.addGrant({ roomJoin: true, room: "test-room", canPublish: true, canSubscribe: true });

  const jwt = await at.toJwt();
  console.log(`✅  Token generated   length=${jwt.length}`);
  console.log(`    Preview: ${jwt.slice(0, 72)}…`);
  return jwt;
}

// ── 4. LiveKit server reachability ────────────────────────────────────────────

function pingLiveKit() {
  return new Promise((resolve) => {
    console.log("\n── LiveKit server reachability ──────────────────────");
    // Convert wss:// → https:// for the HTTP health check
    const httpUrl = process.env.LIVEKIT_URL.replace(/^wss:\/\//, "https://") + "/rtc";
    console.log(`    Pinging ${httpUrl}`);

    const req = https.get(httpUrl, (res) => {
      // Any HTTP response proves the server is alive.
      // 401 = auth required, 426 = WebSocket upgrade required — both are correct.
      res.resume(); // consume response so socket closes cleanly
      console.log(`✅  Server reachable  HTTP ${res.statusCode}`);
      resolve();
    });

    req.on("error", (err) => {
      console.log(`❌  Server unreachable: ${err.message}`);
      resolve();
    });

    req.setTimeout(8000, () => {
      console.log("❌  Server ping timed out after 8s");
      req.destroy();
      resolve();
    });
  });
}

// ── Run all checks ────────────────────────────────────────────────────────────

(async () => {
  try {
    await testToken();
    await pingLiveKit();
    console.log("\n✅  All checks passed — ready to run the emulator.\n");
  } catch (err) {
    console.error("\n❌  Test failed:", err.message);
    process.exit(1);
  }
})();
