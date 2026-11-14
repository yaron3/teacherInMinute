// ─── Contact Us attachments ──────────────────────────────────────────────────
//
// Where a Contact Us request's images live. Kept apart from ./contactSupport,
// which registers a Firestore trigger on load, so the admin callables can use
// these without it.

/**
 * The most images one request can carry. The app offers no more, and
 * firestore.rules and storage.rules hold `attachmentCount` and the file names
 * to it.
 */
export const MAX_CONTACT_ATTACHMENTS = 3;

/**
 * How many attachments a request says it has, clamped to what the rules allow,
 * so a malformed document cannot make the trigger read files that were never
 * uploaded.
 */
export function contactAttachmentCount(data: Record<string, unknown>): number {
  const count = data.attachmentCount;
  if (typeof count !== "number" || !Number.isInteger(count) || count < 0) return 0;
  return Math.min(count, MAX_CONTACT_ATTACHMENTS);
}

/**
 * The Storage paths of a request's attachments. The app uploads them to
 * `contactAttachments/{userId}/{requestId}/{index}.jpg` before it writes the
 * request, so the paths are derived here rather than taken from the document.
 */
export function contactAttachmentPaths(data: Record<string, unknown>): string[] {
  const userId = String(data.userId ?? "");
  const requestId = String(data.id ?? "");
  if (!userId || !requestId) return [];
  return Array.from(
    { length: contactAttachmentCount(data) },
    (_, index) => `contactAttachments/${userId}/${requestId}/${index}.jpg`
  );
}
