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
