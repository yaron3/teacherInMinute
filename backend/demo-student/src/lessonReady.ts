import * as admin from "firebase-admin";

import type { Config } from "./config";

// A lesson starts only once both participants have reported `ready` to the
// startLesson callable (see startWhenBothReady in functions/src/lessons.ts).
// The student app does that as it finishes connecting; this does the same for
// the demo student, so the teacher is not left on "Waiting for the student".

const READY_ATTEMPTS = 3;

let cachedToken: { idToken: string; expiresAt: number } | null = null;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** An ID token for the demo student: a custom token minted with the service
 *  account, exchanged for an ID token the callable accepts as `req.auth`. */
async function studentIdToken(config: Config): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.idToken;

  const customToken = await admin.auth().createCustomToken(config.studentUid);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${config.firebaseWebApiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  if (!response.ok) {
    throw new Error(`signInWithCustomToken failed: ${response.status} ${await response.text()}`);
  }
  const body = (await response.json()) as { idToken: string; expiresIn: string };
  cachedToken = {
    idToken: body.idToken,
    expiresAt: Date.now() + parseInt(body.expiresIn, 10) * 1000,
  };
  return body.idToken;
}

/** Reports the demo student ready on `questionId`. The lesson starts on
 *  whichever report makes both sides ready, so the order does not matter. */
export async function reportStudentReady(config: Config, questionId: string): Promise<void> {
  if (!config.firebaseWebApiKey) {
    console.warn(
      `[demo-student] FIREBASE_WEB_API_KEY is not set — cannot report ready, the lesson will not start qid=${questionId}`,
    );
    return;
  }

  for (let attempt = 1; attempt <= READY_ATTEMPTS; attempt++) {
    try {
      const idToken = await studentIdToken(config);
      const response = await fetch(`${config.functionsBaseUrl}/startLesson`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
        body: JSON.stringify({ data: { questionId, ready: true } }),
      });
      const body = (await response.json()) as {
        result?: { started?: boolean; lessonId?: string | null };
        error?: { status?: string; message?: string };
      };
      if (body.error) {
        console.warn(
          `[demo-student] ready refused qid=${questionId} status=${body.error.status}: ${body.error.message}`,
        );
        return;
      }
      console.log(
        `[demo-student] ready reported qid=${questionId} started=${String(body.result?.started)} lessonId=${body.result?.lessonId ?? "none"}`,
      );
      return;
    } catch (err) {
      console.warn(
        `[demo-student] ready report failed attempt=${attempt} qid=${questionId}: ${err instanceof Error ? err.message : String(err)}`,
      );
      if (attempt < READY_ATTEMPTS) await sleep(attempt * 2000);
    }
  }
}
