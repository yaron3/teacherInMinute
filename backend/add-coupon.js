#!/usr/bin/env node
/**
 * Add a coupon to Firestore.
 *
 * Usage:
 *   node add-coupon.js
 *
 * Requirements:
 *   npm install -g firebase-admin   (or use the one in functions/node_modules)
 *   GOOGLE_APPLICATION_DEFAULT credentials must be active:
 *     firebase login   (sets up ADC via gcloud under the hood), OR
 *     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 */

const readline = require("readline");
const { initializeApp, cert, getApps } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const PROJECT_ID = "teacher-in-a-moment";

// Try to init using Application Default Credentials (works after `firebase login`)
if (!getApps().length) {
  initializeApp({ projectId: PROJECT_ID });
}

const db = getFirestore();

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise((res) => rl.question(q, res));

function randomCouponId(length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1
  return Array.from({ length }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
}

async function main() {
  console.log("\n=== Add Coupon ===\n");

  const studentUserId = (await ask("Student user ID (UID from Firebase Auth): ")).trim();
  if (!studentUserId) { console.error("Student UID is required."); process.exit(1); }

  const createdBy = (await ask("Created by (your name): ")).trim();
  if (!createdBy) { console.error("Creator name is required."); process.exit(1); }

  const minutesRaw = (await ask("Number of minutes to grant: ")).trim();
  const numberOfMinutes = parseInt(minutesRaw, 10);
  if (!Number.isFinite(numberOfMinutes) || numberOfMinutes <= 0) {
    console.error("Minutes must be a positive integer.");
    process.exit(1);
  }

  const priceRaw = (await ask("Price / value (e.g. 9.99): ")).trim();
  const price = parseFloat(priceRaw);
  if (!Number.isFinite(price) || price < 0) {
    console.error("Price must be a non-negative number.");
    process.exit(1);
  }

  const suggestedId = randomCouponId();
  const couponIdInput = (await ask(`Coupon code [leave blank to use ${suggestedId}]: `)).trim();
  const couponId = couponIdInput || suggestedId;

  rl.close();

  console.log("\nAbout to create:");
  console.log(`  Coupon code   : ${couponId}`);
  console.log(`  Student UID   : ${studentUserId}`);
  console.log(`  Minutes       : ${numberOfMinutes}`);
  console.log(`  Price         : ${price}`);
  console.log(`  Created by    : ${createdBy}`);
  console.log("");

  const couponRef = db.collection("coupons").doc(couponId);
  const existing = await couponRef.get();
  if (existing.exists) {
    console.error(`Error: coupon "${couponId}" already exists.`);
    process.exit(1);
  }

  await couponRef.set({
    studentUserId,
    numberOfMinutes,
    price,
    createdBy,
    createdAt: Timestamp.now(),
    activatedAt: null,
  });

  console.log(`✓ Coupon "${couponId}" created successfully.`);
}

main().catch((err) => {
  console.error("Failed:", err.message ?? err);
  process.exit(1);
});
