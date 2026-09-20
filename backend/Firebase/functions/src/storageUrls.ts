// ─── Which media URLs a question may carry ───────────────────────────────────
//
// A question's photo URLs are handed to invited teachers and rendered by their
// app. Anything accepted here is therefore a link this backend asks a teacher's
// device to fetch, so only our own bucket qualifies — an arbitrary URL would
// let a student point teachers at a server they control (which sees every
// invited teacher's IP as the image loads) or at another user's files.
//
// The app uploads question photos to `questionImages/{uid}/{timestamp}.jpg` and
// sends back the download URL, on both platforms (see StorageService.swift), so
// the accepted shape is narrow: our bucket, and the caller's own folder.

/** Project whose buckets we accept. Read per call so tests and emulators can
 *  point it elsewhere. */
function projectId(): string {
  return (
    process.env.GCLOUD_PROJECT ??
    process.env.GCP_PROJECT ??
    "teacher-in-a-moment"
  );
}

/** Both spellings of the default bucket: Firebase minted `appspot.com` buckets
 *  before 2024 and `firebasestorage.app` after, and a download URL carries
 *  whichever the SDK was configured with. `STORAGE_BUCKET` adds a third for a
 *  project that uses a custom one. */
function acceptedBuckets(): Set<string> {
  const buckets = new Set([
    `${projectId()}.firebasestorage.app`,
    `${projectId()}.appspot.com`,
  ]);
  const configured = process.env.STORAGE_BUCKET?.trim();
  if (configured) buckets.add(configured);
  return buckets;
}

function safeDecode(value: string): string | undefined {
  try {
    return decodeURIComponent(value);
  } catch {
    // A malformed percent-escape is not a path we can reason about.
    return undefined;
  }
}

/**
 * The object path a storage URL points at — e.g.
 * `questionImages/abc/1757000000000.jpg` — or `undefined` when the URL is not
 * one of our buckets in a form we recognise.
 */
export function storageObjectPath(rawUrl: unknown): string | undefined {
  if (typeof rawUrl !== "string" || rawUrl.trim() === "") return undefined;

  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    return undefined;
  }

  // Plain http would be downgraded in transit; every URL the app produces is
  // https.
  if (url.protocol !== "https:") return undefined;

  const buckets = acceptedBuckets();

  // Firebase download URL: /v0/b/<bucket>/o/<percent-encoded object>
  if (url.hostname === "firebasestorage.googleapis.com") {
    const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(url.pathname);
    if (!match) return undefined;
    const bucket = safeDecode(match[1]);
    if (!bucket || !buckets.has(bucket)) return undefined;
    return safeDecode(match[2]);
  }

  // Plain Cloud Storage URL: /<bucket>/<object>
  if (url.hostname === "storage.googleapis.com") {
    const match = /^\/([^/]+)\/(.+)$/.exec(url.pathname);
    if (!match) return undefined;
    const bucket = safeDecode(match[1]);
    if (!bucket || !buckets.has(bucket)) return undefined;
    return safeDecode(match[2]);
  }

  return undefined;
}

/** True when `rawUrl` is a photo this student uploaded for a question of their
 *  own — our bucket, and their own folder under `questionImages/`. */
export function isOwnQuestionImageUrl(rawUrl: unknown, uid: string): boolean {
  if (!uid) return false;
  const path = storageObjectPath(rawUrl);
  if (!path) return false;
  // `..` cannot escape a prefix in Cloud Storage (object names are literal),
  // but a path carrying one is not something the app produced.
  if (path.includes("..")) return false;
  return path.startsWith(`questionImages/${uid}/`);
}
