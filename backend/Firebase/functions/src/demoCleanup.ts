// ─── Demo data cleanup ───────────────────────────────────────────────────────
//
// Lists what demo users (see ./demoUsers) left behind in a project — purchases,
// Contact Us requests, questions, lessons, coupons — and the demo accounts
// themselves, so the admin console can offer each as a checkbox and delete
// only what was ticked.
//
// Nothing the client sends is trusted: every record is read again and
// re-checked right before it goes, so a record that turned live, or that
// belongs to (or involves) a real user, is skipped rather than deleted.

import * as admin from "firebase-admin";
import { DEMO_USER_FIELD, inChunks, readDemoUserUids } from "./demoUsers";
import { contactAttachmentPaths } from "./contactAttachments";
import { deleteQuestionRecords } from "./accountDeletion";

export const DEMO_CLEANUP_ITEMS_MAX = 100;
export const DEMO_CLEANUP_ACCOUNTS_MAX = 10;

/**
 * The standing App Store screenshot accounts (CLAUDE.md, "Accounts"). They are
 * demo users too, but are reused for every screenshot set, so the console
 * leaves their account deletion unticked unless the operator ticks it.
 */
export const STANDING_DEMO_EMAILS = new Set([
  "teacher_demo_english@example.com",
  "student_demo_english@example.com",
  "teacher_demo_hebrew@example.com",
  "student_demo_hebrew@example.com",
]);

export type DemoCleanupKind = "purchase" | "contact" | "question" | "lesson" | "coupon";

export interface DemoCleanupItemRef {
  kind: DemoCleanupKind;
  id: string;
}

interface KindSpec {
  collection: string;
  /** Every field naming a person on the record. All of them must be demo
   *  users for the record to be deletable. */
  parties: string[];
  /** Statuses during which the record is live and must not be touched. */
  live: string[];
}

export const KINDS: Record<DemoCleanupKind, KindSpec> = {
  purchase: { collection: "paymentCheckouts", parties: ["uid"], live: [] },
  contact: { collection: "contactRequests", parties: ["userId"], live: [] },
  question: {
    collection: "questions",
    parties: ["studentUid", "acceptedByTeacher", "demoTeacherUid"],
    live: ["searching", "accepted", "in_progress"],
  },
  lesson: { collection: "lessons", parties: ["studentUid", "teacherUid"], live: ["in_progress"] },
  coupon: { collection: "coupons", parties: ["studentUserId"], live: [] },
};

export function isCleanupKind(value: unknown): value is DemoCleanupKind {
  return typeof value === "string" && value in KINDS;
}

/** The people a record names, by its kind's party fields. */
export function partiesOf(kind: DemoCleanupKind, data: Record<string, unknown>): string[] {
  return [
    ...new Set(
      KINDS[kind].parties
        .map((f) => data[f])
        .filter((v): v is string => typeof v === "string" && v.length > 0)
    ),
  ];
}

/**
 * Why a record may not be deleted, or null when it may. A record qualifies when
 * every person it names is a demo user — a question a demo student asked a real
 * teacher holds that teacher's earnings — and it is not live. A sample Contact
 * Us request from the console's "send a sample" button qualifies whoever sent it.
 */
export function blockReason(
  kind: DemoCleanupKind,
  data: Record<string, unknown>,
  demoUids: Set<string>
): string | null {
  const status = String(data.status ?? "");
  if (KINDS[kind].live.includes(status)) return `live (${status})`;
  if (kind === "contact" && data.sample === true) return null;
  const parties = partiesOf(kind, data);
  if (parties.length === 0) return "names no user";
  if (!parties.some((uid) => demoUids.has(uid))) return "not a demo user's";
  if (parties.some((uid) => !demoUids.has(uid))) return "involves a real user";
  return null;
}

function ms(value: unknown): number | null {
  if (!value) return null;
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  const obj = value as { toMillis?: () => number; _seconds?: number; seconds?: number };
  if (typeof obj.toMillis === "function") return obj.toMillis();
  if (typeof obj._seconds === "number") return obj._seconds * 1000;
  if (typeof obj.seconds === "number") return obj.seconds * 1000;
  return null;
}

function clip(text: unknown, max = 60): string {
  const s = typeof text === "string" ? text.replace(/\s+/g, " ").trim() : "";
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

/** One line describing a record, and the date to sort it by. */
export function describe(kind: DemoCleanupKind, data: Record<string, unknown>): { summary: string; at: number | null } {
  switch (kind) {
    case "purchase": {
      const price = Number(data.priceCents) || 0;
      const method = typeof data.paymentMethod === "string" && data.paymentMethod ? data.paymentMethod : data.paypalOrderId ? "paypal" : "";
      return {
        summary: [`${(price / 100).toFixed(2)} ${data.currency ?? ""}`.trim(), `${Number(data.minutes) || 0} min`, method, String(data.status ?? "")]
          .filter(Boolean)
          .join(" · "),
        at: ms(data.completedAt) ?? ms(data.createdAt),
      };
    }
    case "contact":
      return {
        summary: `${data.sample === true ? "[sample] " : ""}${clip(data.title) || clip(data.description) || "Contact request"}`,
        at: ms(data.sentAt),
      };
    case "question":
      return {
        summary: [String(data.topic ?? ""), String(data.status ?? ""), clip(data.text ?? data.questionText, 50)]
          .filter(Boolean)
          .join(" · "),
        at: ms(data.createdAt),
      };
    case "lesson": {
      const seconds = Number(data.durationSeconds ?? data.billedSeconds);
      return {
        summary: [String(data.status ?? ""), Number.isFinite(seconds) ? `${Math.round(seconds / 60)} min` : ""]
          .filter(Boolean)
          .join(" · "),
        at: ms(data.startedAt) ?? ms(data.createdAt),
      };
    }
    case "coupon":
      return {
        summary: [String(data.code ?? ""), data.minutes != null ? `${data.minutes} min` : ""].filter(Boolean).join(" · ") || "Coupon",
        at: ms(data.createdAt),
      };
  }
}

export interface DemoCleanupItem extends DemoCleanupItemRef {
  /** The demo user it is listed under, or null for a sample request sent by
   *  someone who is not a demo user. */
  ownerUid: string | null;
  summary: string;
  at: number | null;
  blocked: string | null;
}

export interface DemoCleanupAccount {
  uid: string;
  email: string | null;
  name: string | null;
  role: string | null;
  standing: boolean;
  /** Records an account deletion would also remove although they involve a
   *  real user (a lesson with a real teacher, say). */
  sharedRecords: number;
  live: number;
}

/** Everything the cleanup could delete in this project, ticked or not. */
export async function buildDemoCleanupPreview(): Promise<{ accounts: DemoCleanupAccount[]; items: DemoCleanupItem[] }> {
  const firestore = admin.firestore();
  const demoUids = await readDemoUserUids();
  const uids = [...demoUids];

  const docs = new Map<string, { kind: DemoCleanupKind; snap: FirebaseFirestore.QueryDocumentSnapshot }>();
  const queries: Promise<void>[] = [];
  for (const kind of Object.keys(KINDS) as DemoCleanupKind[]) {
    const spec = KINDS[kind];
    for (const field of spec.parties) {
      for (const chunk of inChunks(uids)) {
        queries.push(
          firestore.collection(spec.collection).where(field, "in", chunk).get().then((snap) => {
            for (const d of snap.docs) docs.set(`${kind}/${d.id}`, { kind, snap: d });
          })
        );
      }
    }
  }
  queries.push(
    firestore.collection("contactRequests").where("sample", "==", true).get().then((snap) => {
      for (const d of snap.docs) docs.set(`contact/${d.id}`, { kind: "contact", snap: d });
    })
  );
  await Promise.all(queries);

  const items: DemoCleanupItem[] = [...docs.values()].map(({ kind, snap }) => {
    const data = snap.data();
    const owner = partiesOf(kind, data).find((uid) => demoUids.has(uid)) ?? null;
    return { kind, id: snap.id, ownerUid: owner, ...describe(kind, data), blocked: blockReason(kind, data, demoUids) };
  });
  items.sort((a, b) => (b.at ?? 0) - (a.at ?? 0));

  const userSnaps = uids.length ? await firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid))) : [];
  const authUsers = new Map<string, admin.auth.UserRecord>();
  for (const chunk of inChunks(uids)) {
    // getUsers takes up to 100 identifiers; chunks of 30 stay well inside it.
    const { users } = await admin.auth().getUsers(chunk.map((uid) => ({ uid })));
    for (const u of users) authUsers.set(u.uid, u);
  }

  const accounts: DemoCleanupAccount[] = userSnaps.map((snap) => {
    const data = snap.data() ?? {};
    const email = authUsers.get(snap.id)?.email ?? (typeof data.email === "string" ? data.email : null);
    const own = [...docs.values()].filter(({ kind, snap: d }) => partiesOf(kind, d.data()).includes(snap.id));
    return {
      uid: snap.id,
      email,
      name: typeof data.fullName === "string" && data.fullName ? data.fullName : authUsers.get(snap.id)?.displayName ?? null,
      role: typeof data.role === "string" ? data.role : null,
      standing: !!email && STANDING_DEMO_EMAILS.has(email.toLowerCase()),
      sharedRecords: own.filter(({ kind, snap: d }) => blockReason(kind, d.data(), demoUids) === "involves a real user").length,
      live: own.filter(({ kind, snap: d }) => KINDS[kind].live.includes(String(d.data().status ?? ""))).length,
    };
  });
  accounts.sort((a, b) => (a.email ?? a.uid).localeCompare(b.email ?? b.uid));

  return { accounts, items };
}

export type CleanupResult = { status: "deleted" | "skipped" | "failed"; reason?: string };

/**
 * Deletes one record after checking it again against the current demo users.
 * A contact request takes its Storage attachments with it, and a question its
 * RTDB mirror, invitations and board snapshots, as an account deletion would.
 */
export async function deleteDemoCleanupItem(ref: DemoCleanupItemRef, demoUids: Set<string>): Promise<CleanupResult> {
  const firestore = admin.firestore();
  const docRef = firestore.collection(KINDS[ref.kind].collection).doc(ref.id);
  const snap = await docRef.get();
  if (!snap.exists) return { status: "skipped", reason: "already gone" };
  const data = snap.data() ?? {};
  const blocked = blockReason(ref.kind, data, demoUids);
  if (blocked) return { status: "skipped", reason: blocked };

  if (ref.kind === "question") {
    await deleteQuestionRecords(docRef);
  } else {
    if (ref.kind === "contact") {
      const bucket = admin.storage().bucket();
      for (const path of contactAttachmentPaths({ ...data, id: data.id ?? ref.id })) {
        await bucket.file(path).delete({ ignoreNotFound: true });
      }
    }
    await firestore.recursiveDelete(docRef);
  }
  return { status: "deleted" };
}

/** True when `uid` is still marked as a demo user. */
export async function isDemoUser(uid: string): Promise<boolean> {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  return snap.data()?.[DEMO_USER_FIELD] === true;
}
