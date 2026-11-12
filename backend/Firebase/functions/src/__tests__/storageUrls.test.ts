import { isOwnQuestionImageUrl, storageObjectPath } from "../storageUrls";

const BUCKET = "teacher-in-a-moment.firebasestorage.app";

/** What StorageService.uploadQuestionImage hands back. */
function downloadUrl(objectPath: string, bucket: string = BUCKET): string {
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media&token=3f2b1c8e-0000-4aaa-9bbb-ccccdddd0000`
  );
}

describe("storageObjectPath", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv, GCLOUD_PROJECT: "teacher-in-a-moment" };
    delete process.env.STORAGE_BUCKET;
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  test("reads the object path out of a Firebase download URL", () => {
    expect(storageObjectPath(downloadUrl("questionImages/student-1/1757000000000.jpg"))).toBe(
      "questionImages/student-1/1757000000000.jpg"
    );
  });

  test("accepts the legacy appspot.com spelling of the same bucket", () => {
    expect(
      storageObjectPath(
        downloadUrl("questionImages/student-1/1.jpg", "teacher-in-a-moment.appspot.com")
      )
    ).toBe("questionImages/student-1/1.jpg");
  });

  test("accepts a plain Cloud Storage URL", () => {
    expect(
      storageObjectPath(`https://storage.googleapis.com/${BUCKET}/questionImages/student-1/1.jpg`)
    ).toBe("questionImages/student-1/1.jpg");
  });

  test("accepts a bucket named by STORAGE_BUCKET", () => {
    process.env.STORAGE_BUCKET = "some-other-bucket.example";
    expect(
      storageObjectPath(downloadUrl("questionImages/student-1/1.jpg", "some-other-bucket.example"))
    ).toBe("questionImages/student-1/1.jpg");
  });

  test.each([
    ["another project's bucket", downloadUrl("questionImages/student-1/1.jpg", "someone-else.appspot.com")],
    ["a look-alike host", "https://firebasestorage.googleapis.com.evil.test/v0/b/x/o/y.jpg"],
    ["an unrelated host", "https://evil.test/questionImages/student-1/1.jpg"],
    ["plain http", `http://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/x.jpg`],
    ["a non-URL", "not a url"],
    ["an empty string", ""],
    ["a number", 42],
    ["null", null],
  ])("rejects %s", (_label, value) => {
    expect(storageObjectPath(value)).toBeUndefined();
  });
});

describe("isOwnQuestionImageUrl", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv, GCLOUD_PROJECT: "teacher-in-a-moment" };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  test("accepts the student's own question photo", () => {
    expect(
      isOwnQuestionImageUrl(downloadUrl("questionImages/student-1/1757000000000.jpg"), "student-1")
    ).toBe(true);
  });

  test.each([
    ["another student's photo", "questionImages/student-2/1.jpg"],
    ["a uid that merely starts the same", "questionImages/student-12/1.jpg"],
    ["someone's identity documents", "documents/student-1/govId.jpg"],
    ["a profile image", "profileImages/student-1/profile.jpg"],
    ["a board snapshot", "boardSnapshots/q-1/1.jpg"],
    ["a traversal attempt", "questionImages/student-1/../documents/student-2/govId.jpg"],
  ])("rejects %s", (_label, objectPath) => {
    expect(isOwnQuestionImageUrl(downloadUrl(objectPath), "student-1")).toBe(false);
  });

  test("rejects everything when the caller has no uid", () => {
    expect(isOwnQuestionImageUrl(downloadUrl("questionImages/student-1/1.jpg"), "")).toBe(false);
  });
});

describe("the Storage emulator's download URLs", () => {
  const originalEnv = { ...process.env };
  const path = "questionImages/student-1/1757000000000.jpg";
  const emulatorUrl = (host: string, bucket = "demo-teacher-in-a-moment.appspot.com") =>
    `http://${host}/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=t`;

  beforeEach(() => {
    process.env = { ...originalEnv, GCLOUD_PROJECT: "demo-teacher-in-a-moment" };
    delete process.env.STORAGE_BUCKET;
    delete process.env.FUNCTIONS_EMULATOR;
    delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  test("are accepted in the Functions emulator, from a simulator or an Android emulator", () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";

    expect(storageObjectPath(emulatorUrl("127.0.0.1:9199"))).toBe(path);
    expect(storageObjectPath(emulatorUrl("10.0.2.2:9199"))).toBe(path);
    expect(isOwnQuestionImageUrl(emulatorUrl("127.0.0.1:9199"), "student-1")).toBe(true);
  });

  test("are refused outside the emulator, as any plain http URL is", () => {
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";

    expect(storageObjectPath(emulatorUrl("127.0.0.1:9199"))).toBeUndefined();
  });

  test("still need our bucket and the emulator's port", () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";

    expect(storageObjectPath(emulatorUrl("127.0.0.1:9199", "someone-else.appspot.com"))).toBeUndefined();
    expect(storageObjectPath(emulatorUrl("evil.example.com:8080"))).toBeUndefined();
  });
});
