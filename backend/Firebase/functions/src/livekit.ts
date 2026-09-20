// The SDK is required at call time, not at module load. index.ts exports every
// function from one file, so anything imported at module scope is parsed on the
// cold start of *every* function — including the ones that never mint a token.
// `import type` is erased at compile time and costs nothing.
import type { VideoGrant } from "livekit-server-sdk";

const API_KEY = process.env.LIVEKIT_API_KEY ?? "";
const API_SECRET = process.env.LIVEKIT_API_SECRET ?? "";

// Tokens are valid for 60 minutes (FR-B-009).
// Lessons hard-cap at 30 min so a token never expires during a lesson.
const TOKEN_TTL_SECONDS = 3600;

/** The room a lesson's student and teacher meet in, named for its question. */
export function lessonRoomName(questionId: string): string {
  return `lesson_${questionId}`;
}

export async function mintLiveKitToken(roomName: string, participantUid: string): Promise<{
  token: string;
  expiresAt: Date;
}> {
  if (!API_KEY || !API_SECRET) {
    throw new Error("LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set in functions/.env");
  }

  const grant: VideoGrant = {
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
  };

  const { AccessToken } = await import("livekit-server-sdk");
  const token = new AccessToken(API_KEY, API_SECRET, {
    identity: participantUid,
    ttl: TOKEN_TTL_SECONDS,
  });
  token.addGrant(grant);

  return {
    token: await token.toJwt(),
    expiresAt: new Date(Date.now() + TOKEN_TTL_SECONDS * 1000),
  };
}
