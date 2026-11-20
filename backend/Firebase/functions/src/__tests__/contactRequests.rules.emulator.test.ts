/**
 * The rules behind Contact Us with attachments (IT-32), run against the real
 * rules engine: the request document in Firestore, and the images uploaded to
 * Storage before it.
 *
 * The app uploads each image to `contactAttachments/{uid}/{requestId}/{n}.jpg`
 * and then writes `contactRequests/{requestId}` with `attachmentCount`; the
 * backend reads the images back by index (contactAttachments.ts).
 *
 * These need the Firestore and Storage emulators:
 *
 *     npm run test:emulator
 */
import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import { getBytes, ref, uploadBytes } from "firebase/storage";

const PROJECT_ID = "demo-teacher-in-a-moment";
const USER = "user-1";
const OTHER = "user-2";
const REQUEST_ID = "REQ-1";

const RULES_DIR = path.join(__dirname, "..", "..", "..");

let env: RulesTestEnvironment;

function hostAndPort(variable: string): { host: string; port: number } {
  const value = process.env[variable];
  if (!value) throw new Error(`${variable} is not set: run with \`npm run test:emulator\``);
  const [host, port] = value.split(":");
  return { host, port: Number(port) };
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      ...hostAndPort("FIRESTORE_EMULATOR_HOST"),
      rules: fs.readFileSync(path.join(RULES_DIR, "firestore.rules"), "utf8"),
    },
    storage: {
      ...hostAndPort("FIREBASE_STORAGE_EMULATOR_HOST"),
      rules: fs.readFileSync(path.join(RULES_DIR, "storage.rules"), "utf8"),
    },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

afterEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});

/** What ContactSupportRequest.firestoreData writes. */
function request(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: REQUEST_ID,
    title: "The board froze",
    description: "Screenshots attached.",
    userId: USER,
    userName: "Dana",
    userEmail: "dana@example.com",
    sentAt: "2026-11-14T10:00:00Z",
    deviceType: "iPhone",
    osVersion: "iOS 26.3",
    locale: "en",
    role: "student",
    ...extra,
  };
}

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0xff, 0xd9]);

function writeRequest(uid: string, data: Record<string, unknown>) {
  return setDoc(doc(env.authenticatedContext(uid).firestore(), "contactRequests", REQUEST_ID), data);
}

function upload(uid: string, objectPath: string, contentType = "image/jpeg", bytes: Uint8Array = JPEG) {
  return uploadBytes(ref(env.authenticatedContext(uid).storage(), objectPath), bytes, { contentType });
}

describe("contactRequests", () => {
  it("still accepts a request without attachments, as older apps send it", async () => {
    await assertSucceeds(writeRequest(USER, request()));
  });

  it("accepts an attachment count from 0 to 3", async () => {
    for (const count of [0, 1, 3]) {
      await assertSucceeds(writeRequest(USER, request({ attachmentCount: count })));
      await env.clearFirestore();
    }
  });

  it("refuses a count over 3, below 0, or not a whole number", async () => {
    for (const count of [4, -1, 1.5, "2"]) {
      await assertFails(writeRequest(USER, request({ attachmentCount: count })));
    }
  });

  it("refuses any other new field, such as a list of paths", async () => {
    await assertFails(writeRequest(USER, request({ attachments: ["contactAttachments/user-2/x/0.jpg"] })));
  });
});

describe("contactAttachments", () => {
  const own = (file: string) => `contactAttachments/${USER}/${REQUEST_ID}/${file}`;

  it("lets the sender upload a JPEG at index 0, 1 or 2 and read it back", async () => {
    for (const file of ["0.jpg", "1.jpg", "2.jpg"]) {
      await assertSucceeds(upload(USER, own(file)));
    }
    await assertSucceeds(getBytes(ref(env.authenticatedContext(USER).storage(), own("0.jpg"))));
  });

  it("refuses another user's folder, both to write and to read", async () => {
    await assertFails(upload(OTHER, own("0.jpg")));
    await assertSucceeds(upload(USER, own("0.jpg")));
    await assertFails(getBytes(ref(env.authenticatedContext(OTHER).storage(), own("0.jpg"))));
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), own("0.jpg"))));
  });

  it("refuses a fourth image, another name, or anything but a JPEG", async () => {
    await assertFails(upload(USER, own("3.jpg")));
    await assertFails(upload(USER, own("notes.pdf"), "application/pdf"));
    await assertFails(upload(USER, own("0.jpg"), "image/png"));
    await assertFails(upload(USER, own("0.jpg"), "text/html"));
  });

  it("refuses an image of 10 MB or more", async () => {
    await assertFails(upload(USER, own("0.jpg"), "image/jpeg", new Uint8Array(10 * 1024 * 1024)));
  });
});
