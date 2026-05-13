import { AccessToken, VideoGrant } from "livekit-server-sdk";

const API_KEY = process.env.LIVEKIT_API_KEY ?? "";
const API_SECRET = process.env.LIVEKIT_API_SECRET ?? "";

// Tokens are valid for 60 minutes (FR-B-009).
// Lessons hard-cap at 30 min so a token never expires during a lesson.
const TOKEN_TTL_SECONDS = 3600;

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
