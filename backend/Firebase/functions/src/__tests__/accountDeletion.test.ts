const mockRecords = new Map<string, any[]>();
const mockRemove = jest.fn().mockResolvedValue(undefined);
const mockDeleteFiles = jest.fn().mockResolvedValue(undefined);
const mockRecursiveDelete = jest.fn().mockResolvedValue(undefined);
const mockDeleteUser = jest.fn().mockResolvedValue(undefined);
const mockVerifyToken = jest.fn().mockResolvedValue({ uid: "owner" });
const mockCollection = (path: string): any => ({
  doc: (id: string) => ({ path: `${path}/${id}`, collection: (name: string) => mockCollection(`${path}/${id}/${name}`) }),
  listDocuments: async () => [],
  where: (field: string, _op: string, value: string) => {
    const key = `${path}:${field}:${value}`;
    const query = {
      get: async () => ({ docs: mockRecords.get(key) || [], empty: !(mockRecords.get(key)?.length) }),
      limit: () => query,
    };
    return query;
  },
});
jest.mock("firebase-admin", () => ({
  firestore: () => ({ collection: mockCollection, recursiveDelete: mockRecursiveDelete }),
  database: () => ({ ref: () => ({ remove: mockRemove, once: async () => ({ forEach: () => undefined }) }) }),
  storage: () => ({ bucket: () => ({ deleteFiles: mockDeleteFiles }) }),
  auth: () => ({ verifyIdToken: mockVerifyToken, deleteUser: mockDeleteUser }),
}));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_options: any, handler: any) => handler,
  HttpsError: class extends Error { constructor(public code: string, message: string) { super(message); } },
}));
import { assertDeletionRequest, deleteAccountData, deleteAccount } from "../accountDeletion";

const request = () => ({
  auth: { uid: "owner", token: { auth_time: Math.floor(Date.now() / 1000), firebase: { sign_in_provider: "password" } } },
  data: { confirmDeletion: true, uid: "someone-else" },
  rawRequest: { headers: { authorization: "Bearer token" } },
} as any);

beforeEach(() => {
  jest.clearAllMocks();
  mockRecords.clear();
});

it("uses only the authenticated UID, never a caller-provided target", () => {
  expect(assertDeletionRequest(request())).toBe("owner");
});
it.each(["missing-auth", "unconfirmed", "stale", "google", "missing-time"])("rejects %s before deletion", async kind => {
  const req = request();
  if (kind === "missing-auth") req.auth = undefined;
  if (kind === "unconfirmed") req.data.confirmDeletion = false;
  if (kind === "stale") req.auth.token.auth_time -= 301;
  if (kind === "google") req.auth.token.firebase.sign_in_provider = "google.com";
  if (kind === "missing-time") delete req.auth.token.auth_time;
  await expect((deleteAccount as any)(req)).rejects.toThrow();
  expect(mockDeleteUser).not.toHaveBeenCalled();
  expect(mockRecursiveDelete).not.toHaveBeenCalled();
});
it("does not delete any data during an active lesson", async () => {
  mockRecords.set("lessons:studentUid:owner", [{ data: () => ({ status: "in_progress" }) }]);
  await expect(deleteAccountData("owner")).rejects.toThrow("End your active lesson");
  expect(mockRecursiveDelete).not.toHaveBeenCalled();
  expect(mockDeleteFiles).not.toHaveBeenCalled();
});
it("removes nested user data and uploads before deleting Auth", async () => {
  await (deleteAccount as any)(request());
  expect(mockRecursiveDelete).toHaveBeenCalledWith(expect.objectContaining({ path: "users/owner" }));
  expect(mockRecursiveDelete).toHaveBeenCalledWith(expect.objectContaining({ path: "teachers/owner" }));
  expect(mockDeleteFiles).toHaveBeenCalledWith({ prefix: "documents/owner/" });
  expect(mockDeleteFiles).toHaveBeenCalledWith({ prefix: "questionImages/owner/" });
  expect(mockDeleteUser).toHaveBeenCalledWith("owner");
  expect(mockRecursiveDelete.mock.invocationCallOrder.at(-1)).toBeLessThan(mockDeleteUser.mock.invocationCallOrder[0]);
});
it("keeps Auth available for a retry if cleanup fails", async () => {
  mockDeleteFiles.mockRejectedValueOnce(new Error("storage unavailable"));
  await expect((deleteAccount as any)(request())).rejects.toThrow("storage unavailable");
  expect(mockDeleteUser).not.toHaveBeenCalled();
});
it("rejects a revoked session before touching data", async () => {
  mockVerifyToken.mockRejectedValueOnce(new Error("revoked"));
  await expect((deleteAccount as any)(request())).rejects.toThrow("revoked");
  expect(mockRecursiveDelete).not.toHaveBeenCalled();
});
