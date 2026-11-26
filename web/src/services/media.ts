import { Room, RoomEvent, Track, type RemoteTrack } from "livekit-client";
import { LIVEKIT_URL } from "./lesson";

export interface MediaHandlers {
  /** A remote audio or video track to put on the page. */
  onRemoteTrack: (track: RemoteTrack) => void;
  onRemoteTrackGone: (track: RemoteTrack) => void;
  onDisconnected: () => void;
}

const MAX_ATTEMPTS = 3;

/** Joins the lesson's LiveKit room and publishes the microphone, and the
 *  camera for a video lesson. A camera that will not start falls back to
 *  audio rather than take the lesson down, as on the apps. Retries a connect
 *  lost to a flaky network before giving up, like LiveKitService. */
export async function connectMedia(
  token: string,
  withVideo: boolean,
  handlers: MediaHandlers,
): Promise<{ room: Room; cameraFailed: boolean }> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    if (attempt > 1) await new Promise((r) => setTimeout(r, (attempt - 1) * 1000));
    const room = new Room({ adaptiveStream: true, dynacast: true });
    room
      .on(RoomEvent.TrackSubscribed, (track) => handlers.onRemoteTrack(track))
      .on(RoomEvent.TrackUnsubscribed, (track) => handlers.onRemoteTrackGone(track))
      .on(RoomEvent.Disconnected, () => handlers.onDisconnected());
    try {
      await room.connect(LIVEKIT_URL, token);
      await room.localParticipant.setMicrophoneEnabled(true);
      let cameraFailed = false;
      if (withVideo) {
        try {
          await room.localParticipant.setCameraEnabled(true);
        } catch (error) {
          console.error("[media] camera failed, continuing with audio", error);
          cameraFailed = true;
        }
      }
      // Tracks the teacher published before this side joined.
      for (const p of room.remoteParticipants.values()) {
        for (const pub of p.trackPublications.values()) {
          if (pub.track) handlers.onRemoteTrack(pub.track as RemoteTrack);
        }
      }
      return { room, cameraFailed };
    } catch (error) {
      lastError = error;
      console.error(`[media] connect attempt ${attempt} failed`, error);
      await room.disconnect();
    }
  }
  throw lastError;
}

export function localCameraTrack(room: Room) {
  return room.localParticipant.getTrackPublication(Track.Source.Camera)?.track ?? null;
}

export async function setMicrophone(room: Room, on: boolean) {
  await room.localParticipant.setMicrophoneEnabled(on);
}
